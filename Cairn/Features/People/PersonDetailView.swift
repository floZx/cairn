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
    /// celle des repas, la pesée.
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
    /// Change quand la liste demande la note : Entrée ou `e` sur une personne.
    var focusRequest = 0

    @Environment(\.modelContext) private var context
    @Query private var people: [Person]
    @Query private var journalNotes: [JournalNote]
    @Query private var activities: [Activity]
    @Query private var mealNotes: [MealNote]
    @Query private var weights: [WeightEntry]
    @Query private var slots: [MealSlot]

    /// Les citations de cette personne, et d'elle seule.
    private var citations: [PeopleIndex.Citation] {
        guard let handle else { return [] }
        return PeopleIndex.citations(
            dans: PeopleView.textes(
                journalNotes: journalNotes, activities: activities,
                mealNotes: mealNotes, weights: weights, slots: slots
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
    /// La note se lit rendue et s'écrit au clic, comme celle d'une sortie :
    /// un champ toujours ouvert en tête de page se lisait comme un formulaire,
    /// et son Markdown restait brut.
    @State private var enEdition = false

    private var fiche: Person? { people.first { $0.key == cle } }

    var body: some View {
        guard let handle else { return AnyView(EmptyView()) }
        return AnyView(
            contenu(handle)
                // Entrée ou `e` depuis la liste : droit dans l'éditeur.
                .onChange(of: focusRequest) { _, _ in commencerLaNote() }
        )
    }

    private func contenu(_ handle: PersonHandle) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // L'en-tête de sa carte, en grand : médaillon, nom, et combien
                // de notes la citent.
                HStack(spacing: 14) {
                    PersonMonogram(handle: handle, size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(handle.displayName)
                            .font(.largeTitle.weight(.semibold))
                            .lineLimit(1)
                        if !citations.isEmpty {
                            Text(citations.count == 1 ? "1 note" : "\(citations.count) notes")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Note")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if enEdition {
                            Text("Échap pour terminer")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    noteDeLaPersonne
                }

                if citations.isEmpty {
                    Text("Aucune note ne la cite pour l'instant.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes qui la citent")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        // Les lignes survolées débordent de huit points : le
                        // texte, lui, reste aligné sur le reste de la page.
                        VStack(spacing: 2) {
                            ForEach(citations) { citation in
                                citationView(citation)
                            }
                        }
                        .padding(.horizontal, -8)
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
            enEdition = false
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

    /// La note rendue, l'éditeur, ou l'invitation à écrire — les trois états
    /// de celle d'une sortie, sur la même surface.
    @ViewBuilder
    private var noteDeLaPersonne: some View {
        let ecrite = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if enEdition {
            CompletingNoteEditor(
                texte: $note,
                taille: 14,
                focus: $noteFocus,
                onEchappement: { enEdition = false }
            )
                .frame(minHeight: 110)
                .padding(2)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
                // Quitter le champ referme l'éditeur : la note est déjà
                // enregistrée au fil de la frappe.
                .onChange(of: noteFocus) { _, focus in
                    if !focus { enEdition = false }
                }
        } else if ecrite.isEmpty {
            Button(action: commencerLaNote) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Écrire une note")
                        Text("Ce qu'il y a à retenir de cette personne.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        } else {
            // Pas de `textSelection`, pour la raison de la note d'une sortie :
            // un texte sélectionnable prend le clic pour lui, et seul le vide
            // à côté des mots ouvrait l'éditeur.
            MarkdownText(
                markdown: note, baseSize: 14, hidesTagHashes: true,
                attachmentsBase: attachmentsBase
            )
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
            .contentShape(.rect)
            .onTapGesture(perform: commencerLaNote)
        }
    }

    private func commencerLaNote() {
        enEdition = true
        noteFocus = true
    }

    private func citationView(_ citation: PeopleIndex.Citation) -> some View {
        PersonDetailCitation(citation: citation, attachmentsBase: attachmentsBase) {
            onOuvrirLaSource(citation)
        }
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
        Log.journal.attempt("note d'une personne") { try context.save() }
    }
}

/// Une citation sur la page d'une personne : la ligne de sa carte, en entier.
///
/// La tuile du jour, le mois et la source, puis le texte rendu — photos
/// comprises, ce qu'un extrait de popover n'a pas à porter. Pas de carte
/// autour : le survol suffit à dire qu'on peut y aller.
struct PersonDetailCitation: View {
    let citation: PeopleIndex.Citation
    let attachmentsBase: URL?
    let ouvrir: () -> Void

    @State private var survolee = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            JournalDateTile(date: citation.dateKey)
            VStack(alignment: .leading, spacing: 3) {
                Text(
                    JournalRowLayout.monthTitle(citation.dateKey).capitalized
                    + " · " + citation.source.libelle
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                MarkdownText(
                    markdown: citation.texte, baseSize: 14, hidesTagHashes: true,
                    attachmentsBase: attachmentsBase
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.primary.opacity(survolee ? 0.05 : 0))
        )
        .contentShape(.rect)
        .onHover { survolee = $0 }
        .onTapGesture(perform: ouvrir)
        .help("Aller à « \(citation.source.libelle) »")
    }
}
