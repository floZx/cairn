import SwiftUI
import SwiftData
import Charts

/// Aggregates over the filtered activities, in place of the list.
///
/// The date range is set here rather than taken from the sidebar's period
/// filter: comparing against the preceding period means reading activities that
/// filter would have already removed. Every other criterion — sport, labels,
/// distance, region — still comes from the sidebar, which is what makes this
/// worth having: "my trail runs over 20 km, last six months against the six
/// before" is a question the two controls answer together.
struct StatisticsView: View {
    /// Filtered by everything except the date range, which is `period`'s job.
    let activities: [Activity]
    /// Opens an activity in the detail pane. A record names an outing, and the
    /// obvious question about it — where was it, how did it go — is answered one
    /// pane to the right.
    let onSelect: (PersistentIdentifier) -> Void
    /// `j` et `k` : la page défile tant que la touche est tenue, du même
    /// mouvement que le volet de droite sous `J` et `K`.
    var scrollRequest = PaneScrollRequest()

    @AppStorage(StatsPeriod.storageKey) private var period: StatsPeriod = .twelveMonths

    /// Which measure the volume chart plots. Distance and climbing tell very
    /// different stories about the same weeks.
    @State private var measure: ChartMeasure = .distance

    enum ChartMeasure: String, CaseIterable, Identifiable {
        case distance
        case elevation
        /// The one measure that adds up honestly across sports — a kilometre
        /// of cycling and one on foot are not the same kilometre — which is
        /// what makes it worth having beside the other two.
        case duration

        var id: String { rawValue }

        var label: String {
            switch self {
            case .distance: "Distance"
            case .elevation: "D+"
            case .duration: "Temps"
            }
        }
    }

    var body: some View {
        let stats = ActivityStatistics.compute(for: activities, period: period)
        let daily = TrainingLoad.daily(activities)
        let form = TrainingLoad.series(daily, calendar: ActivityStatistics.calendar)
        let regularity = Regularity.compute(
            activities, daily: daily, periodStart: stats.periodStart ?? Date()
        )
        PaneScrollView(
            resetKey: "statistiques", request: scrollRequest, scrollsSidewaysWhenNarrow: true
        ) {
            VStack(alignment: .leading, spacing: 16) {
                periodPicker
                if stats.count == 0 {
                    ContentUnavailableView(
                        "Aucune activité",
                        systemImage: "chart.bar",
                        description: Text("Rien à mesurer sur cette période avec les filtres actifs.")
                    )
                    .padding(.top, 30)
                } else {
                    totals(stats, regularity: regularity)
                    FormCard(
                        points: form,
                        periodStart: stats.periodStart,
                        estimatedCount: daily.estimatedCount,
                        count: daily.count
                    )
                    RegularityCard(regularity: regularity)
                    IntensityCard(
                        intensity: Intensity.compute(
                            activities,
                            slotStarts: stats.slots.map(\.start),
                            unit: period.granularity.component
                        ),
                        granularity: period.granularity
                    )
                    ProgressionCard(
                        activities: activities,
                        sports: SportProgress.sports(in: activities, since: stats.periodStart ?? Date()),
                        periodStart: stats.periodStart ?? Date(),
                        onSelect: onSelect
                    )
                    // Two columns once the window has room for them: the
                    // volume and the week read side by side, the table and the
                    // records likewise.
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 440), spacing: 16, alignment: .top)],
                        alignment: .leading,
                        spacing: 16
                    ) {
                        volumeChart(stats)
                        weekChart(ActivityStatistics.weekProgress(for: activities))
                        bySport(stats)
                        records(stats)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Statistiques")
    }

    // MARK: - Period

