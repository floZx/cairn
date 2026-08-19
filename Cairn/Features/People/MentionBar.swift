import SwiftUI
import SwiftData

/// La barre de propositions qui se pose sous un éditeur quand on tape `@`.
///
/// Une vue plutôt qu'un modificateur, parce qu'elle a besoin de ses propres
/// requêtes : les personnes déjà connues se déduisent des textes, et chaque
/// endroit qui l'emploierait devrait sinon les lui passer.
struct MentionBar: View {
    @Binding var texte: String

    @Query private var fiches: [Person]
    @Query private var journalNotes: [JournalNote]
    @Query private var activities: [Activity]

    @State private var enCours: MentionCompletion.EnCours?

    /// L'annuaire n'est parcouru **que** pendant qu'une citation s'écrit.
    ///
    /// Calculé à la demande plutôt que rangé à l'apparition : la version
    /// précédente le construisait dans un `onAppear` posé sur une vue qui ne
    /// rendait rien tant qu'il n'y avait rien à proposer — et une vue vide ne
    /// reçoit pas ses événements de cycle de vie. L'annuaire restait donc
    /// désespérément vide, et la barre muette. Signalé, et c'est la cause.
    ///
    /// Le coût est celui d'une lecture des notes par lettre tapée **après un
    /// `@`**, c'est-à-dire quelques-unes par citation. Le reste du temps, ce
    /// `guard` rend la propriété gratuite.
    private var annuaire: [PersonHandle] {
        guard enCours != nil else { return [] }
        var trouves = Set(fiches.compactMap { PersonHandle(name: $0.name) })
        trouves.formUnion(PersonScanner.mentions(inAny: journalNotes.map(\.text)))
        trouves.formUnion(PersonScanner.mentions(inAny: activities.map(\.activityDescription)))
        return trouves.sorted()
    }

    private var propositions: [PersonHandle] {
        guard let enCours else { return [] }
        return MentionCompletion.propositions(pour: enCours.fragment, parmi: annuaire)
    }

    var body: some View {
        // Un conteneur qui existe toujours, même sans rien à montrer : c'est
        // lui qui porte le `onChange`, et une branche `if` qui disparaît
        // emporterait l'observation avec elle.
        VStack(spacing: 0) {
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
        .onChange(of: texte) { ancien, nouveau in
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
        self.enCours = nil
    }
}
