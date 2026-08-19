import SwiftUI
import SwiftData

/// L'éditeur du journal, avec la complétion des citations sous le curseur.
///
/// La liste suivait jusqu'ici le bord du champ, faute de savoir où était le
/// curseur : dans un volet qui fait toute la hauteur de la fenêtre, elle se
/// retrouvait à l'autre bout de l'écran. `NoteTextView` rend ce rectangle,
/// et la liste vient enfin se poser où l'on regarde.
struct CompletingNoteEditor: View {
    @Binding var texte: String
    var taille: CGFloat
    @Binding var focus: Bool
    /// Ce que l'échappement fait quand aucune complétion n'est ouverte.
    var onEchappement: () -> Void
    var onImageCollee: (Data) -> Bool

    @Query private var fiches: [Person]
    @Query private var journalNotes: [JournalNote]
    @Query private var activities: [Activity]

    @State private var enCours: MentionCompletion.EnCours?
    @State private var retenue = 0
    @State private var curseur = CGRect.zero

    private var annuaire: [PersonHandle] {
        guard enCours != nil else { return [] }
        var trouves = Set(fiches.compactMap { PersonHandle(name: $0.name) })
        // La note en cours d'écriture est écartée de son propre annuaire : le
        // journal enregistre à la frappe, et « @To » à moitié tapé se
        // proposait sinon lui-même.
        trouves.formUnion(
            PersonScanner.mentions(inAny: journalNotes.map(\.text).filter { $0 != texte })
        )
        trouves.formUnion(PersonScanner.mentions(inAny: activities.map(\.activityDescription)))
        return trouves.sorted()
    }

    private var propositions: [PersonHandle] {
        guard let enCours else { return [] }
        return MentionCompletion.propositions(pour: enCours.fragment, parmi: annuaire)
    }

    private var ouverte: Bool { !propositions.isEmpty }

    var body: some View {
        NoteTextView(
            texte: $texte,
            taille: taille,
            focus: $focus,
            onCommande: commande,
            onCurseur: { curseur = $0 },
            onImageCollee: onImageCollee
        )
        .overlay(alignment: .topLeading) {
            if ouverte {
                liste
                    // Sous la ligne du curseur, pas dessus : une liste posée
                    // par-dessus le texte cacherait la phrase qu'on est en
                    // train d'écrire.
                    .offset(x: curseur.minX, y: curseur.maxY + 4)
            }
        }
        .onChange(of: texte) { ancien, nouveau in
            guard let position = MentionCompletion.pointDInsertion(de: ancien, vers: nouveau)
            else {
                enCours = nil
                return
            }
            enCours = MentionCompletion.enCours(dans: nouveau, a: position)
            retenue = 0
        }
    }

    private var liste: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(propositions.enumerated()), id: \.element.id) { rang, handle in
                HStack(spacing: 6) {
                    Text(handle.displayName)
                    Spacer(minLength: 12)
                    if rang == retenue {
                        Text("⇥").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .frame(minWidth: 150, alignment: .leading)
                .background(rang == retenue ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear))
                .contentShape(.rect)
                .onTapGesture { choisir(handle) }
            }
        }
        .font(.callout)
        .padding(.vertical, 3)
        .background(.regularMaterial, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
        .shadow(radius: 8, y: 2)
        .fixedSize()
    }

    private func commande(_ touche: NoteTextView.Commande) -> Bool {
        switch touche {
        case .tabulation:
            guard ouverte, propositions.indices.contains(retenue) else { return false }
            choisir(propositions[retenue])
            return true
        case .bas, .haut:
            guard ouverte else { return false }
            let pas = touche == .bas ? 1 : -1
            retenue = (retenue + pas + propositions.count) % propositions.count
            return true
        case .echappement:
            // Non traité quand rien n'est ouvert : c'est ce qui laisse
            // l'échappement du journal quitter le champ, comme avant.
            guard ouverte else {
                onEchappement()
                return true
            }
            enCours = nil
            return true
        }
    }

    private func choisir(_ handle: PersonHandle) {
        guard let enCours else { return }
        texte = MentionCompletion.complete(texte, remplacant: enCours.plage, par: handle)
        self.enCours = nil
        retenue = 0
    }
}
