import SwiftUI

/// suivinut's mini calendar: dots on logged days, click to travel. The
/// displayed month follows the selection but can be browsed independently.
///
/// Shared since the journal arrived: the food log puts it in the right-hand
/// panel, the journal in the sidebar, and "which days have something on them,
/// and take me there" is the same question in both. It knows nothing of either
/// — a bound day and a set of marked ones is the whole contract.
struct MiniCalendarView: View {
    @Binding var selected: DateKey
    let loggedDays: Set<String>

    /// A day of the displayed month — kept as state so browsing months does
    /// not move the selection until a day is clicked.
    @State private var shownMonth: DateKey

    init(selected: Binding<DateKey>, loggedDays: Set<String>) {
        _selected = selected
        self.loggedDays = loggedDays
        _shownMonth = State(initialValue: selected.wrappedValue)
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Button {
                    shownMonth = shownMonth.monthStart.advanced(by: -1).monthStart
                } label: {
                    Image(systemName: "chevron.left")
                }
                Spacer()
                Text(Self.monthFormatter.string(from: shownMonth.date()).capitalized)
                    .font(.callout.weight(.semibold))
                Spacer()
                Button {
                    shownMonth = shownMonth.monthEnd().advanced(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
            }
            .buttonStyle(.borderless)
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow {
                    ForEach(["L", "M", "M", "J", "V", "S", "D"].indices, id: \.self) {
                        Text(["L", "M", "M", "J", "V", "S", "D"][$0])
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(
                    Array(MiniCalendarModel.weeks(containing: shownMonth).enumerated()),
                    id: \.offset
                ) { _, week in
                    GridRow {
                        ForEach(week.indices, id: \.self) { index in
                            dayCell(week[index])
                        }
                    }
                }
            }
        }
        .onChange(of: selected) { _, newValue in shownMonth = newValue }
    }

    @ViewBuilder
    private func dayCell(_ day: DateKey?) -> some View {
        if let day {
            Button {
                selected = day
            } label: {
                VStack(spacing: 1) {
                    Text(String(Int(day.raw.suffix(2)) ?? 0))
                        .font(.caption.monospacedDigit())
                    Circle()
                        .fill(loggedDays.contains(day.raw)
                              ? Color.accentColor : .clear)
                        .frame(width: 4, height: 4)
                }
                .frame(maxWidth: .infinity, minHeight: 24)
                .background(
                    day == selected
                        ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 4)
                )
            }
            .buttonStyle(.borderless)
        } else {
            Color.clear.frame(maxWidth: .infinity, minHeight: 24)
        }
    }
}
