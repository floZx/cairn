import SwiftUI
import SwiftData

/// La liste des gens cités dans les notes.
///
/// Rien ne s'y ajoute à la main : une personne y entre parce qu'on l'a citée
/// quelque part, et en sort quand plus aucune note ne la nomme — sauf si on a
/// écrit quelque chose sur elle, auquel cas elle reste en bas. Voir
/// `PeopleIndex.lignes`.
struct PeopleView: View {
    @Binding var selection: String?
    /// Entrée ou `e` : le curseur dans la note de la personne ouverte.
    var onEdit: () -> Void = {}
    /// Ce que la liste ne traite pas elle-même — changer de section, l'aide.
    var onCommand: (VimCommand) -> Bool = { _ in false }

    @Query private var journalNotes: [JournalNote]
    @Query private var activities: [Activity]
    @Query private var mealNotes: [MealNote]
    @Query private var weights: [WeightEntry]
    @Query private var sessions: [PlannedSession]
    @Query private var slots: [MealSlot]
    @Query private var people: [Person]

    /// Tous les textes de la bibliothèque, réduits à ce que l'index lit.
    ///
    /// Calculé dans le corps de la vue, comme `SameRouteSection` : un `@Query`
    /// ne se matérialise qu'à la lecture, et un calcul fait hors rendu verrait
    /// une bibliothèque vide sans jamais qu'on le lui dise.
    static func textes(
        journalNotes: [JournalNote], activities: [Activity], mealNotes: [MealNote],
        weights: [WeightEntry], sessions: [PlannedSession], slots: [MealSlot]
    ) -> [PeopleIndex.Texte] {
        var textes: [PeopleIndex.Texte] = []
        for note in journalNotes {
            guard let jour = note.dateKey else { continue }
            textes.append(.init(dateKey: jour, source: .journal, contenu: note.text))
        }
        for sortie in activities {
            guard let texte = sortie.activityDescription, !texte.isEmpty else { continue }
            textes.append(.init(
                dateKey: DateKey(sortie.startLocalDate), source: .sortie(sortie.name),
                contenu: texte, activityUUID: sortie.uuid
            ))
        }
        let nomDuCreneau = Dictionary(
            slots.map { ($0.uuid, $0.name) }, uniquingKeysWith: { premier, _ in premier }
        )
        for note in mealNotes {
            guard let jour = note.dateKey else { continue }
            let creneau = note.mealSlot.flatMap { nomDuCreneau[$0.uuid] } ?? "Repas"
            textes.append(.init(dateKey: jour, source: .repas(creneau), contenu: note.note))
        }
        for pesee in weights {
            guard let jour = pesee.dateKey, let mot = pesee.note, !mot.isEmpty else { continue }
            textes.append(.init(dateKey: jour, source: .pesee, contenu: mot))
        }
        for seance in sessions {
            guard let jour = seance.dateKey, !seance.notes.isEmpty else { continue }
            textes.append(.init(
                dateKey: jour,
                source: .seance(seance.title.isEmpty ? seance.sport.displayName : seance.title),
                contenu: seance.notes
            ))
        }
        return textes
    }

    var body: some View {
        let citations = PeopleIndex.citations(
            dans: Self.textes(
                journalNotes: journalNotes, activities: activities, mealNotes: mealNotes,
                weights: weights, sessions: sessions, slots: slots
            )
        )
        let lignes = PeopleIndex.lignes(
            citations: citations, fiches: people.map { (key: $0.key, name: $0.name) }
        )

        Group {
            if lignes.isEmpty {
                ContentUnavailableView {
                    Label("Personne, pour l'instant", systemImage: "at")
                } description: {
                    Text(
                        "Citez quelqu'un dans une note avec « @prénom » et il apparaîtra ici."
                    )
                }
            } else {
                ScrollViewReader { defilement in
                List(lignes, selection: $selection) { ligne in
                    HStack(spacing: 8) {
                        Text(ligne.handle.displayName)
                            .font(.body.weight(.medium))
                        if ligne.aUneNote {
                            Image(systemName: "text.alignleft")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .help("Une note existe sur cette personne")
                        }
                        Spacer(minLength: 8)
                        // Pas de date : celle de la dernière citation ne dit
                        // rien qu'on vienne chercher ici, et elle arrivait
                        // avec une heure — minuit — qu'aucune note n'a jamais
                        // eue. Le compte suffit à ranger la liste, et l'ordre
                        // porte déjà la fraîcheur.
                        Text("\(ligne.compte)")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                            .monospacedDigit()
                            .frame(width: 30, alignment: .trailing)
                    }
                    .padding(.vertical, 2)
                    .tag(ligne.handle.key)
                    .id(ligne.handle.key)
                }
                // Au clavier, comme la liste du journal : `j` et `k` passent
                // d'une personne à l'autre, Entrée ou `e` ouvre sa note.
                .vimKeys { commande in
                    let cles = lignes.map(\.handle.key)
                    let actuel = selection.flatMap { cles.firstIndex(of: $0) } ?? 0
                    let cible: Int?
                    switch commande {
                    case let .move(delta): cible = actuel + delta
                    case .first: cible = 0
                    case .last: cible = cles.count - 1
                    case let .halfPage(bas): cible = actuel + (bas ? 1 : -1) * VimMotion.halfPageRows
                    case .edit, .editNotes:
                        guard selection != nil else { return false }
                        onEdit()
                        return true
                    default:
                        return onCommand(commande)
                    }
                    guard let cible, !cles.isEmpty else { return false }
                    let borne = min(max(cible, 0), cles.count - 1)
                    selection = cles[borne]
                    defilement.scrollTo(cles[borne])
                    return true
                }
                .onKeyPress(.return) {
                    guard selection != nil else { return .ignored }
                    onEdit()
                    return .handled
                }
                }
            }
        }
        .navigationTitle(lignes.count == 1 ? "1 personne" : "\(lignes.count) personnes")
        // Toujours quelqu'un d'ouvert, comme les fiches des activités : sans
        // sélection, la liste s'étalait sur toute la fenêtre, deux noms à un
        // bout et leur compte à l'autre.
        .onAppear { garder(lignes) }
        .onChange(of: selection) { _, _ in garder(lignes) }
        .onChange(of: lignes.map(\.handle.key)) { _, _ in garder(lignes) }
    }

    private func garder(_ lignes: [PeopleIndex.Ligne]) {
        if let cle = Self.selectionGardee(cles: lignes.map(\.handle.key), actuelle: selection) {
            selection = cle
        }
    }

    /// La personne à ouvrir pour que le volet ne reste jamais vide, ou nil
    /// quand celle qui l'est encore fait l'affaire.
    static func selectionGardee(cles: [String], actuelle: String?) -> String? {
        if let actuelle, cles.contains(actuelle) { return nil }
        return cles.first
    }
}