    private var periodPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Période", selection: $period) {
                ForEach(StatsPeriod.allCases) { choice in
                    Text(choice.displayName).tag(choice)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            // Said plainly, because the sidebar has a period filter of its own
            // that deliberately does not apply here.
            Text("La période se règle ici. Les autres filtres de la barre latérale s'appliquent.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Totals

    private func totals(_ stats: ActivityStatistics, regularity: Regularity) -> some View {
        StatsCard(
            "Cumuls",
            subtitle: "La distance se lit par sport : additionner des sports différents n'aurait pas de sens."
        ) {
            // No total distance here on purpose: summing a swim, a ride and a
            // run gives a number that means nothing. It lives per sport below.
            HStack(alignment: .top, spacing: 24) {
                KeyFigure(
                    title: "Activités",
                    value: "\(stats.count)",
                    change: ChangeBadge.percent(Double(stats.count), Double(stats.comparison.count))
                )
                KeyFigure(
                    title: "Temps en mouvement",
                    value: Format.durationCompact(stats.movingTime),
                    change: ChangeBadge.percent(
                        Double(stats.movingTime), Double(stats.comparison.movingTime)
                    )
                )
                KeyFigure(
                    title: "Dénivelé positif",
                    value: Format.elevation(stats.elevationGain),
                    change: ChangeBadge.percent(stats.elevationGain, stats.comparison.elevationGain)
                )
                KeyFigure(
                    title: "Par semaine",
                    value: Format.durationCompact(Int(regularity.weeklyHours * 3600)),
                    detail: "\(regularity.activeDays) jours actifs"
                )
            }
        }
    }

    // MARK: - Volume

    private func volumeChart(_ stats: ActivityStatistics) -> some View {
        StatsCard(
            period.granularity.sectionTitle,
            subtitle: "En trait, \(period.comparisonName.lowercased())"
        ) {
            Picker("Mesure", selection: $measure) {
                ForEach(ChartMeasure.allCases) { measure in
                    Text(measure.label).tag(measure)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        } content: {

            Chart(stats.slots) { slot in
                BarMark(
                    x: .value("Début", slot.start, unit: period.granularity.component),
                    y: .value(measure.label, current(slot))
                )
                .foregroundStyle(by: .value("Série", "Période"))

                // A line over the bars rather than a second set of bars: doubling
                // the count in one pane is unreadable, and the shape of the line
                // is what makes the two comparable at a glance.
                LineMark(
                    x: .value("Début", slot.start, unit: period.granularity.component),
                    y: .value(measure.label, comparison(slot))
                )
                .foregroundStyle(by: .value("Série", period.comparisonName))
                .symbol(.circle)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            .chartForegroundStyleScale([
                "Période": Color.accentColor,
                period.comparisonName: Color.secondary,
            ])
            .chartXAxis {
                // Labelled by month even when the bars are weeks: thirteen week
                // numbers do not fit a pane, and a month tells you where you are
                // just as well. The year is redundant on a rolling window.
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.narrow))
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let raw = value.as(Double.self) {
                            Text(axisLabel(for: raw))
                        }
                    }
                }
            }
            .frame(height: 200)
        }
    }

    private func current(_ slot: ActivityStatistics.SlotTotals) -> Double {
        switch measure {
        case .distance: slot.distance / 1000
        case .elevation: slot.elevationGain
        case .duration: Double(slot.movingTime) / 3600
        }
    }

    private func comparison(_ slot: ActivityStatistics.SlotTotals) -> Double {
        switch measure {
        case .distance: slot.comparisonDistance / 1000
        case .elevation: slot.comparisonElevationGain
        case .duration: Double(slot.comparisonMovingTime) / 3600
        }
    }

    /// Hours rather than seconds on the axis: a week of training is read in
    /// hours, and "25200" says nothing to anyone.
    private func axisLabel(for value: Double) -> String {
        switch measure {
        case .distance: "\(Int(value)) km"
        case .elevation: "\(Int(value)) m"
        case .duration: "\(Int(value)) h"
        }
    }

    // MARK: - La semaine contre la précédente

    /// Two cumulative curves, Monday to Sunday: this week against the last.
    ///
    /// The shape is Strava's relative-effort chart; the measure is one of this
    /// screen's own, since Cairn computes no heart-rate load. The question it
    /// answers is "am I ahead or behind", and two lines that start together
    /// answer it without adding anything up.
    private func weekChart(_ progress: ActivityStatistics.WeekProgress) -> some View {
        StatsCard("Cette semaine", subtitle: "Cumul jour par jour, contre la semaine dernière") {

            Chart {
                ForEach(progress.lastWeek) { point in
                    LineMark(
                        x: .value("Jour", point.dayIndex),
                        y: .value(measure.label, weekValue(point)),
                        series: .value("Série", "La semaine dernière")
                    )
                    .foregroundStyle(by: .value("Série", "La semaine dernière"))
                    .symbol(.circle)
                }
                ForEach(progress.thisWeek) { point in
                    LineMark(
                        x: .value("Jour", point.dayIndex),
                        y: .value(measure.label, weekValue(point)),
                        series: .value("Série", "Cette semaine")
                    )
                    .foregroundStyle(by: .value("Série", "Cette semaine"))
                    .symbol(.circle)
                    .lineStyle(StrokeStyle(lineWidth: 3))
                }
            }
            .chartForegroundStyleScale([
                "Cette semaine": Color.accentColor,
                "La semaine dernière": Color.secondary,
            ])
            .chartXScale(domain: 0...6)
            .chartXAxis {
                AxisMarks(values: Array(0...6)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let index = value.as(Int.self) {
                            Text(Self.weekdayNames[index])
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let raw = value.as(Double.self) {
                            Text(axisLabel(for: raw))
                        }
                    }
                }
            }
            .frame(height: 200)

            if let ahead = weekDifference(progress) {
                Text(ahead)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Monday first, like every week this application counts.
    private static let weekdayNames = ["lun.", "mar.", "mer.", "jeu.", "ven.", "sam.", "dim."]

    private func weekValue(_ point: ActivityStatistics.WeekProgress.Point) -> Double {
        switch measure {
        case .distance: point.distance / 1000
        case .elevation: point.elevationGain
        case .duration: Double(point.movingTime) / 3600
        }
    }

    /// Where this week stands against the same day of the last one.
    ///
    /// Compared on the same day rather than on the week's total: a Wednesday
    /// against a finished week would say "behind" every time, which is true
    /// and useless.
    private func weekDifference(
        _ progress: ActivityStatistics.WeekProgress
    ) -> String? {
        guard let current = progress.thisWeek.last else { return nil }
        let sameDay = progress.lastWeek.first { $0.dayIndex == current.dayIndex }
        guard let sameDay else { return nil }
        let delta = weekValue(current) - weekValue(sameDay)
        let unit = axisLabel(for: abs(delta.rounded()))
        let day = Self.weekdayNames[current.dayIndex]
        if abs(delta) < 0.05 {
            return "Au même point que \(day) dernier."
        }
        return delta > 0
            ? "\(unit) de plus que \(day) dernier."
            : "\(unit) de moins que \(day) dernier."
    }

    // MARK: - By sport

    private func bySport(_ stats: ActivityStatistics) -> some View {
        StatsCard("Par sport") {
            Table(stats.sports) {
                TableColumn("Sport") { row in
                    SportLabel(row.sport.displayName, sport: row.sport)
                }
                TableColumn("Activités") { row in
                    Text("\(row.count)").monospacedDigit()
                }
                .width(min: 70, ideal: 80)
                TableColumn("Distance") { row in
                    Text(Format.distance(row.distance)).monospacedDigit()
                }
                .width(min: 80, ideal: 100)
                TableColumn("Temps") { row in
                    Text(Format.durationCompact(row.movingTime)).monospacedDigit()
                }
                .width(min: 80, ideal: 100)
                TableColumn("D+") { row in
                    Text(Format.elevation(row.elevationGain)).monospacedDigit()
                }
                .width(min: 70, ideal: 90)
            }
            // Sized to its contents: a scrolling table inside a scrolling page
            // traps the wheel in whichever the cursor happens to be over.
            .scrollContentBackground(.hidden)
            .frame(height: CGFloat(stats.sports.count) * 28 + 28)
        }
    }

    // MARK: - Records

    private func records(_ stats: ActivityStatistics) -> some View {
        StatsCard("Records", subtitle: "Cliquer pour ouvrir la sortie") {
            ForEach(stats.records) { record in
                RecordRow(record: record, onSelect: onSelect)
            }
        }
    }
}

/// One record: what it measures, the figure, the outing and its date. The
/// whole row opens the outing.
struct RecordRow: View {
    let record: ActivityStatistics.Record
    let onSelect: (PersistentIdentifier) -> Void

    var body: some View {
        Button {
            onSelect(record.activityID)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(record.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 150, alignment: .leading)
                Text(record.formattedValue)
                    .font(.body.monospacedDigit())
                    .frame(width: 90, alignment: .leading)
                SportLabel(record.activityName, sport: record.sport)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(record.formattedDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // The whole row, not just the name: a target the width of an
            // activity's title is a target you have to aim at.
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Ouvrir « \(record.activityName) »")
    }
}
