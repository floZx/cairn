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

    /// One dot per attempt, evenly spaced — Strava's progress graph for a
    /// matched course. Spaced by attempt rather than by date: placed in time,
    /// forty-nine weekly footings were a grey smear, then a window that had
    /// to be scrolled; one step each, fifty fit a pane and read at a glance.
    /// Around them, the trend and the three lines worth naming — fastest,
    /// average, slowest — where an axis of round paces used to be.
    @ViewBuilder
    private func chart(_ matches: [Activity]) -> some View {
        let attempts = rows(matches: matches)
            .filter { $0.movingTime > 0 && $0.averageSpeed > 0 }
            .sorted { $0.startLocalDate < $1.startLocalDate }
        if let progress = RouteProgress(speeds: attempts.map(\.averageSpeed)) {
            VStack(alignment: .leading, spacing: 6) {
                progressChart(attempts, progress)
                legend(attempts, progress)
            }
        }
    }

    /// Plotted in average speed, labelled in the sport's own tongue — pace
    /// for a run, km/h for a ride, /100 m for a swim. Up is faster, which is
    /// the way a progress chart wants to read.
    private func progressChart(_ attempts: [Activity], _ progress: RouteProgress) -> some View {
        let sport = activity.sportType
        let color = sport.color
        let points = Array(attempts.enumerated())
        let current = attempts.firstIndex { $0.persistentModelID == activity.persistentModelID }
        let best = progress.speeds.firstIndex(of: progress.fastest)
        let pad = max((progress.fastest - progress.slowest) * 0.15, progress.average * 0.01)

        return Chart {
            // The attempts joined by a thread, faint: it says the order, the
            // trend says the direction.
            ForEach(points, id: \.offset) { index, attempt in
                LineMark(
                    x: .value("Sortie", index), y: .value("Vitesse", attempt.averageSpeed),
                    series: .value("Série", "sorties")
                )
                .foregroundStyle(color.opacity(0.25))
                .lineStyle(StrokeStyle(lineWidth: 1))
            }
            ForEach(Array(progress.trend.enumerated()), id: \.offset) { index, speed in
                LineMark(
                    x: .value("Sortie", index), y: .value("Vitesse", speed),
                    series: .value("Série", "tendance")
                )
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .interpolationMethod(.catmullRom)
            }
            ForEach(points, id: \.offset) { index, attempt in
                let point = PointMark(
                    x: .value("Sortie", index), y: .value("Vitesse", attempt.averageSpeed)
                )
                if index == current {
                    point.symbolSize(110).foregroundStyle(color)
                } else if index == best {
                    point.symbol {
                        Circle().strokeBorder(Color.yellow, lineWidth: 2.5)
                            .background(Circle().fill(.background))
                            .frame(width: 11, height: 11)
                    }
                } else {
                    point.symbol {
                        Circle().strokeBorder(color.opacity(0.7), lineWidth: 1.2)
                            .background(Circle().fill(.background))
                            .frame(width: 7, height: 7)
                    }
                }
            }
        }
        .chartXScale(domain: -0.5...(Double(attempts.count) - 0.5))
        .chartYScale(domain: (progress.slowest - pad)...(progress.fastest + pad))
        .chartXAxis {
            // The first and the last day only: in between, the steps are
            // attempts, and dates would pretend to be a time scale.
            AxisMarks(values: [0, attempts.count - 1]) { value in
                AxisValueLabel(anchor: value.index == 0 ? .topLeading : .topTrailing) {
                    if let index = value.as(Int.self), attempts.indices.contains(index) {
                        Text(Format.dateOnly(attempts[index].startLocalDate))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(
                position: .trailing,
                values: [progress.fastest, progress.average, progress.slowest]
            ) { value in
                let speed = value.as(Double.self) ?? 0
                let isAverage = abs(speed - progress.average) < 1e-9
                AxisGridLine(
                    stroke: StrokeStyle(lineWidth: 0.8, dash: isAverage ? [] : [3, 3])
                )
                AxisValueLabel {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(isAverage ? "Moyenne"
                             : abs(speed - progress.fastest) < 1e-9 ? "Le plus rapide" : "Le plus lent")
                            .foregroundStyle(.secondary)
                        Text(Format.speed(speed, sport: sport))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    .font(.caption2)
                }
            }
        }
        .frame(height: 170)
    }

    /// How many, what the thick line is, and where this one stands.
    private func legend(_ attempts: [Activity], _ progress: RouteProgress) -> some View {
        let color = activity.sportType.color
        let comparison = RouteProgress.comparison(
            activity.averageSpeed, average: progress.average, sport: activity.sportType
        )
        return HStack(spacing: 6) {
            Text("\(attempts.count) sorties").fontWeight(.medium)
            Capsule().fill(color).frame(width: 14, height: 3)
                .padding(.leading, 6)
            Text("tendance sur 5 sorties").foregroundStyle(.secondary)
            Spacer(minLength: 12)
            if let comparison {
                Text("Celle-ci : \(comparison)")
                    .foregroundStyle(
                        activity.averageSpeed > progress.average ? .green : .secondary
                    )
            }
        }
        .font(.caption)
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
            //
            // The date got 20 pt more — « 24 sept. 2026 » was cut to « 24
            // sept. 20… » at 80 — taken from the time (« 3 h 14 » and its
            // trophy fit in 62) and the gap (« +3 min » in 54), so the row
            // still adds up to what the 360 pt floor leaves.
            HStack(spacing: 8) {
                Text(Format.dateOnly(row.startDate, in: row.timeZone))
                    .frame(width: 100, alignment: .leading)
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
                .frame(width: 62, alignment: .leading)
                Spacer(minLength: 4)
                Text(Format.speed(row.averageSpeed, sport: row.sportType))
                    .frame(width: 74, alignment: .trailing)
                deltaText(row, isCurrent: isCurrent)
                    .frame(width: 54, alignment: .trailing)
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
