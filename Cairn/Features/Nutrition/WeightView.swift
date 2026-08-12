// Cairn/Features/Nutrition/WeightView.swift
import SwiftUI
import SwiftData
import Charts

/// The weight screen — suivinut's weight graph, stats and editable list in
/// one place. Chart idioms follow `StatisticsView` (Swift Charts, system
/// colours); write paths follow `NutritionDayView` (NutritionJournal +
/// failure alert + the vim gate while a sheet is up).
struct WeightView: View {
    /// Forwarded window-level vim commands, same contract as
    /// `NutritionDayView.onCommand`.
    let onCommand: (VimCommand) -> Bool

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WeightEntry.dateKeyRaw) private var entries: [WeightEntry]
    @AppStorage(WeightPeriod.storageKey) private var period: WeightPeriod = .ninetyDays
    @AppStorage(NutritionSettings.weightGoalKey)
    private var weightGoal = NutritionSettings.defaultWeightGoalKg
    @State private var isAddingEntry = false
    @State private var editingEntry: WeightEntry?
    @State private var writeFailureMessage: String?

    private var isPresentingModal: Bool {
        isAddingEntry || editingEntry != nil || writeFailureMessage != nil
    }

    /// Sorted ascending by the query; the raw string sorts chronologically.
    private var points: [WeightPoint] {
        entries.compactMap { entry in
            entry.dateKey.map { WeightPoint(dateKey: $0, weightKg: entry.weightKg) }
        }
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView {
                    Label("Aucune pesée", systemImage: "scalemass")
                } description: {
                    Text("Consignez votre poids pour suivre la tendance.")
                } actions: {
                    Button("Nouvelle pesée…") { isAddingEntry = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                content
            }
        }
        .vimKeys(enabled: !isPresentingModal) { command in
            switch command {
            case .addFood, .newWeighIn:
                // Both keys open the same sheet here: on the weight screen,
                // "add" can only mean a weigh-in.
                isAddingEntry = true
                return true
            default:
                return onCommand(command)
            }
        }
        .sheet(isPresented: $isAddingEntry) {
            WeightEntrySheet(existing: nil, defaultWeightKg: defaultWeight)
        }
        .sheet(item: $editingEntry) { entry in
            WeightEntrySheet(existing: entry, defaultWeightKg: defaultWeight)
        }
        .alert(
            "Écriture impossible",
            isPresented: Binding(
                get: { writeFailureMessage != nil },
                set: { if !$0 { writeFailureMessage = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(writeFailureMessage ?? "")
        }
    }

    /// The last weigh-in is the least surprising prefill for a new one.
    private var defaultWeight: Double {
        entries.last?.weightKg ?? weightGoal
    }

    // MARK: - Content

    private var content: some View {
        let windowed = WeightStats.window(points, days: period.days)
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("Poids")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Picker("Période", selection: $period) {
                        ForEach(WeightPeriod.allCases) { period in
                            Text(period.displayName).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    Button {
                        isAddingEntry = true
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Nouvelle pesée")
                }
                chart(windowed)
                tiles
                Divider()
                list
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func chart(_ windowed: [WeightPoint]) -> some View {
        Chart {
            ForEach(windowed, id: \.dateKey.raw) { point in
                LineMark(
                    x: .value("Date", point.dateKey.date()),
                    y: .value("Poids", point.weightKg)
                )
                PointMark(
                    x: .value("Date", point.dateKey.date()),
                    y: .value("Poids", point.weightKg)
                )
                .symbolSize(20)
            }
            if weightGoal > 0 {
                RuleMark(y: .value("Objectif", weightGoal))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .bottomTrailing) {
                        Text("Objectif \(Format.typedNumber(weightGoal)) kg")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
            }
            // The period minimum, green like suivinut's braille graph: the
            // floor already reached is the encouraging line.
            if let minimum = windowed.map(\.weightKg).min() {
                RuleMark(y: .value("Minimum", minimum))
                    .foregroundStyle(.green.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartYScale(domain: yDomain(windowed))
        .frame(height: 220)
    }

    /// Fitted rather than zero-based: a weight chart from zero flattens a
    /// 3 kg trend into an invisible wiggle. The goal line stays in frame.
    private func yDomain(_ windowed: [WeightPoint]) -> ClosedRange<Double> {
        let values = windowed.map(\.weightKg)
            + (weightGoal > 0 ? [weightGoal] : [])
        guard let low = values.min(), let high = values.max() else {
            return 0...100
        }
        return (low - 0.5)...(high + 0.5)
    }

    private var tiles: some View {
        HStack(alignment: .top, spacing: 24) {
            if let current = points.last {
                StatTile("Poids actuel", "\(Format.typedNumber(current.weightKg)) kg")
            }
            if let delta = WeightStats.delta(points) {
                StatTile("Δ 7 jours", signed(delta) + " kg")
            }
            if let rate = WeightStats.ratePerWeek(points) {
                StatTile("Rythme", signed(rate) + " kg/sem")
            }
            if weightGoal > 0,
               let weeks = WeightStats.weeksToGoal(points, goal: weightGoal) {
                StatTile("Objectif", "~\(Int(weeks.rounded())) sem")
            }
        }
    }

    private func signed(_ value: Double) -> String {
        Format.signedTwoDecimals(value)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pesées")
                .font(.headline)
            // Newest first: the row being checked or fixed is almost always
            // the latest one.
            ForEach(entries.reversed(), id: \.persistentModelID) { entry in
                HStack(spacing: 16) {
                    Text(entry.dateKey.map { Format.dateOnly($0.date()) } ?? entry.dateKeyRaw)
                        .frame(width: 110, alignment: .leading)
                    Text("\(Format.typedNumber(entry.weightKg)) kg")
                        .monospacedDigit()
                        .frame(width: 70, alignment: .trailing)
                    if let note = entry.note {
                        // The inline half of the renderer, not the block one:
                        // this is a row of a table held to one line, and
                        // `MarkdownText` lays paragraphs out vertically. Bold
                        // and italics survive, the tag loses its hash, and the
                        // row keeps its height.
                        MarkdownText.inline(note, hidingTagHashes: true)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
                .contentShape(.rect)
                .contextMenu {
                    Button("Éditer…") { editingEntry = entry }
                    Divider()
                    Button("Supprimer", role: .destructive) { delete(entry) }
                }
            }
        }
    }

    private func delete(_ entry: WeightEntry) {
        do {
            try NutritionJournal.deleteWeight(entry, in: modelContext)
        } catch {
            writeFailureMessage =
                "Votre suppression n'a pas pu être enregistrée. \(error.localizedDescription)"
        }
    }
}
