import SwiftUI

/// The two dates a book covers, and the wait while it is drawn.
///
/// The sheet stays up during the drawing rather than closing on a window that
/// has stopped answering: map snapshots are round trips to a tile server, and
/// ten silent seconds read as a freeze. It closes when the file is written.
struct ExportJournalSheet: View {
    /// Where the export has got to, owned by the caller — it is the one doing
    /// the work.
    struct Progress: Equatable {
        var done: Int
        var total: Int
    }

    @State private var from: Date
    @State private var to: Date
    let progress: Progress?
    let onExport: (DateKey, DateKey) -> Void
    let onCancel: () -> Void

    init(
        from: DateKey, to: DateKey, progress: Progress?,
        onExport: @escaping (DateKey, DateKey) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _from = State(initialValue: from.date())
        _to = State(initialValue: to.date())
        self.progress = progress
        self.onExport = onExport
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Exporter le journal en PDF").font(.headline)
            Text(
                "Un carnet à relire : les notes du journal, les sorties avec "
                    + "leur carte et leurs courbes, les photos, l'alimentation "
                    + "et le poids."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Du")
                    DatePicker("", selection: $from, displayedComponents: .date)
                        .labelsHidden()
                }
                GridRow {
                    Text("Au")
                    DatePicker("", selection: $to, displayedComponents: .date)
                        .labelsHidden()
                }
            }
            .disabled(progress != nil)

            if let progress {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(
                        value: Double(progress.done),
                        total: Double(max(progress.total, 1))
                    )
                    Text("Image \(progress.done) sur \(progress.total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } else {
                HStack {
                    Spacer()
                    Button("Annuler", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                    Button("Exporter…") {
                        onExport(DateKey(from), DateKey(to))
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
