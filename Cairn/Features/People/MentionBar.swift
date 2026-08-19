import SwiftUI
import SwiftData

/// La barre de propositions qui se pose sous un éditeur quand on tape `@`.
///
/// Une vue plutôt qu'un modificateur, parce qu'elle a besoin de ses propres
/// requêtes : les personnes déjà connues se déduisent des textes, et chaque
/// endroit qui l'emploierait devrait sinon les lui passer.
///
/// L'annuaire est calculé **une fois à l'apparition**, pas à chaque frappe :
/// relire les notes de la bibliothèque à chaque lettre pour proposer six noms
/// serait payer très cher un service très simple. Quelqu'un cité pour la
/// première fois dans la note qu'on est en train d'écrire n'y figure donc pas
/// encore, ce qui est sans conséquence — on est justement en train de taper
/// son nom en entier.
struct MentionBar: View {
    @Binding var texte: String

    @Query private var fiches: [Person]
    @Query private var journalNotes: [JournalNote]
    @Query private var activities: [Activity]

    @State private var annuaire: [PersonHandle] = []
    @State private var precedent = ""
    @State private var enCours: MentionCompletion.EnCours?

    private var propositions: [PersonHandle] {
        guard let enCours else { return [] }
        return MentionCompletion.propositions(pour: enCours.fragment, parmi: annuaire)
    }

    var body: some View {
        Group {
            if !propositions.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(propositions) { handle in
                            Button(handle.displayName) { choisir(handle) }
                                .buttonStyle(.borderless)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.quaternary, in: .capsule)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.never)
                .frame(height: 28)
            }
        }
        .onAppear {
            precedent = texte
            construireLAnnuaire()
        }
        .onChange(of: texte) { ancien, nouveau in
            defer { precedent = nouveau }
            guard let curseur = MentionCompletion.pointDInsertion(de: ancien, vers: nouveau)
            else {
                enCours = nil
                return
            }
            enCours = MentionCompletion.enCours(dans: nouveau, a: curseur)
        }
    }

    private func choisir(_ handle: PersonHandle) {
        guard let enCours else { return }
        texte = MentionCompletion.complete(texte, remplacant: enCours.plage, par: handle)
        precedent = texte
        self.enCours = nil
    }

    private func construireLAnnuaire() {
        var trouves = Set(fiches.compactMap { PersonHandle(name: $0.name) })
        trouves.formUnion(PersonScanner.mentions(inAny: journalNotes.map(\.text)))
        trouves.formUnion(PersonScanner.mentions(inAny: activities.map(\.activityDescription)))
        annuaire = trouves.sorted()
    }
}
