import SwiftUI
import Charts

/// Aggregates over the filtered activities, in place of the list.
///
/// Solidary with the filters by design — that is what makes it worth having.
/// "My trail runs over 20 km this year" is a question the sidebar can already
/// express; this pane answers it. The window subtitle already states which
/// filters are on, so the figures never stand without their context.
struct StatisticsView: View {
    let activities: [Activity]

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
        let stats = ActivityStatistics.compute(for: activities)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if stats.count == 0 {
                    ContentUnavailableView(
                        "Aucune activité",
                        systemImage: "chart.bar",
                        description: Text("Les filtres actifs ne laissent rien à mesurer.")
                    )
                    .padding(.top, 40)
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
                sectionTitle("Douze derniers mois")
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
                    y: .value(monthlyMeasure.label, plotted(month))
                )
                .foregroundStyle(Color.accentColor)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { value in
                    AxisGridLine()
                    // Initial only: twelve three-letter labels do not fit the
                    // pane, and the year is redundant on a twelve-month window.
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
            .frame(height: 180)
        }
    }

    private func plotted(_ month: ActivityStatistics.MonthTotals) -> Double {
        switch monthlyMeasure {
        case .distance: month.distance / 1000
        case .elevation: month.elevationGain
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
