import SwiftUI
import SwiftData

/// Le plan d'entraînement, un mois à la fois.
///
/// Une grille et non une liste : un plan se lit par semaines — trois séances
/// et deux jours de repos, un enchaînement samedi-dimanche — et une liste
/// verticale de dates cache précisément ce rythme-là. C'est la forme qu'avait
/// le calendrier macOS d'où il vient, et ce n'est pas un hasard.
///
/// Chaque case porte ce qui était prévu et coche ce qui a été fait ; le
/// rapprochement est automatique, voir `TrainingMatch`.
struct TrainingView: View {
    @Binding var day: DateKey
    let onSelectActivity: (PersistentIdentifier) -> Void

    @Environment(\.modelContext) private var context

    /// Le mois affiché, indépendant du jour choisi : on feuillette le plan
    /// sans déplacer la sélection tant qu'on n'a pas cliqué une case.
    @State private var shownMonth: DateKey
    /// Une seule feuille à la fois, et un seul `.sheet` pour les trois.
    ///
    /// Trois modificateurs `.sheet` sur la même vue ne se cumulent pas :
    /// SwiftUI n'en honore qu'un, et les deux autres ne s'ouvrent jamais.
    /// Mesuré ici — le bouton d'import ne faisait rien du tout.
    @State private var feuille: FeuilleDuPlan?

    init(day: Binding<DateKey>, onSelectActivity: @escaping (PersistentIdentifier) -> Void) {
        _day = day
        self.onSelectActivity = onSelectActivity
        _shownMonth = State(initialValue: day.wrappedValue)
    }

    /// Tout le plan, pas seulement le mois affiché.
    ///
    /// Un prédicat par mois se relancerait à chaque coup de chevron pour
    /// épargner quelques centaines de lignes — un plan d'un an en fait trois
    /// cents. Le tri est ici parce que la grille en a besoin partout.
    @Query(sort: [SortDescriptor(\PlannedSession.dateKeyRaw), SortDescriptor(\PlannedSession.sortOrder)])
    private var sessions: [PlannedSession]

    /// Les sorties, toutes, triées : le mois affiché change à chaque coup de
    /// chevron, et un `@Query` ne relit pas son prédicat quand un `@State`
    /// bouge. Le tri en base, le découpage par jour dans la case — quelques
    /// centaines de lignes parcourues à chaque rendu, ce qui ne se voit pas.
    @Query(sort: \Activity.startLocalDate) private var activities: [Activity]

