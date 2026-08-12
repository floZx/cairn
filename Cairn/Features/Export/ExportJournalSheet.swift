import SwiftUI

/// The two dates a book covers, and the wait while it is made.
///
/// The sheet stays up during the making rather than closing on a window that
/// has stopped answering: map snapshots are round trips to a tile server, and
/// ten silent seconds read as a freeze. It closes when the file is written.
struct ExportJournalSheet: View {
    /// Where the export has got to. Two phases and not one number, because the
    /// second is the one nobody expects: once every picture is drawn, WebKit
    /// still has a whole book to lay out, and a bar sitting full at 100 % while
    /// that happens is a bar that lies. Measured on a thirty-two-month export —
    /// 2 571 pictures drawn, then minutes of silence.
    enum Progress: Equatable {
        case drawing(done: Int, total: Int)
        case layingOut
    }

    @Binding var from: DateKey
    @Binding var to: DateKey
    /// Roughly how many pictures the chosen period will need, so the size of
    /// what is about to be asked for is visible before it is asked for.
    let imageCount: Int
    let progress: Progress?
    let onExport: () -> Void
    let onCancel: () -> Void

    /// Past this, an export is a matter of minutes rather than seconds, and
    /// saying so beforehand is the difference between waiting and wondering.
    private static let longExport = 300

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
                    DatePicker("", selection: date($from), displayedComponents: .date)
                        .labelsHidden()
                }
                GridRow {
                    Text("Au")
                    DatePicker("", selection: date($to), displayedComponents: .date)
                        .labelsHidden()
                }
            }
            .disabled(progress != nil)

            if progress == nil {
                estimate
            }

            if let progress {
                waiting(progress)
            } else {
                HStack {
                    Spacer()
                    Button("Annuler", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                    Button("Exporter…", action: onExport)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var estimate: some View {
        Label {
            Text(
                imageCount > Self.longExport
                    ? "Environ \(imageCount) images à dessiner : comptez "
                        + "plusieurs minutes."
                    : "Environ \(imageCount) images à dessiner."
            )
        } icon: {
            Image(systemName: imageCount > Self.longExport
                ? "exclamationmark.triangle" : "photo")
        }
        .font(.callout)
        .foregroundStyle(imageCount > Self.longExport ? .orange : .secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func waiting(_ progress: Progress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            switch progress {
            case let .drawing(done, total):
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                Text("Image \(done) sur \(total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            case .layingOut:
                ProgressView().progressViewStyle(.linear)
                Text("Mise en page du carnet…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// A `DatePicker` speaks `Date`; the rest of the app speaks `DateKey`, and
    /// a day is what a book is cut into.
    private func date(_ key: Binding<DateKey>) -> Binding<Date> {
        Binding(
            get: { key.wrappedValue.date() },
            set: { key.wrappedValue = DateKey($0) }
        )
    }
}
