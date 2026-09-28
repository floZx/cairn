import SwiftUI

/// A year of days as a grid, the streak of active weeks, and where the year
/// is heading.
struct RegularityCard: View {
    let regularity: Regularity

    @State private var hovered: Regularity.Day?
    /// The grid's width, measured, so its height can follow the cell size
    /// rather than reserve room for the largest one.
    @State private var width: CGFloat = 700

    var body: some View {
        StatsCard(
            "Régularité",
            subtitle: "Les 52 dernières semaines, un carré par jour"
        ) {
            figures
            heatmap
            HStack {
                hoverLine
                Spacer()
                scale
            }
            if let projection = regularity.projection {
                projectionLine(projection)
            }
        }
    }

    // MARK: - Figures

    private var figures: some View {
        HStack(alignment: .top, spacing: 24) {
            KeyFigure(
                title: "Série en cours",
                value: weeks(regularity.currentStreak),
                detail: "semaines d'affilée avec une sortie"
            )
            KeyFigure(
                title: "Meilleure série",
                value: weeks(regularity.bestStreak),
                detail: regularity.currentStreak >= regularity.bestStreak && regularity.bestStreak > 0
                    ? "c'est celle-ci !" : "depuis la première sortie"
            )
            KeyFigure(
                title: "Jours actifs",
                value: "\(regularity.activeDays)",
                detail: "sur \(regularity.periodDays) jours (\(activeShare) %)"
            )
            KeyFigure(
                title: "Par semaine",
                value: Format.durationCompact(Int(regularity.weeklyHours * 3600)),
                detail: "en moyenne sur la période"
            )
        }
    }

    private func weeks(_ count: Int) -> String {
        "\(count) sem."
    }

    private var activeShare: Int {
        Int((Double(regularity.activeDays) / Double(max(regularity.periodDays, 1)) * 100).rounded())
    }

    // MARK: - Grid

    private static let gap: CGFloat = 3
    private static let weekdayLabels = ["lun.", "", "mer.", "", "ven.", "", "dim."]

    private var heatmap: some View {
        let levels = Self.levels(for: regularity.days)
        let weeks = (regularity.days.map(\.week).max() ?? 0) + 1
        let byPosition = Dictionary(
            regularity.days.map { ($0.week * 7 + $0.weekday, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let labelWidth: CGFloat = 30
        let cell = max(6, min(16, (width - labelWidth) / CGFloat(weeks) - Self.gap))
        return Group {
            VStack(alignment: .leading, spacing: Self.gap) {
                monthLabels(cell: cell, labelWidth: labelWidth)
                HStack(alignment: .top, spacing: Self.gap) {
                    VStack(alignment: .leading, spacing: Self.gap) {
                        ForEach(0..<7, id: \.self) { weekday in
                            Text(Self.weekdayLabels[weekday])
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .frame(width: labelWidth - Self.gap, height: cell, alignment: .leading)
                        }
                    }
                    ForEach(0..<weeks, id: \.self) { week in
                        VStack(spacing: Self.gap) {
                            ForEach(0..<7, id: \.self) { weekday in
                                if let day = byPosition[week * 7 + weekday] {
                                    RoundedRectangle(cornerRadius: 2.5)
                                        .fill(Self.fill(level: levels[day.date] ?? 0))
                                        .overlay {
                                            if hovered == day {
                                                RoundedRectangle(cornerRadius: 2.5)
                                                    .strokeBorder(Color.primary.opacity(0.6), lineWidth: 1)
                                            }
                                        }
                                        .frame(width: cell, height: cell)
                                        .onHover { inside in
                                            if inside { hovered = day }
                                            else if hovered == day { hovered = nil }
                                        }
                                } else {
                                    Color.clear.frame(width: cell, height: cell)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private func monthLabels(cell: CGFloat, labelWidth: CGFloat) -> some View {
        let firsts = regularity.days.filter { $0.weekday == 0 }
        let calendar = ActivityStatistics.calendar
        return ZStack(alignment: .topLeading) {
            ForEach(firsts) { day in
                let previous = calendar.date(byAdding: .day, value: -7, to: day.date)
                if let previous,
                   calendar.component(.month, from: previous) != calendar.component(.month, from: day.date) {
                    Text(day.date.formatted(.dateTime.month(.abbreviated)))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .offset(x: labelWidth + CGFloat(day.week) * (cell + Self.gap))
                }
            }
        }
        .frame(height: 12, alignment: .topLeading)
    }

    /// Five levels: none, then quartiles of the days that had an outing —
    /// relative to one's own year, so the grid has contrast whatever the
    /// volume.
    static func levels(for days: [Regularity.Day]) -> [Date: Int] {
        let loads = days.map(\.load).filter { $0 > 0 }.sorted()
        guard !loads.isEmpty else { return [:] }
        func quantile(_ q: Double) -> Double { loads[min(loads.count - 1, Int(Double(loads.count) * q))] }
        let bounds = [quantile(0.25), quantile(0.5), quantile(0.75)]
        var result: [Date: Int] = [:]
        for day in days where day.load > 0 {
            result[day.date] = 1 + bounds.filter { day.load > $0 }.count
        }
        return result
    }

    static func fill(level: Int) -> Color {
        switch level {
        case 0: Color.secondary.opacity(0.12)
        case 1: Color.accentColor.opacity(0.3)
        case 2: Color.accentColor.opacity(0.5)
        case 3: Color.accentColor.opacity(0.75)
        default: Color.accentColor
        }
    }

    private var hoverLine: some View {
        Group {
            if let hovered {
                Text(Format.dateOnly(hovered.date) + " — " + (hovered.movingTime > 0
                    ? "\(Format.durationCompact(hovered.movingTime)), charge \(Int(hovered.load.rounded()))"
                    : "repos"))
            } else {
                Text("Survoler un jour pour le détail")
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private var scale: some View {
        HStack(spacing: 3) {
            Text("Moins").font(.caption2).foregroundStyle(.secondary)
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Self.fill(level: level))
                    .frame(width: 10, height: 10)
            }
            Text("Plus").font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: - Projection

    private func projectionLine(_ projection: Regularity.Projection) -> some View {
        var text = "À ce rythme, \(projection.year) finira à \(projection.projectedMovingTime / 3600) h d'effort"
        if let sport = projection.mainSport, projection.projectedMainSportDistance > 0 {
            text += ", dont \(Format.distance(projection.projectedMainSportDistance)) de \(sport.displayName.lowercased())"
        }
        text += " — \(projection.movingTimeSoFar / 3600) h à ce jour."
        return Label(text, systemImage: "chart.line.uptrend.xyaxis")
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}