    /// Les types de journée, pour les poser d'un clic droit sur une case.
    @Query(sort: \DayType.sortOrder) private var dayTypes: [DayType]

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            entete
            Divider()
            grille
        }
        .background(.clear)
        .sheet(item: $feuille) { ouverte in
            switch ouverte {
            case .seance(let seance):
                PlannedSessionSheet(session: seance, dateKey: seance.dateKey ?? day)
            case .nouvelle(let jour):
                PlannedSessionSheet(session: nil, dateKey: jour)
            case .importer:
                TrainingImportSheet()
            }
        }
    }

    private var entete: some View {
        HStack(spacing: 12) {
            // Les deux chevrons encadrent le mois, et le mois est centré entre
            // eux : c'est la forme d'un sélecteur de mois partout ailleurs, et
            // aligné à gauche sur une largeur fixe il flottait à côté du
            // chevron droit selon la longueur du nom.
            HStack(spacing: 4) {
                Button { reculer() } label: { Image(systemName: "chevron.left") }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .help("Mois précédent")
                Text(Self.monthFormatter.string(from: shownMonth.date()).capitalized)
                    .font(.title3.weight(.semibold))
                    // Assez large pour « Septembre 2026 », le plus long des
                    // douze : une largeur qui s'ajuste ferait sauter les
                    // chevrons d'un mois à l'autre.
                    .frame(width: 168)
                    .multilineTextAlignment(.center)
                Button { avancer() } label: { Image(systemName: "chevron.right") }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .help("Mois suivant")
            }
            .buttonStyle(.borderless)

            // Jamais désactivé, même déjà sur aujourd'hui : un bouton grisé
            // se lit « cassé » avant de se lire « rien à faire », et c'est
            // exactement le malentendu qu'on vient de corriger.
            Button("Aujourd'hui") { revenirAAujourdhui() }

            Spacer()

            Button {
                feuille = .importer
            } label: {
                Label("Importer un calendrier", systemImage: "calendar.badge.plus")
            }
            .help("Importer un plan depuis un calendrier macOS, une fois")
            Button {
                feuille = .nouvelle(day)
            } label: {
                Label("Nouvelle séance", systemImage: "plus")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Le jour **et** le mois affiché.
    ///
    /// Le mois seul ne suffisait pas : un mois déjà à l'écran ne bougeait pas,
    /// et le bouton paraissait cassé alors qu'il faisait ce qu'on lui avait
    /// demandé. « Aujourd'hui » veut dire aujourd'hui, pas « le mois où il
    /// tombe ».
    private func revenirAAujourdhui() {
        let aujourdhui = DateKey(Date())
        day = aujourdhui
        shownMonth = aujourdhui
    }

    private var grille: some View {
        GeometryReader { geo in
            let semaines = MiniCalendarModel.weeks(containing: shownMonth)
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(Self.jours.indices, id: \.self) { index in
                        Text(Self.jours[index])
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 4)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(semaines.enumerated()), id: \.offset) { _, semaine in
                            HStack(spacing: 0) {
                                ForEach(semaine.indices, id: \.self) { index in
                                    cellule(semaine[index])
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            // Une hauteur plancher plutôt qu'une hauteur
                            // fixe : une semaine à double séance doit pouvoir
                            // grandir, mais une semaine vide ne doit pas
                            // s'écraser sur la ligne des numéros.
                            .frame(minHeight: max(96, (geo.size.height - 40) / CGFloat(max(semaines.count, 1))))
                        }
                    }
                }
            }
        }
    }

    private static let jours = ["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi", "Dimanche"]

    @ViewBuilder
    private func cellule(_ jour: DateKey?) -> some View {
        if let jour {
            TrainingDayCell(
                jour: jour,
                choisi: jour == day,
                aujourdhui: jour == DateKey(Date()),
                resultat: TrainingMatch.apparie(
                    seances: sessions.filter { $0.dateKeyRaw == jour.raw },
                    sorties: activities.filter { DateKey($0.startLocalDate).raw == jour.raw },
                    sportSeance: \.sport, sportSortie: \.sportType
                ),
                onChoisir: { day = jour },
                typesDeJour: dayTypes,
                onTypeDeJour: { poser($0, sur: jour) },
                onOuvrir: { feuille = .seance($0) },
                onCreer: { feuille = .nouvelle(jour) },
                onSupprimer: supprimer,
                onOuvrirSortie: onSelectActivity
            )
        } else {
            Color.clear
        }
    }

    /// Pose un type de journée sur toutes les séances d'un jour, et sur la
    /// journée nutrition avec.
    ///
    /// Par jour et non par séance : le budget calorique est celui de la
    /// journée, pas d'une sortie. Et depuis le clic droit plutôt que depuis la
    /// feuille, parce que le plan arrive du calendrier sans aucun type — les
    /// titres n'en portent pas — et qu'ouvrir trois cents feuilles pour les
    /// poser un par un n'était pas une réponse.
    private func poser(_ type: DayType?, sur jour: DateKey) {
        for seance in sessions where seance.dateKeyRaw == jour.raw {
            seance.dayType = type
            try? TrainingNutrition.appliquer(seance, dans: context)
        }
        try? context.save()
    }

    private func supprimer(_ seance: PlannedSession) {
        context.delete(seance)
        try? context.save()
    }

    private func reculer() { shownMonth = shownMonth.monthStart.advanced(by: -1).monthStart }
    private func avancer() { shownMonth = shownMonth.monthEnd().advanced(by: 1) }
}

/// Ce qui peut s'ouvrir par-dessus la grille.
private enum FeuilleDuPlan: Identifiable {
    case seance(PlannedSession)
    case nouvelle(DateKey)
    case importer

    var id: String {
        switch self {
        case .seance(let seance): "seance-\(seance.uuid)"
        case .nouvelle(let jour): "nouvelle-\(jour.raw)"
        case .importer: "import"
        }
    }
}

