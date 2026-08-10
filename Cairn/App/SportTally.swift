import Foundation

/// How many activities each sport has, in the order the filter list shows them.
enum SportTally {
    struct Row: Equatable, Identifiable {
        var sport: SportType
        var count: Int
        var id: SportType { sport }
    }

    /// Most-used first, ties broken by name.
    ///
    /// The count alone is not an order. `Dictionary` hands its pairs back in
    /// whatever order its buckets happen to be in, and `sorted(by:)` makes no
    /// stability promise, so two sports on the same count had nothing deciding
    /// between them: Randonnée and Vélo, both on 55, traded rows on their own
    /// every time the list was rebuilt. A name to fall back on makes the order
    /// a function of the data and of nothing else.
    static func rows(for sports: [SportType]) -> [Row] {
        Dictionary(grouping: sports, by: { $0 })
            .map { Row(sport: $0.key, count: $0.value.count) }
            .sorted { first, second in
                guard first.count == second.count else {
                    return first.count > second.count
                }
                return first.sport.displayName
                    .localizedCaseInsensitiveCompare(second.sport.displayName)
                    == .orderedAscending
            }
    }
}
