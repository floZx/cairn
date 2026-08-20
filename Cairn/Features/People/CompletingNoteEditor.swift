import SwiftUI
import SwiftData

/// Un éditeur de note, avec la complétion des citations sous le curseur.
///
/// La liste suivait le bord du champ, faute de savoir où était le curseur :
/// dans un volet qui fait toute la hauteur de la fenêtre, elle se retrouvait à
/// l'autre bout de l'écran. `NoteTextView` rend ce rectangle, et la liste vient
/// se poser où l'on regarde.
///
/// Éprouvé d'abord sur le seul journal, puis posé partout : c'est le même
/// geste dans les six champs, et deux mécaniques de complétion auraient
/// divergé au premier correctif.
struct CompletingNoteEditor: View {
    @Binding var texte: String
    var taille: CGFloat
    @Binding var focus: Bool
    /// Ce que l'échappement fait quand aucune complétion n'est ouverte.
    ///
    /// Facultatif : sans lui, l'éditeur se contente de rendre le clavier, et
    /// l'échappement suivant va où il irait normalement — fermer la feuille,
    /// par exemple.
    var onEchappement: (() -> Void)?
    /// Ce qu'une image collée devient. Seul le journal en accepte.
    var onImageCollee: ((Data) -> Bool)?

    /// L'annuaire se lit à la demande, pas par `@Query`.
    ///
    /// Trois `@Query` vivaient ici, dont une sur les huit cents sorties — dans
    /// **chacun** des six champs de saisie. Or le journal écrit à chaque
    /// frappe, et une écriture invalide toute requête ouverte : taper une
    /// phrase relançait donc la lecture de la bibliothèque entière, lettre
    /// après lettre. C'est ce qui rendait la saisie poussive et le texte
    /// hésitant.
    ///
    /// Ici, rien ne se lit tant qu'aucune arobase n'a été tapée, et la lecture
    /// n'a lieu qu'une fois par séance d'écriture. Conséquence assumée :
    /// quelqu'un cité pour la première fois pendant qu'on écrit n'entre pas
    /// dans l'annuaire avant le champ suivant — on est justement en train de
    /// taper son nom en entier.
    @Environment(\.modelContext) private var context
    @State private var annuaire: [PersonHandle] = []
    @State private var annuaireLu = false

    @State private var enCours: MentionCompletion.EnCours?
    @State private var retenue = 0
    @State private var curseur = CGRect.zero
    /// Où poser le curseur après une insertion, une fois.
    @State private var curseurDemande: Int?

    private func lireLAnnuaire() {
        guard !annuaireLu else { return }
        annuaireLu = true

        var trouves = Set(
            ((try? context.fetch(FetchDescriptor<Person>())) ?? [])
                .compactMap { PersonHandle(name: $0.name) }
        )
        // La note en cours d'écriture est écartée de son propre annuaire : le
        // journal enregistre à la frappe, et « @To » à moitié tapé se
        // proposait sinon lui-même.
        let notes = ((try? context.fetch(FetchDescriptor<JournalNote>())) ?? [])
            .map(\.text)
            .filter { $0 != texte }
        trouves.formUnion(PersonScanner.mentions(inAny: notes))

        // Seules les sorties qui portent une note : les autres ne peuvent
        // citer personne, et les lire toutes revenait à parcourir la
        // bibliothèque pour rien.
        let decrites = FetchDescriptor<Activity>(
            predicate: #Predicate { $0.activityDescription != nil }
        )
        trouves.formUnion(
            PersonScanner.mentions(
                inAny: ((try? context.fetch(decrites)) ?? []).map(\.activityDescription)
            )
        )
        annuaire = trouves.sorted()
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
            curseurDemande: $curseurDemande,
            onCommande: commande,
            onCurseur: { curseur = $0 },
            onImageCollee: { onImageCollee?($0) ?? false }
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
            if enCours != nil { lireLAnnuaire() }
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
            guard ouverte else {
                // Rien à refermer : l'écran décide, et sans consigne l'éditeur
                // rendra simplement le clavier.
                guard let onEchappement else { return false }
                onEchappement()
                return true
            }
            enCours = nil
            return true
        }
    }

    private func choisir(_ handle: PersonHandle) {
        guard let enCours else { return }
        let complete = MentionCompletion.complete(
            texte, remplacant: enCours.plage, par: handle
        )
        // La position d'abord : le texte qui change déclenche la mise à jour de
        // l'éditeur, et elle doit y trouver la consigne déjà posée.
        curseurDemande = complete.curseur
        texte = complete.texte
        self.enCours = nil
        retenue = 0
    }
}
