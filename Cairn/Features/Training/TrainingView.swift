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
    @State private var editing: PlannedSession?
    @State private var creatingOn: DateKey?
    @State private var importing = false

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
        .sheet(item: $editing) { seance in
            PlannedSessionSheet(session: seance, dateKey: seance.dateKey ?? day)
        }
        .sheet(item: $creatingOn) { jour in
            PlannedSessionSheet(session: nil, dateKey: jour)
        }
        .sheet(isPresented: $importing) { TrainingImportSheet() }
    }

    private var entete: some View {
        HStack(spacing: 12) {
            Button { reculer() } label: { Image(systemName: "chevron.left") }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Text(Self.monthFormatter.string(from: shownMonth.date()).capitalized)
                .font(.title2.weight(.semibold))
                .frame(minWidth: 190, alignment: .leading)
            Button { avancer() } label: { Image(systemName: "chevron.right") }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("Aujourd'hui") { shownMonth = DateKey(Date()) }
            Spacer()
            Button {
                importing = true
            } label: {
                Label("Reprendre un calendrier", systemImage: "calendar.badge.plus")
            }
            .help("Recopier un plan depuis un calendrier macOS, une fois")
            Button {
                creatingOn = day
            } label: {
                Label("Nouvelle séance", systemImage: "plus")
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
                onOuvrir: { editing = $0 },
                onCreer: { creatingOn = jour },
                onSupprimer: supprimer,
                onOuvrirSortie: onSelectActivity
            )
        } else {
            Color.clear
        }
    }

    private func supprimer(_ seance: PlannedSession) {
        context.delete(seance)
        try? context.save()
    }

    private func reculer() { shownMonth = shownMonth.monthStart.advanced(by: -1).monthStart }
    private func avancer() { shownMonth = shownMonth.monthEnd().advanced(by: 1) }
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
        }
    }

    private var numero: Int {
        Calendar.current.component(.day, from: jour.date())
    }

    private func seanceLigne(_ paire: TrainingMatch.Paire<PlannedSession, Activity>) -> some View {
        let seance = paire.seance
        let faite = paire.sortie != nil
        return Button { onOuvrir(seance) } label: {
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

/// Pour que `sheet(item:)` puisse porter un jour.
extension DateKey: Identifiable {
    var id: String { raw }
}
