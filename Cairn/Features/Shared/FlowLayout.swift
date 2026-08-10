import SwiftUI

/// The wrapping decision, kept apart from the layout so it can be tested
/// without a view hierarchy.
enum FlowRows {
    /// Groups item indices into rows that fit within `maxWidth`.
    static func rows(
        widths: [CGFloat], spacing: CGFloat, maxWidth: CGFloat
    ) -> [[Int]] {
        var rows: [[Int]] = []
        var current: [Int] = []
        var used: CGFloat = 0
        for (index, width) in widths.enumerated() {
            let needed = current.isEmpty ? width : used + spacing + width
            // The `current.isEmpty` guard is what stops an item wider than the
            // whole line from being pushed off a row it could never fit on,
            // leaving an empty row above it and itself alone below.
            if !current.isEmpty, needed > maxWidth {
                rows.append(current)
                current = [index]
                used = width
            } else {
                current.append(index)
                used = needed
            }
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }
}

/// Rows of items that wrap when the next one would not fit.
///
/// SwiftUI ships no wrapping stack, and an `HStack` of six chips inside a pane
/// the user has dragged down to its 360 pt floor simply runs off the edge —
/// the same failure the "Parcours similaires" columns had.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
    ) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let limit = proposal.width ?? .infinity
        let rows = FlowRows.rows(
            widths: sizes.map(\.width), spacing: spacing, maxWidth: limit
        )
        let height = rows.enumerated().reduce(CGFloat.zero) { total, row in
            let tallest = row.element.map { sizes[$0].height }.max() ?? 0
            return total + tallest + (row.offset == 0 ? 0 : lineSpacing)
        }
        let rowWidths: [CGFloat] = rows.map { row in
            let content: CGFloat = row.reduce(CGFloat.zero) { $0 + sizes[$1].width }
            let gaps = CGFloat(max(0, row.count - 1))
            return content + spacing * gaps
        }
        let width: CGFloat = rowWidths.max() ?? 0
        return CGSize(width: min(width, limit), height: height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
        cache: inout Void
    ) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = FlowRows.rows(
            widths: sizes.map(\.width), spacing: spacing, maxWidth: bounds.width
        )
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            let tallest = row.map { sizes[$0].height }.max() ?? 0
            for index in row {
                subviews[index].place(
                    // Centred on the row's own height: chips of different
                    // heights on one line would otherwise hang from its top.
                    at: CGPoint(x: x, y: y + (tallest - sizes[index].height) / 2),
                    proposal: ProposedViewSize(sizes[index])
                )
                x += sizes[index].width + spacing
            }
            y += tallest + lineSpacing
        }
    }
}
