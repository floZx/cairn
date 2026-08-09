import SwiftUI
import SwiftData
import Charts

/// The other outings on this very course — Strava's « matched activities ».
///
/// The point is the comparison: same course, different day, different legs.
/// Every matched effort is a row, the current one included so the delta
/// column has its zero, and the fastest wears the trophy.
struct SameRouteSection: View {
    let activity: Activity
    var onSelect: ((PersistentIdentifier) -> Void)?

    @Query private var activities: [Activity]

    var body: some View {
        // Computed in `body`, not in a `.task`: a `@Query` materialises when
        // the render reads it, and only that read makes the view re-render
        // when the results land. A task that read it off-render saw an empty
        // library once and was never told otherwise — the section stayed
        // blank for courses that matched. The signature cache keeps the
        // in-body cost to a handful of dictionary lookups.
        let matches = Self.matches(for: activity, in: activities)
        if !matches.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Parcours similaires").font(.headline)
                Text(
                    "\(matches.count + 1) sorties sur ce tracé — "
                    + "l'écart se lit face à celle-ci."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                chart(matches)
                rowList(matches)
            }
        }
    }

    // MARK: - Chart

    /// One dot per attempt, in time — Strava's progress graph for a matched
    /// course. The line makes the trend readable; the dots carry the story:
    /// the open outing in the sport's colour, the record in trophy yellow.
    ///
    /// Past a dozen attempts the chart windows itself to roughly ten and
    /// scrolls horizontally, opening on the most recent — forty-nine weekly
    /// footings squeezed into one pane width were a single grey smear.
    @ViewBuilder
    private func chart(_ matches: [Activity]) -> some View {
        let attempts = rows(matches: matches)
            .filter { $0.movingTime > 0 }
            .sorted { $0.startLocalDate < $1.startLocalDate }
        if attempts.count >= 3 {
            let span = attempts.last!.startLocalDate
                .timeIntervalSince(attempts.first!.startLocalDate)
            if attempts.count > 12, span > 0 {
                // Ten *average* gaps of visible window: irregular outings mean
                // some windows show more dots, some fewer, and that is fine.
                let visible = span / Double(attempts.count) * 10
                chartBase(attempts, matches: matches)
                    .chartScrollableAxes(.horizontal)
                    .chartXVisibleDomain(length: visible)
                    .chartScrollPosition(initialX:
                        attempts.last!.startLocalDate.addingTimeInterval(-visible)
                    )
            } else {
                chartBase(attempts, matches: matches)
            }
        }
    }

    /// Plotted in average speed, labelled in the sport's own tongue — pace
    /// for a run, km/h for a ride, /100 m for a swim (what Strava's graph
    /// shows too, not the finish time). Up is faster, which is the way a
    /// progress chart wants to read.
    private func chartBase(
        _ attempts: [Activity], matches: [Activity]
    ) -> some View {
        let bestSpeed = attempts.map(\.averageSpeed).max()
        return Chart(attempts, id: \.id) { attempt in
            LineMark(
                x: .value("Date", attempt.startLocalDate),
                y: .value("Allure", attempt.averageSpeed)
            )
            .foregroundStyle(.quaternary)
            PointMark(
                x: .value("Date", attempt.startLocalDate),
                y: .value("Allure", attempt.averageSpeed)
            )
            .foregroundStyle(pointColor(attempt, bestSpeed: bestSpeed))
            .symbolSize(
                attempt.persistentModelID == activity.persistentModelID ? 90 : 45
            )
        }
        // From the slowest attempt, not from zero: the differences between
        // efforts are seconds per kilometre, and a zero-based axis flattens
        // them into one straight line.
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let speed = value.as(Double.self) {
                        Text(Format.speed(speed, sport: activity.sportType))
                            .monospacedDigit()
                    }
                }
            }
        }
        .frame(height: 110)
    }

    private func pointColor(_ attempt: Activity, bestSpeed: Double?) -> Color {
        if attempt.persistentModelID == activity.persistentModelID {
            return activity.sportType.color
        }
        return attempt.averageSpeed == bestSpeed ? .yellow : .secondary
    }

    /// Six rows, then the list scrolls in place: a weekly loop accumulates
    /// dozens of outings, and the section is a comparison, not an archive.
    /// The cut sits mid-row on purpose — a half-visible line is what says
    /// « there is more » without a scroll indicator asking to be noticed.
    @ViewBuilder
    private func rowList(_ matches: [Activity]) -> some View {
        let stack = VStack(spacing: 2) {
            ForEach(rows(matches: matches), id: \.id) { row in
                rowView(row, matches: matches)
            }
        }
        if matches.count + 1 > 6 {
            ScrollView {
                stack
            }
            .frame(height: 6.5 * 27)
        } else {
            stack
        }
    }

    // MARK: - Matching

    /// Signatures are cached per activity: the section reopens on every
    /// selection change, and a course's simplified track does not move.
    @MainActor
    private enum SignatureCache {
        static var cache: [PersistentIdentifier: [Coordinate]?] = [:]

        static func signature(for activity: Activity) -> [Coordinate]? {
            if let cached = cache[activity.persistentModelID] { return cached }
            let computed = RouteSignature.signature(of: activity.simplifiedCoordinates)
            cache[activity.persistentModelID] = computed
            return computed
        }
    }

    static func matches(for activity: Activity, in all: [Activity]) -> [Activity] {
        guard activity.distance > 0,
              let reference = SignatureCache.signature(for: activity) else { return [] }
        return all.filter { other in
            guard other.persistentModelID != activity.persistentModelID,
                  other.sportType == activity.sportType,
                  // The length gate first: it is free, and it spares decoding
                  // the track of every activity in the library.
                  abs(other.distance - activity.distance)
                      <= max(other.distance, activity.distance) * 0.10,
                  let candidate = SignatureCache.signature(for: other) else {
                return false
            }
            return RouteSignature.matches(
                reference, candidate,
                distanceA: activity.distance, distanceB: other.distance
            )
        }
        .sorted { $0.startLocalDate > $1.startLocalDate }
    }

    // MARK: - Rows

    private func rows(matches: [Activity]) -> [Activity] {
        ([activity] + matches).sorted { $0.startLocalDate > $1.startLocalDate }
    }

    private func bestTime(matches: [Activity]) -> Int? {
        rows(matches: matches).map(\.movingTime).filter { $0 > 0 }.min()
    }

    private func rowView(_ row: Activity, matches: [Activity]) -> some View {
        let isCurrent = row.persistentModelID == activity.persistentModelID
        return Button {
            if !isCurrent { onSelect?(row.persistentModelID) }
        } label: {
            // Sized for the pane's 360 pt floor, not for comfort: fixed
            // columns wider than the pane push the whole detail page
            // sideways. The heart rate lives in the tooltip instead of a
            // column — the gap and the pace are what the comparison is about.
            HStack(spacing: 8) {
                Text(Format.dateOnly(row.startLocalDate))
                    .frame(width: 80, alignment: .leading)
                HStack(spacing: 4) {
                    Text(Format.durationCompact(row.movingTime))
                        .fontWeight(isCurrent ? .semibold : .regular)
                    if row.movingTime == bestTime(matches: matches) {
                        Image(systemName: "trophy.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption2)
                            .help("Meilleur temps sur ce parcours")
                    }
                }
                .frame(width: 74, alignment: .leading)
                Spacer(minLength: 4)
                Text(Format.speed(row.averageSpeed, sport: row.sportType))
                    .frame(width: 74, alignment: .trailing)
                deltaText(row, isCurrent: isCurrent)
                    .frame(width: 62, alignment: .trailing)
            }
            .font(.callout.monospacedDigit())
            .lineLimit(1)
            .foregroundStyle(isCurrent ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(
            isCurrent ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
            in: .rect(cornerRadius: 6)
        )
        .help(rowHelp(row, isCurrent: isCurrent))
    }

    private func rowHelp(_ row: Activity, isCurrent: Bool) -> String {
        let heartrate = row.averageHeartrate.map {
            " — FC moy. \(Int($0.rounded())) bpm"
        } ?? ""
        return isCurrent ? "Cette sortie\(heartrate)" : "\(row.name)\(heartrate)"
    }

    /// Signed gap to the current effort: green when the other outing was
    /// faster — something to chase — red when this one wins.
    @ViewBuilder
    private func deltaText(_ row: Activity, isCurrent: Bool) -> some View {
        if isCurrent || row.movingTime == 0 || activity.movingTime == 0 {
            Text("—").foregroundStyle(.tertiary)
        } else {
            let delta = row.movingTime - activity.movingTime
            Text(delta <= 0
                 ? "−\(Format.durationCompact(-delta))"
                 : "+\(Format.durationCompact(delta))")
                .foregroundStyle(delta <= 0 ? Color.green : Color.red)
        }
    }
}
