import SwiftUI

/// One panel of the statistics dashboard: a title, an optional line under it,
/// and its content on a faint ground.
///
/// The ground is the one the journal and people cards already use, so the
/// screens read as one application. Faint on purpose: the figures are what
/// should stand out, not the boxes around them.
struct StatsCard<Content: View, Accessory: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    init(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 12)
                accessory
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
    }
}

/// A large figure with its caption and, when there is something to compare
/// against, how it moved.
struct KeyFigure: View {
    let title: String
    let value: String
    var change: Int?
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.title.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let change {
                ChangeBadge(percent: change)
            } else if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// « ↑ 12 % » — the web's evolution, in the same colours: green says "up",
/// not "better", and zero is neither.
struct ChangeBadge: View {
    let percent: Int
    var suffix = "vs période précédente"

    var body: some View {
        HStack(spacing: 4) {
            Text(arrow + " \(abs(percent)) %")
                .fontWeight(.semibold)
                .foregroundStyle(color)
            Text(suffix).foregroundStyle(.tertiary)
        }
        .font(.caption.monospacedDigit())
        .lineLimit(1)
    }

    private var arrow: String { percent > 0 ? "↑" : percent < 0 ? "↓" : "=" }
    private var color: Color { percent > 0 ? .green : percent < 0 ? .orange : .secondary }

    /// The change in percent, or nil when there is nothing to compare with:
    /// "+∞ %" is not information.
    static func percent(_ current: Double, _ before: Double) -> Int? {
        guard before > 0 else { return nil }
        return Int(((current - before) / before * 100).rounded())
    }
}
