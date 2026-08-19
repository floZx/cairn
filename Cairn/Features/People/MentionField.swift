import SwiftUI
import SwiftData

/// L'autocomplétion des citations, posée **sur** un éditeur.
///
/// Un modificateur et non une vue voisine, et c'est tout le sujet : les touches
/// arrivent à la vue qui a le focus — l'éditeur — et une barre posée à côté de
/// lui ne les voit jamais. Il fallait donc aller les chercher là où elles
/// tombent.
///
/// La première version proposait bien les noms mais obligeait à cliquer.
/// Quitter le clavier au milieu d'une phrase pour attraper la souris coûte
/// plus cher que de taper le prénom en entier, ce qui vidait la fonctionnalité
/// de son intérêt.
///
/// Les touches retenues :
///
/// - **⇥** accepte la proposition retenue. Tab plutôt qu'Entrée, qui doit
///   rester le passage à la ligne — une note s'écrit en paragraphes.
/// - **↓ ↑** changent de proposition, comme dans toutes les listes de
///   complétion. Elles ne déplacent le curseur que lorsque la barre est
///   fermée, c'est-à-dire presque toujours.
/// - **⎋** referme sans rien insérer. Rendue « non traitée » quand la barre
///   est déjà fermée, pour que les échappements des éditeurs — quitter le
///   champ, fermer la feuille — gardent leur sens.
struct MentionField: ViewModifier {
    @Binding var texte: String

    @Query private var fiches: [Person]
    @Query private var journalNotes: [JournalNote]
    @Query private var activities: [Activity]

    @State private var enCours: MentionCompletion.EnCours?
    @State private var retenue = 0

    private var annuaire: [PersonHandle] {
        guard enCours != nil else { return [] }
        var trouves = Set(fiches.compactMap { PersonHandle(name: $0.name) })
        // La note en cours d'écriture est écartée de son propre annuaire.
        //
        // Le journal enregistre à la frappe : « @To » à moitié tapé est déjà
        // dans le magasin, et se proposait donc lui-même — vu à l'écran, en
        // tête de liste, juste avant « @Tom ». Une complétion qui propose ce
        // qu'on est en train d'écrire ne sert à rien et occupe la place.
        //
        // Conséquence assumée : quelqu'un cité dans cette note et nulle part
        // ailleurs n'est pas proposé. On vient justement d'écrire son nom.
        let autres = journalNotes.map(\.text).filter { $0 != texte }
        trouves.formUnion(PersonScanner.mentions(inAny: autres))
        trouves.formUnion(
            PersonScanner.mentions(
                inAny: activities.map(\.activityDescription).filter { $0 != texte }
            )
        )
        return trouves.sorted()
    }

    private var propositions: [PersonHandle] {
        guard let enCours else { return [] }
        return MentionCompletion.propositions(pour: enCours.fragment, parmi: annuaire)
    }

    private var ouverte: Bool { !propositions.isEmpty }

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Au-dessus du champ, et non en dessous.
            //
            // `TextEditor` ne dit pas où est son curseur, donc la barre ne peut
            // pas le suivre. Reste à choisir le bord le moins mauvais : dans le
            // journal, l'éditeur occupe toute la hauteur du volet même pour
            // trois lignes, et une barre posée en bas se retrouvait à l'autre
            // bout de l'écran — signalé, capture à l'appui. En haut, elle est
            // à quelques centimètres des premières lignes, là où l'on écrit le
            // plus souvent.
            if ouverte {
                barre
            }
            content
                // Posées sur l'éditeur lui-même : c'est lui qui a le focus, et
                // `onKeyPress` ne voit que ce qui traverse la vue focalisée.
                .onKeyPress(.tab) { accepter() }
                .onKeyPress(.downArrow) { deplacer(1) }
                .onKeyPress(.upArrow) { deplacer(-1) }
                .onKeyPress(.escape) {
                    guard ouverte else { return .ignored }
                    enCours = nil
                    return .handled
                }
        }
        .onChange(of: texte) { ancien, nouveau in
            guard let curseur = MentionCompletion.pointDInsertion(de: ancien, vers: nouveau)
            else {
                enCours = nil
                return
            }
            enCours = MentionCompletion.enCours(dans: nouveau, a: curseur)
            retenue = 0
        }
    }

    private var barre: some View {
        HStack(spacing: 6) {
            ForEach(Array(propositions.enumerated()), id: \.element.id) { rang, handle in
                Button(handle.displayName) { choisir(handle) }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        rang == retenue ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                        in: .capsule
                    )
                    .foregroundStyle(rang == retenue ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            }
            Text("⇥ pour insérer")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .font(.callout)
    }

    private func accepter() -> KeyPress.Result {
        guard ouverte, propositions.indices.contains(retenue) else { return .ignored }
        choisir(propositions[retenue])
        return .handled
    }

    private func deplacer(_ pas: Int) -> KeyPress.Result {
        guard ouverte else { return .ignored }
        retenue = (retenue + pas + propositions.count) % propositions.count
        return .handled
    }

    private func choisir(_ handle: PersonHandle) {
        guard let enCours else { return }
        texte = MentionCompletion.complete(texte, remplacant: enCours.plage, par: handle)
        self.enCours = nil
        retenue = 0
    }
}

extension View {
    /// Complète les `@pseudo` tapés dans cet éditeur.
    func citations(_ texte: Binding<String>) -> some View {
        modifier(MentionField(texte: texte))
    }
}
