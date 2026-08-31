import Foundation
import SwiftData

/// The one rule for putting a text into a day's note.
///
/// Lifted out of `JournalStore.saveNow()` when `cairn-note` arrived: the
/// terminal writes the same notes the pane does, and a second copy of "empty
/// means gone" is a copy that drifts. The store keeps the typing, the
/// debounce and the list around it; what is left here is only the decision.
///
/// Takes a `ModelContext` rather than living on the store: the tool has no
/// store, and this rule never needed one.
enum JournalNoteWrite {
    /// What the write turned out to be, for a caller that has something to
    /// say about it. `JournalStore` ignores it; the tool prints it.
    enum Outcome {
        /// A day that had no note has one now.
        case created
        /// A note that existed was rewritten.
        case updated
        /// A note emptied to nothing, and taken out with it.
        case deleted
        /// Nothing was there, and nothing was typed: no row is made.
        case nothing
    }

    /// The row for that day, or nil. The one fetch, so the predicate is
    /// written once.
    static func row(for date: DateKey, in context: ModelContext) -> JournalNote? {
        let raw = date.raw
        var descriptor = FetchDescriptor<JournalNote>(
            predicate: #Predicate { $0.dateKeyRaw == raw }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Poses `text` as that day's note. Does not save: the caller decides
    /// when, and `JournalStore` has a debounce that depends on deciding it.
    @discardableResult
    static func apply(
        _ text: String, for date: DateKey, in context: ModelContext
    ) -> Outcome {
        if let existing = row(for: date, in: context) {
            existing.setText(text)
            // A note emptied to nothing goes, exactly as an emptied file used
            // to leave the vault: opening today's note and typing nothing must
            // not leave a blank day in the journal. The rule is
            // `JournalNote.isEmpty`, and it has not changed.
            //
            // The row goes; the note does not, when this is the pane calling.
            // That is a pause in the middle of writing — select-all, delete,
            // think — and `JournalStore.refresh()` puts the open day's row
            // back on its own.
            if existing.isEmpty {
                context.delete(existing)
                return .deleted
            }
            return .updated
        }
        let note = JournalNote(dateKey: date, text: text)
        // Never inserted at all when there is nothing to keep.
        guard !note.isEmpty else { return .nothing }
        context.insert(note)
        return .created
    }

    /// Un jour, une note.
    ///
    /// Deux appareils peuvent écrire la même journée sans se connaître : le
    /// Mac pose la sienne, le téléphone n'en voit aucune — la première n'est
    /// pas encore partie — et crée la sienne. Le miroir rapproche les notes
    /// par `uuid`, que ces deux-là n'ont justement pas en commun, alors il
    /// range les deux. La journée arrive ensuite en double dans la liste :
    /// deux lignes portant la même date, donc la même identité, et une
    /// sélection qui en allume deux. Constaté le 31 août 2026 sur le 21 août.
    ///
    /// Le jour est la seule clé que les deux côtés partagent, et c'est par
    /// elle qu'on les recolle — comme les sorties Strava se recollent par leur
    /// identifiant Strava (voir `MirrorEngine.adopterLesUUIDsDeStrava`).
    ///
    /// **Les textes sont recollés, pas arbitrés.** Les deux ont été écrits
    /// pour de bon et aucun n'a vu l'autre ; en garder un seul reviendrait à
    /// jeter en silence une soirée que quelqu'un a pris la peine de raconter.
    /// La ligne qui survit est la plus récemment touchée : c'est son `uuid`
    /// que les deux côtés partageront ensuite.
    ///
    /// N'enregistre pas, comme `apply` : l'appelant décide quand. Et il
    /// enregistre **hors** de `MirrorBookkeeping.perform`, sans quoi la fusion
    /// resterait sur ce Mac.
    ///
    /// - Returns: le nombre de lignes retirées.
    @discardableResult
    static func foldDuplicateDays(in context: ModelContext) -> Int {
        let rows = (try? context.fetch(FetchDescriptor<JournalNote>())) ?? []
        var parJour: [String: [JournalNote]] = [:]
        for row in rows {
            // Une ligne dont la date ne se lit pas n'a pas de journée à
            // laquelle appartenir : on la laisse où elle est plutôt que de la
            // fondre au hasard dans une autre.
            guard let jour = row.dateKey else { continue }
            parJour[jour.raw, default: []].append(row)
        }

        var retirees = 0
        for doublons in parJour.values where doublons.count > 1 {
            // Du plus ancien au plus récent : c'est l'ordre dans lequel la
            // journée s'est écrite, donc celui dans lequel elle se lit.
            let ordre = doublons.sorted { $0.updatedAt < $1.updatedAt }
            guard let survivante = ordre.last else { continue }
            let fondu = fusion(ordre.map(\.text))
            if fondu != survivante.text { survivante.setText(fondu) }
            for perdue in ordre.dropLast() {
                context.delete(perdue)
                retirees += 1
            }
        }
        return retirees
    }

    /// Recolle des textes en un seul, sans répéter ce qui s'y trouve déjà.
    ///
    /// Le test de contenance n'est pas une élégance. La ligne écartée dort
    /// encore dans le miroir et peut en revenir ; sans lui, chaque passage
    /// rallongerait la note d'une copie d'elle-même.
    static func fusion(_ textes: [String]) -> String {
        var gardes: [String] = []
        for texte in textes {
            let propre = texte.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !propre.isEmpty else { continue }
            if gardes.contains(where: { $0.contains(propre) }) { continue }
            // Et l'inverse : un texte qui contient l'un des précédents prend
            // sa place plutôt que de s'ajouter à côté.
            gardes.removeAll { propre.contains($0) }
            gardes.append(propre)
        }
        return gardes.joined(separator: "\n\n")
    }
}
