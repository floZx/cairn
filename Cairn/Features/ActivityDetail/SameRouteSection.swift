import SwiftUI
import SwiftData

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
                Text("Même parcours").font(.headline)
                Text(
                    "\(matches.count + 1) sorties sur ce tracé — "
                    + "l'écart se lit face à celle-ci."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                VStack(spacing: 2) {
                    ForEach(rows(matches: matches), id: \.id) { row in
                        rowView(row, matches: matches)
                    }
                }
            }
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
