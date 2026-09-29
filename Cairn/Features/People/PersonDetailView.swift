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
    /// Change quand la liste demande de la renommer.
    var renameRequest = 0
    /// Sa nouvelle clé, une fois renommée.
    var onRenommee: (String) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    /// Optionnel, comme pour `MarkdownText` : le journal se réécrit par son
    /// magasin, qui n'existe que dans l'application montée.
    @Environment(AppEnvironment.self) private var app: AppEnvironment?
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
            ),
            annuaire: annuaire
        )[handle] ?? []
    }

    private var annuaire: PeopleIndex.Annuaire { PeopleIndex.Annuaire(people: people) }

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
    /// Le nom en cours d'ajout aux alias, champ ouvert ; nil, champ fermé.
    @State private var nouvelAlias: String?
    @FocusState private var champAlias: Bool
    /// Le nom en cours de saisie dans la fenêtre de renommage ; nil, fermée.
    @State private var nouveauNom: String?
    @State private var refusDuNom: String?

    private var fiche: Person? { people.first { $0.key == cle } }

    var body: some View {
        guard let handle else { return AnyView(EmptyView()) }
        return AnyView(
            contenu(handle)
                // Entrée ou `e` depuis la liste : droit dans l'éditeur.
                .onChange(of: focusRequest) { _, _ in commencerLaNote() }
                .onChange(of: renameRequest) { _, _ in nouveauNom = handle.name }
                .alert(
                    "Renommer \(handle.name)",
                    isPresented: Binding(
                        get: { nouveauNom != nil }, set: { if !$0 { nouveauNom = nil } }
                    )
                ) {
                    TextField("Nouveau nom", text: Binding(
                        get: { nouveauNom ?? "" }, set: { nouveauNom = $0 }
                    ))
                    Button("Renommer") { renommer(handle) }
                    Button("Annuler", role: .cancel) { nouveauNom = nil }
                } message: {
                    Text(citations.isEmpty
                         ? "Aucune note ne la cite encore."
                         : "\(citations.count == 1 ? "La note" : "Les \(citations.count) notes") qui la citent seront réécrites avec le nouveau nom.")
                }
                .alert(
                    "Impossible de renommer",
                    isPresented: Binding(
                        get: { refusDuNom != nil }, set: { if !$0 { refusDuNom = nil } }
                    )
                ) {
                    Button("OK", role: .cancel) { refusDuNom = nil }
                } message: {
                    Text(refusDuNom ?? "")
                }
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
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(handle.displayName)
                                .font(.largeTitle.weight(.semibold))
                                .lineLimit(1)
                            Button {
                                nouveauNom = handle.name
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Renommer — chaque note qui la cite est réécrite")
                        }
                        if !citations.isEmpty {
                            Text(citations.count == 1 ? "1 note" : "\(citations.count) notes")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                autresNoms(handle)

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

    /// « Autres noms » : les alias en pastilles, qu'on retire d'un clic, et
    /// un champ pour en ajouter — ajouter un nom qui avait sa propre fiche la
    /// fond dans celle-ci, voir `PersonAliases`.
    private func autresNoms(_ handle: PersonHandle) -> some View {
        HStack(spacing: 6) {
            Text("Autres noms")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(annuaire.alias(de: handle)) { alias in
                HStack(spacing: 4) {
                    Text(alias.name)
                    Button {
                        guard let fiche else { return }
                        PersonAliases.retirer(alias, de: fiche, context: context)
                        Log.journal.attempt("alias d'une personne") { try context.save() }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Ne plus compter « \(alias.name) » comme \(handle.name)")
                }
                .font(.callout)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(.quaternary.opacity(0.5), in: .capsule)
            }
            if nouvelAlias != nil {
                TextField("Autre nom", text: Binding(
                    get: { nouvelAlias ?? "" }, set: { nouvelAlias = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.callout)
                .frame(width: 120)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(.quaternary.opacity(0.5), in: .capsule)
                .focused($champAlias)
                .onSubmit { ajouterLAlias(a: handle) }
                .onExitCommand { nouvelAlias = nil }
                .onChange(of: champAlias) { _, focus in
                    if !focus { nouvelAlias = nil }
                }
            } else {
                Button {
                    nouvelAlias = ""
                    champAlias = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .background(.quaternary.opacity(0.5), in: .circle)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Ajouter un autre nom sous lequel on la cite")
            }
        }
        .focusEffectDisabled()
    }

    private func ajouterLAlias(a principal: PersonHandle) {
        let tape = (nouvelAlias ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "@ "))
        nouvelAlias = nil
        guard let alias = PersonHandle(name: tape) else { return }
        PersonAliases.fusionner(alias, dans: principal, context: context)
        Log.journal.attempt("alias d'une personne") { try context.save() }
    }

    /// Réécrit chaque `@ancien` en `@nouveau` — le journal par son magasin,
    /// le reste par `PersonRename` —, puis suit la personne sous son nouveau
    /// nom.
    private func renommer(_ ancien: PersonHandle) {
        let tape = nouveauNom ?? ""
        nouveauNom = nil
        let connus = Array(PersonScanner.mentions(
            inAny: journalNotes.map(\.text) + activities.map(\.activityDescription)
                + mealNotes.map(\.note) + weights.map(\.note)
        )) + people.compactMap { PersonHandle(name: $0.name) }
            + people.flatMap { $0.aliases.compactMap(PersonHandle.init(name:)) }
        switch PersonRename.refus(tape, pour: ancien, connus: connus) {
        case .nomInvalide:
            refusDuNom = "« \(tape) » n'est pas un nom de personne : des lettres, des chiffres, - ou _, sans espace."
            return
        case .inchange:
            return
        case let .dejaPris(autre):
            refusDuNom = "\(autre.name) existe déjà. Pour les réunir, utilise « C'est aussi… » dans la liste."
            return
        case nil:
            break
        }
        guard let nouveau = PersonHandle(name: tape.trimmingCharacters(in: CharacterSet(charactersIn: "@ ")))
        else { return }
        enEdition = false
        app?.journal.reecrire { PersonRename.remplacer(dans: $0, ancien: ancien, par: nouveau) }
        PersonRename.renommer(ancien, en: nouveau, context: context)
        Log.journal.attempt("renommage d'une personne") { try context.save() }
        onRenommee(nouveau.key)
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
            fiche.note = propre.isEmpty ? "" : texte
            // Vide, elle ne part que si aucun alias ne la retient.
            PersonAliases.supprimerSiVide(fiche, context: context)
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
