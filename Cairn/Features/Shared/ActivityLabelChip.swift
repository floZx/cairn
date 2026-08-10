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

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: label.symbolName)
                .foregroundStyle(
                    label == .favorite
                        ? AnyShapeStyle(.yellow) : AnyShapeStyle(.secondary)
                )
            Text(label.displayName)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.quaternary, in: .capsule)
    }
}
