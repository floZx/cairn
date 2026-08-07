import SwiftUI
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

    @AppStorage(StatsPeriod.storageKey) private var period: StatsPeriod = .twelveMonths

    /// Which measure the monthly chart plots. Distance and climbing tell very
    /// different stories about the same months.
    @State private var monthlyMeasure: MonthlyMeasure = .distance

    enum MonthlyMeasure: String, CaseIterable, Identifiable {
        case distance
        case elevation

        var id: String { rawValue }

        var label: String {
            switch self {
            case .distance: "Distance"
            case .elevation: "D+"
            }
        }
    }

    var body: some View {
        let stats = ActivityStatistics.compute(for: activities, period: period)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                periodPicker
                if stats.count == 0 {
                    ContentUnavailableView(
                        "Aucune activité",
                        systemImage: "chart.bar",
                        description: Text("Rien à mesurer sur cette période avec les filtres actifs.")
                    )
                    .padding(.top, 30)
                } else {
                    totals(stats)
                    Divider()
                    monthly(stats)
                    Divider()
                    bySport(stats)
                    Divider()
                    records(stats)
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

    private func totals(_ stats: ActivityStatistics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Cumuls")
            // No total distance here on purpose: summing a swim, a ride and a
            // run gives a number that means nothing. It lives per sport below.
            HStack(alignment: .top, spacing: 32) {
                StatTile("Activités", "\(stats.count)")
                StatTile("Temps en mouvement", Format.duration(stats.movingTime))
                StatTile("Dénivelé positif", Format.elevation(stats.elevationGain))
            }
            Text("La distance se lit par sport : additionner des sports différents n'aurait pas de sens.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Monthly

    private func monthly(_ stats: ActivityStatistics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle("Par mois")
                Spacer()
                Picker("Mesure", selection: $monthlyMeasure) {
                    ForEach(MonthlyMeasure.allCases) { measure in
                        Text(measure.label).tag(measure)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            Chart(stats.months) { month in
                BarMark(
                    x: .value("Mois", month.month, unit: .month),
                    y: .value(monthlyMeasure.label, current(month))
                )
                .foregroundStyle(by: .value("Série", "Période"))

                // A line over the bars rather than a second set of bars: at
                // twelve months, twenty-four bars in one pane are unreadable,
                // and the shape of the line is what makes the two comparable.
                LineMark(
                    x: .value("Mois", month.month, unit: .month),
                    y: .value(monthlyMeasure.label, comparison(month))
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
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisGridLine()
                    // Initial only: twelve three-letter labels do not fit the
                    // pane, and the year is redundant on a rolling window.
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

    private func current(_ month: ActivityStatistics.MonthTotals) -> Double {
        switch monthlyMeasure {
        case .distance: month.distance / 1000
        case .elevation: month.elevationGain
        }
    }

    private func comparison(_ month: ActivityStatistics.MonthTotals) -> Double {
        switch monthlyMeasure {
        case .distance: month.comparisonDistance / 1000
        case .elevation: month.comparisonElevationGain
        }
    }

    private func axisLabel(for value: Double) -> String {
        switch monthlyMeasure {
        case .distance: "\(Int(value)) km"
        case .elevation: "\(Int(value)) m"
        }
    }

    // MARK: - By sport

    private func bySport(_ stats: ActivityStatistics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Par sport")
            Table(stats.sports) {
                TableColumn("Sport") { row in
                    Label(row.sport.displayName, systemImage: row.sport.symbolName)
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
            .frame(height: CGFloat(stats.sports.count) * 28 + 28)
        }
    }

    // MARK: - Records

    private func records(_ stats: ActivityStatistics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Records")
            ForEach(stats.records) { record in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(record.kind.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 150, alignment: .leading)
                    Text(record.formattedValue)
                        .font(.body.monospacedDigit())
                        .frame(width: 90, alignment: .leading)
                    Label(record.activityName, systemImage: record.sport.symbolName)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Format.dateOnly(record.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.headline)
    }
}
