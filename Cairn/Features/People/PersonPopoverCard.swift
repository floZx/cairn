import SwiftUI
import SwiftData

/// La fiche d'une personne, en petit, au-dessus de la note qui la cite.
///
/// Ce qu'on a écrit **sur** elle, puis les cinq dernières notes qui la citent.
/// Cinq, parce qu'une popover se lit d'un coup d'œil : au-delà, c'est la page
/// complète qu'on veut, et le bouton du bas y mène.
///
/// Les cinq coûtent une relecture des textes de la bibliothèque, et c'est
/// assumé pour un clic — mais **pas** au prix de la lire entière : la requête
/// des sorties porte son filtre, si bien qu'on parcourt les cinquante-sept qui
/// ont écrit quelque chose et non les huit cent soixante-huit qui existent.
struct PersonPopoverCard: View {
    let handle: PersonHandle

    @Environment(\.ouvrirDansPeople) private var ouvrirDansPeople
    @Environment(\.ouvrirLaCitation) private var ouvrirLaCitation
    @Environment(\.dismiss) private var fermer
    /// La table des fiches ne contient que les personnes sur qui quelque chose
    /// a été écrit : quelques lignes, pas la bibliothèque.
    @Query private var fiches: [Person]

    // Les textes où quelqu'un peut être cité. Le filtre est dans la requête
    // pour les sorties : c'est la seule table où le rapport entre « en a
    // écrit » et « existe » est de un à quinze.
    @Query private var notesDuJournal: [JournalNote]
    @Query(filter: #Predicate<Activity> {
        $0.activityDescription != nil && $0.activityDescription != ""
    })
    private var sortiesQuiRacontent: [Activity]
    @Query private var notesDeRepas: [MealNote]
    @Query private var pesees: [WeightEntry]
    @Query private var creneaux: [MealSlot]

    /// Toutes ses citations, les plus récentes d'abord — `PeopleIndex.citations`
    /// les range déjà ainsi. La carte en montre cinq et compte le reste.
    private var citations: [PeopleIndex.Citation] {
        let index = PeopleIndex.citations(
            dans: PeopleView.textes(
                journalNotes: notesDuJournal, activities: sortiesQuiRacontent,
                mealNotes: notesDeRepas, weights: pesees, slots: creneaux
            )
        )
        return index[handle] ?? []
    }

    private var note: String? {
        let ecrit = (fiches.first { $0.key == handle.key }?.note ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ecrit.isEmpty ? nil : ecrit
    }

    var body: some View {
        let citations = citations
        VStack(alignment: .leading, spacing: 0) {
            enTete(total: citations.count)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            // Rien quand rien n'a été écrit : une phrase qui dit qu'il n'y a
            // rien occupe la place de ce qu'il n'y a pas, et la carte a mieux à
            // montrer — les notes qui la citent sont juste en dessous.
            if let note {
                // Rendue comme une note, parce que c'en est une : on y écrit
                // des tags et on y cite d'autres gens.
                MarkdownText(markdown: note, hidesTagHashes: true)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }

            if !citations.isEmpty {
                Divider()
                Text("Dernières notes")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                VStack(spacing: 0) {
                    ForEach(citations.prefix(5)) { citation in
                        PersonCitationRow(citation: citation, handle: handle) {
                            fermer()
                            ouvrirLaCitation(citation)
                        }
                    }
                }
                // Les lignes survolées s'arrondissent à huit points du bord,
                // et non à seize : le texte, lui, reste aligné sur l'en-tête.
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }

            // La fiche vit dans le journal : masqué, il n'y a plus où l'ouvrir.
            if !SidebarItem.journal.estMasquee {
                Divider()
                Button {
                    fermer()
                    ouvrirDansPeople(handle.key)
                } label: {
                    HStack(spacing: 4) {
                        Text("Voir sa fiche")
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
            }
        }
        // Rien ne reçoit le clavier ici, et c'est voulu : on n'arrive sur
        // cette carte qu'à la souris, et l'anneau bleu que macOS posait sur la
        // première note ne désignait rien qu'on allait taper.
        .focusEffectDisabled()
        // La popover hérite de l'interligne de la note qui l'a ouverte — celui,
        // généreux, de l'éditeur du journal. Une carte se lit serrée.
        .lineSpacing(1)
        .frame(width: 340, alignment: .leading)
    }

    /// L'initiale dans un médaillon, le nom, et combien de notes la citent.
    private func enTete(total: Int) -> some View {
        HStack(spacing: 10) {
            PersonMonogram(handle: handle, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(handle.displayName)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                if total > 0 {
                    Text(total == 1 ? "1 note" : "\(total) notes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// L'initiale d'une personne dans un médaillon teinté — ce que la photo est
/// à un contact, pour quelqu'un qui n'en a pas.
struct PersonMonogram: View {
    let handle: PersonHandle
    var size: CGFloat = 28

    var body: some View {
        Text(String(handle.name.prefix(1)).uppercased())
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: size, height: size)
            .background(Color.accentColor.opacity(0.14), in: .circle)
    }
}

/// Une note qui cite quelqu'un : le jour en tuile, comme dans les listes,
/// d'où elle vient, et l'extrait où son nom ressort.
///
/// Cliquable jusqu'au bout de la ligne : c'est un extrait, ce qu'on veut en
/// faire est aller le lire entier là où il a été écrit.
struct PersonCitationRow: View {
    let citation: PeopleIndex.Citation
    let handle: PersonHandle
    let action: () -> Void

    @State private var survolee = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                JournalDateTile(date: citation.dateKey)
                    .scaleEffect(0.85, anchor: .top)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        JournalRowLayout.monthTitle(citation.dateKey).capitalized
                        + " · " + citation.source.libelle
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    // Du texte nu et non du Markdown rendu : un extrait de trois
                    // lignes dans une popover n'a pas besoin de ses gras, et les
                    // mentions qu'il contient y deviendraient des liens ouvrant
                    // une popover dans la popover. Seul son nom à elle ressort.
                    Text(Self.extrait(citation.texte, soulignant: handle))
                        .font(.callout)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.primary.opacity(survolee ? 0.06 : 0))
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { survolee = $0 }
    }

    /// L'extrait, avec chaque mention de cette personne en couleur d'accent,
    /// et l'arobase de toutes les mentions retirée, comme dans les notes.
    ///
    /// Reconnue par sa clé et non par son orthographe : « @Helene » tapé à la
    /// hâte est la même « @Hélène », et doit ressortir pareil.
    static func extrait(_ texte: String, soulignant handle: PersonHandle) -> AttributedString {
        var resultat = AttributedString()
        var curseur = texte.startIndex
        while let arobase = texte[curseur...].firstIndex(of: "@") {
            resultat += AttributedString(texte[curseur..<arobase])
            let debut = texte.index(after: arobase)
            let fin = texte[debut...].firstIndex { !PersonHandle.isAllowed($0) } ?? texte.endIndex
            // La règle des notes : une arobase collée à un mot est celle
            // d'une adresse, pas une mention.
            let avant = arobase > texte.startIndex ? texte[texte.index(before: arobase)] : nil
            let enTeteDeMot = avant == nil || avant!.isWhitespace || "([{«\"'-–—*>".contains(avant!)
            if enTeteDeMot, let cite = PersonHandle(name: String(texte[debut..<fin])) {
                var nom = AttributedString(texte[debut..<fin])
                if cite.key == handle.key {
                    nom.foregroundColor = .accentColor
                    nom.font = .callout.weight(.medium)
                }
                resultat += nom
                curseur = fin
            } else {
                resultat += AttributedString("@")
                curseur = debut
            }
        }
        resultat += AttributedString(texte[curseur...])
        return resultat
    }
}

/// Aller là d'où vient une citation — la journée, la sortie, le repas, la
/// pesée. `RootView` sait comment ; la popover n'a qu'à dire
/// laquelle. Voir `ouvrirDansPeople` juste en dessous pour le pourquoi de
/// l'environnement.
extension EnvironmentValues {
    @Entry var ouvrirLaCitation = NavigationAction<PeopleIndex.Citation> { _ in }
}

/// Aller à la fiche complète, depuis n'importe quelle note.
///
/// Par l'environnement : une note est rendue à cinq étages de la vue qui sait
/// changer d'écran, et faire descendre une fermeture à travers cinq signatures
/// aurait mêlé la navigation à des vues qui n'en parlent pas.
///
/// Sans rien par défaut : hors de l'application montée — aperçus, essais — il
/// n'y a nulle part où aller.
extension EnvironmentValues {
    @Entry var ouvrirDansPeople = NavigationAction<String> { _ in }
}

/// A navigation a note asks `RootView` for, the way `OpenURLAction` asks the
/// system.
///
/// Equal to every other by design: it only forwards to `RootView`, which reads
/// its own state when called, so a fresh closure is never a new behaviour. A
/// bare closure in the environment cannot be compared, and SwiftUI would
/// invalidate every view reading it on each update of the root view.
struct NavigationAction<Target>: Equatable {
    let perform: (Target) -> Void

    func callAsFunction(_ target: Target) { perform(target) }

    static func == (lhs: Self, rhs: Self) -> Bool { true }
}
