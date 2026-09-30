import SwiftUI

/// The sidebar's month: click a day to travel. The displayed month follows
/// the selection but can be browsed independently.
///
/// Empty days are the ones marked, in grey, not the full ones: kept daily, a
/// dot under every logged day was a sprinkle of blue saying nothing. The
/// selection is an accent disc and today an accent figure, as in Apple's own
/// calendars. `marks` adds a short line under a day — the food log's verdict
/// on its calories.
///
/// Shared since the journal arrived: the food log puts it in the right-hand
/// panel, the journal in the sidebar, and "which days have something on them,
/// and take me there" is the same question in both. It knows nothing of either
/// — a bound day and a set of marked ones is the whole contract.
struct MiniCalendarView: View {
    @Binding var selected: DateKey
    let loggedDays: Set<String>
    var marks: [String: Color] = [:]

    /// A day of the displayed month — kept as state so browsing months does
    /// not move the selection until a day is clicked.
    @State private var shownMonth: DateKey

    init(
        selected: Binding<DateKey>, loggedDays: Set<String>, marks: [String: Color] = [:]
    ) {
        _selected = selected
        self.loggedDays = loggedDays
        self.marks = marks
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
                    .font(.callout.weight(.medium))
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
                            // The weekend a shade lighter, in the header only:
                            // on the days themselves grey already means empty.
                            .foregroundStyle($0 >= 5 ? .tertiary : .secondary)
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
            let isSelected = day == selected
            Button {
                selected = day
            } label: {
                VStack(spacing: 2) {
                    Text(String(Int(day.raw.suffix(2)) ?? 0))
                        .font(.caption.monospacedDigit()
                            .weight(isSelected || day == today ? .semibold : .regular))
                        .foregroundStyle(figureStyle(day, isSelected: isSelected))
                        .frame(width: 22, height: 22)
                        .background {
                            if isSelected { Circle().fill(Color.accentColor) }
                        }
                    Capsule()
                        .fill(marks[day.raw] ?? .clear)
                        .frame(width: 10, height: 2)
                }
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(maxWidth: .infinity, minHeight: 26)
        }
    }

    private var today: DateKey { DateKey(Date()) }

    private func figureStyle(_ day: DateKey, isSelected: Bool) -> AnyShapeStyle {
        if isSelected { return AnyShapeStyle(.white) }
        if day == today { return AnyShapeStyle(Color.accentColor) }
        return loggedDays.contains(day.raw) ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary)
    }
}