/// Une case du mois.
///
/// Extraite parce qu'elle porte tout le dessin : la grille, elle, ne fait que
/// de la géométrie, et les deux mélangées faisaient une vue de trois cents
/// lignes où l'on ne trouvait plus rien.
private struct TrainingDayCell: View {
    let jour: DateKey
    let choisi: Bool
    let aujourdhui: Bool
    let resultat: TrainingMatch.Resultat<PlannedSession, Activity>
    let onChoisir: () -> Void
    let typesDeJour: [DayType]
    let onTypeDeJour: (DayType?) -> Void
    let onOuvrir: (PlannedSession) -> Void
    let onCreer: () -> Void
    let onSupprimer: (PlannedSession) -> Void
    let onOuvrirSortie: (PersistentIdentifier) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text("\(numero)")
                    .font(.callout.weight(aujourdhui ? .bold : .regular))
                    .foregroundStyle(aujourdhui ? Color.accentColor : .primary)
                if let type = resultat.paires.first?.seance.dayType {
                    Text(type.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            ForEach(resultat.paires.indices, id: \.self) { index in
                seanceLigne(resultat.paires[index])
            }
            // Ce qui n'était pas prévu, en retrait : de l'entraînement quand
            // même, mais qui ne coche aucune ligne du plan.
            ForEach(resultat.enPlus) { sortie in
                Button { onOuvrirSortie(sortie.id) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: sortie.sportType.symbolName)
                            .foregroundStyle(sortie.sportType.color)
                        Text(sortie.name).lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(choisi ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(choisi ? Color.accentColor.opacity(0.5) : .clear)
        )
        .padding(2)
        .contentShape(Rectangle())
        .onTapGesture { onChoisir() }
        .contextMenu {
            Button("Ajouter une séance", systemImage: "plus") { onCreer() }
            if !resultat.paires.isEmpty, !typesDeJour.isEmpty {
                Divider()
                Menu("Type de journée") {
                    ForEach(typesDeJour) { type in
                        Button("\(type.name) · \(type.kcalTarget) kcal") {
                            onTypeDeJour(type)
                        }
                    }
                    Divider()
                    Button("Aucun") { onTypeDeJour(nil) }
                }
            }
        }
    }

    private var numero: Int {
        Calendar.current.component(.day, from: jour.date())
    }

    @ViewBuilder
    private func seanceLigne(_ paire: TrainingMatch.Paire<PlannedSession, Activity>) -> some View {
        let seance = paire.seance
        let faite = paire.sortie != nil
        Button { onOuvrir(seance) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: faite ? "checkmark.circle.fill" : seance.sport.symbolName)
                    .foregroundStyle(faite ? Color.green : seance.sport.color)
                VStack(alignment: .leading, spacing: 0) {
                    Text(seance.title.isEmpty ? seance.sport.displayName : seance.title)
                        .lineLimit(2)
                    if let objectif = seance.objectifResume {
                        Text(objectif)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .font(.caption)
            // Une séance accomplie s'efface un peu : ce qui reste à faire est
            // ce qu'on vient lire.
            .opacity(faite ? 0.65 : 1)
        }
        .buttonStyle(.plain)
        .help(seance.notes.isEmpty ? seance.title : seance.notes)
        .contextMenu {
            Button("Modifier", systemImage: "pencil") { onOuvrir(seance) }
            Button("Supprimer", systemImage: "trash", role: .destructive) { onSupprimer(seance) }
        }

        // La sortie qui l'a accomplie, en dessous et en retrait : c'est elle
        // qui mène au volet de droite, la ligne du dessus menant à la séance.
        if let sortie = paire.sortie {
            Button { onOuvrirSortie(sortie.id) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.turn.down.right")
                    Text(sortie.name).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            }
            .buttonStyle(.plain)
            .help("Voir « \(sortie.name) »")
        }
    }
}

extension PlannedSession {
    /// « 18 km · 1 h 30 · 400 m », en ne disant que ce qui est visé.
    var objectifResume: String? {
        var morceaux: [String] = []
        if let distance = plannedDistance { morceaux.append(Format.distance(distance)) }
        if let duree = plannedDuration { morceaux.append(Format.durationCompact(Int(duree))) }
        if let denivele = plannedElevation { morceaux.append(Format.elevation(denivele)) }
        return morceaux.isEmpty ? nil : morceaux.joined(separator: " · ")
    }
}

