import SwiftUI
import SwiftData

/// La page d'une personne : ce qu'on a écrit sur elle, puis tout ce qui la
/// cite.
///
/// La fiche n'est créée qu'au moment où l'on écrit quelque chose — voir
/// `Person`. Tant que le champ reste vide, rien n'est rangé en base, et la
/// personne continue de n'exister que dans les phrases où on la nomme.
struct PersonDetailView: View {
    let handle: PersonHandle
    let citations: [PeopleIndex.Citation]
    let onSelectActivity: (String) -> Void

    @Environment(\.modelContext) private var context
    @Query private var people: [Person]

    @State private var note = ""
    @State private var charge = false

    private var fiche: Person? { people.first { $0.key == handle.key } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(handle.displayName)
                    .font(.largeTitle.weight(.semibold))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Note").font(.headline)
                    TextEditor(text: $note)
                        .citations($note)
                        .font(.system(size: 14))
                        .frame(minHeight: 110)
                        .padding(6)
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
        .onChange(of: handle.key) { _, _ in
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
            MarkdownText(markdown: citation.texte, baseSize: 14, hidesTagHashes: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 10))
        .contentShape(.rect)
        .onTapGesture {
            if let uuid = citation.activityUUID { onSelectActivity(uuid) }
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
        } else if !propre.isEmpty {
            context.insert(Person(handle: handle, note: texte))
        }
        try? context.save()
    }
}
