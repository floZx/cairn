import Foundation

/// A position in the day's meal list: a meal header, or a food row in it.
/// suivinut's day table had exactly these two kinds of rows — the header is
/// selectable so `a`, `n`, `c`, `s` have a target even in an empty meal.
struct DayCursor: Equatable {
    var mealIndex: Int
    var rowIndex: Int?
}

enum DayCursorModel {
    static func positions(rowCounts: [Int]) -> [DayCursor] {
        var positions: [DayCursor] = []
        for (mealIndex, count) in rowCounts.enumerated() {
            positions.append(DayCursor(mealIndex: mealIndex, rowIndex: nil))
            for rowIndex in 0..<count {
                positions.append(
                    DayCursor(mealIndex: mealIndex, rowIndex: rowIndex)
                )
            }
        }
        return positions
    }

    static func move(
        from current: DayCursor?, by delta: Int, rowCounts: [Int]
    ) -> DayCursor? {
        let all = positions(rowCounts: rowCounts)
        guard !all.isEmpty else { return nil }
        guard let current, let index = all.firstIndex(of: current) else {
            // Same rule as the activity list: `j` starts at the top, `k` at
            // the bottom, so both do something on an untouched screen.
            return delta >= 0 ? all.first : all.last
        }
        return all[min(max(index + delta, 0), all.count - 1)]
    }

    static func clamp(
        _ cursor: DayCursor?, rowCounts: [Int]
    ) -> DayCursor? {
        guard let cursor else { return nil }
        let all = positions(rowCounts: rowCounts)
        guard !all.isEmpty else { return nil }
        if all.contains(cursor) { return cursor }
        // The exact spot is gone (deleted row, shorter day): the nearest
        // earlier position keeps the hands where the eyes already are.
        let meal = min(cursor.mealIndex, rowCounts.count - 1)
        if let row = cursor.rowIndex, cursor.mealIndex < rowCounts.count {
            let count = rowCounts[cursor.mealIndex]
            if count > 0 {
                return DayCursor(
                    mealIndex: cursor.mealIndex,
                    rowIndex: min(row, count - 1)
                )
            }
            return DayCursor(mealIndex: cursor.mealIndex, rowIndex: nil)
        }
        let count = rowCounts[meal]
        return DayCursor(mealIndex: meal, rowIndex: count > 0 ? count - 1 : nil)
    }
}
