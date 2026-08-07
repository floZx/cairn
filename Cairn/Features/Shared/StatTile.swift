import SwiftUI

/// A caption over a figure — the unit of a stats grid.
///
/// Shared by the activity detail pane and the statistics view rather than
/// written twice: the two are read side by side, so a difference in type size or
/// spacing between them would show.
struct StatTile: View {
    let title: String
    let value: String

    init(_ title: String, _ value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            // Monospaced digits so a column of figures lines up.
            Text(value).font(.title3.monospacedDigit())
        }
    }
}
