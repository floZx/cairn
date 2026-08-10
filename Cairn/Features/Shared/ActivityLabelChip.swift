import SwiftUI

/// One marker as a chip: its symbol, its name, a capsule to sit in.
///
/// Quiet on purpose — secondary text on the faintest fill the system offers.
/// The header already carries the sport's colour twice, in the label above the
/// title and in the watermark behind it; a row of coloured badges under it
/// would be the loudest thing on a pane whose subject is the outing's name.
/// Only the favourite's star keeps its yellow, which it has everywhere else.
struct ActivityLabelChip: View {
    let label: ActivityLabel

    /// Drops the word and keeps the symbol, for the card list: a 42 pt row
    /// has no room for six names, and the date beside them is what the row is
    /// actually indexed by. The name moves to the tooltip rather than being
    /// lost — these symbols are learned in a day, but not in a second.
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: label.symbolName)
                .foregroundStyle(
                    label == .favorite
                        ? AnyShapeStyle(.yellow) : AnyShapeStyle(.secondary)
                )
            if !compact {
                Text(label.displayName)
                    .foregroundStyle(.secondary)
            }
        }
        .font(compact ? .caption2 : .caption)
        .padding(.horizontal, compact ? 5 : 8)
        .padding(.vertical, compact ? 1 : 3)
        .background(.quaternary, in: .capsule)
        .help(compact ? label.displayName : "")
    }
}
