import SwiftUI
import SwiftData

/// La page d'une personne : ce qu'on a écrit sur elle, puis tout ce qui la
/// cite.
///
/// La fiche n'est créée qu'au moment où l'on écrit quelque chose — voir
/// `Person`. Tant que le champ reste vide, rien n'est rangé en base, et la
/// personne continue de n'exister que dans les phrases où on la nomme.
struct PersonDetailView: View {
    /// La personne ouverte, par sa clé repliée.
    let cle: String
    /// Aller là d'où vient une citation — la sortie, la journée du journal,
    /// celle des repas, la pesée, la séance.
    ///
    /// Une seule fermeture pour les cinq : c'est l'écran qui sait comment on
    /// s'y rend, et la page n'a qu'à dire de quelle citation il s'agit.
    let onOuvrirLaSource: (PeopleIndex.Citation) -> Void
    /// Le dossier où les pièces jointes du journal se résolvent.
    ///
    /// Sans lui, une citation venue d'une note illustrée affichait le chemin
    /// du fichier en toutes lettres — « pieces-jointes/2026-08-12-1.png » —
    /// au lieu de la photo. Signalé.
    let attachmentsBase: URL?

    @Environment(\.modelContext) private var context
    @Query private var people: [Person]
    @Query private var journalNotes: [JournalNote]
    @Query private var activities: [Activity]
    @Query private var mealNotes: [MealNote]
    @Query private var weights: [WeightEntry]
    @Query private var sessions: [PlannedSession]
    @Query private var slots: [MealSlot]

    /// Les citations de cette personne, et d'elle seule.
    private var citations: [PeopleIndex.Citation] {
        guard let handle else { return [] }
        return PeopleIndex.citations(
            dans: PeopleView.textes(
                journalNotes: journalNotes, activities: activities,
                mealNotes: mealNotes, weights: weights,
                sessions: sessions, slots: slots
            )
        )[handle] ?? []
    }

    /// Retrouvée par ses citations d'abord, par sa fiche ensuite : quelqu'un
    /// dont la note existe mais que plus aucune note ne cite doit rester
    /// ouvrable.
    private var handle: PersonHandle? {
        if let fiche = people.first(where: { $0.key == cle }) {
            return PersonHandle(name: fiche.name)
        }
        return PersonScanner.mentions(
            inAny: journalNotes.map(\.text) + activities.map(\.activityDescription)
        ).first { $0.key == cle }
    }

    @State private var note = ""
    @State private var charge = false
    @State private var noteFocus = false

    private var fiche: Person? { people.first { $0.key == cle } }

    var body: some View {
        guard let handle else { return AnyView(EmptyView()) }
        return AnyView(contenu(handle))
    }

    private func contenu(_ handle: PersonHandle) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(handle.displayName)
                    .font(.largeTitle.weight(.semibold))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Note").font(.headline)
                    CompletingNoteEditor(
                        texte: $note,
                        taille: 14,
                        focus: $noteFocus
                    )
                        .frame(minHeight: 110)
                        .padding(2)
                        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
                        .overlay(alignment: .topLeading) {
                            if note.isEmpty {
                                Text("Ce qu'il y a à retenir de cette personne…")
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 14)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                if citations.isEmpty {
                    Text("Aucune note ne la cite pour l'instant.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Citée \(citations.count) fois")
                        .font(.headline)
                    ForEach(citations) { citation in
                        citationView(citation)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            note = fiche?.note ?? ""
            charge = true
        }
        .onChange(of: cle) { _, _ in
            charge = false
            note = fiche?.note ?? ""
            charge = true
        }
        // Écrit au fil de la frappe : SwiftData enregistre tout seul, et
        // l'outbox part avec. Un bouton « Enregistrer » sur une note de trois
        // lignes serait une cérémonie de plus qu'il faudrait penser à faire.
        .onChange(of: note) { _, nouvelle in
            guard charge else { return }
            enregistrer(nouvelle)
        }
    }

    private func citationView(_ citation: PeopleIndex.Citation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(Format.fullDate(citation.dateKey.date()).capitalized)
                    .font(.caption.weight(.medium))
                Text("·").foregroundStyle(.tertiary)
                Text(citation.source.libelle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            MarkdownText(
                markdown: citation.texte, baseSize: 14, hidesTagHashes: true,
                attachmentsBase: attachmentsBase
            )
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 10))
        .contentShape(.rect)
        .onTapGesture { onOuvrirLaSource(citation) }
        .help("Aller à « \(citation.source.libelle) »")
    }

    /// Crée la fiche au premier caractère, la supprime au dernier effacé.
    ///
    /// Le second point compte autant que le premier : une fiche vide laissée
    /// derrière ferait rester la personne dans la liste alors que plus rien ne
    /// la cite ni ne la décrit.
    private func enregistrer(_ texte: String) {
        let propre = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fiche {
            if propre.isEmpty {
                context.delete(fiche)
            } else {
                fiche.note = texte
            }
        } else if !propre.isEmpty, let handle {
            context.insert(Person(handle: handle, note: texte))
        }
        try? context.save()
    }
}
