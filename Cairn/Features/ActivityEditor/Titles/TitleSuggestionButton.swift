import SwiftUI
import SwiftData

/// The ✨ offering a few titles to pick from — beside the editor's name
/// field, and beside a banal title in the activity's pane.
///
/// Worked out on the first click — the communes cost a few geocoding
/// requests, the rest a pass over the library — then kept while the button
/// is on screen.
@available(macOS 26.0, *)
struct TitleSuggestionButton: View {
    let activity: Activity
    /// What the titles are read from: the editor's draft, so a sport changed
    /// a second ago counts, or the activity as stored.
    let draft: ActivityDraft
    let onPick: (String) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var showsPopover = false
    @State private var titles: [String]?
    @State private var task: Task<Void, Never>?

    var body: some View {
        Button {
            showsPopover = true
            if titles == nil, task == nil { gather() }
        } label: {
            Image(systemName: "sparkles")
        }
        .buttonStyle(.borderless)
        .help("Proposer des titres")
        .popover(isPresented: $showsPopover, arrowEdge: .bottom) {
            popover
        }
        .onDisappear { task?.cancel() }
    }

    @ViewBuilder
    private var popover: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let titles {
                if titles.isEmpty {
                    Text("Rien à proposer pour cette activité.")
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
                ForEach(titles, id: \.self) { title in
                    SuggestionRow(title: title) {
                        onPick(title)
                        showsPopover = false
                    }
                }
            } else {
                ProgressView("Recherche des lieux traversés…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
        .padding(8)
        .frame(width: 320)
    }

    private func gather() {
        task = Task {
            let library = (try? modelContext.fetch(FetchDescriptor<Activity>())) ?? []
            var ingredients = TitleIngredientsBuilder.build(
                activity: activity, draft: draft, library: library
            )
            ingredients.places = await TitleIngredientsBuilder.places(
                along: activity.simplifiedCoordinates
            )
            guard !Task.isCancelled else { return }
            titles = TitleSuggestions.make(ingredients, avoiding: draft.name)
            task = nil
        }
    }
}

/// One proposal, highlighted under the pointer like a menu item.
private struct SuggestionRow: View {
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            // On two lines when it must: long commune names — « Boucle bien
            // vallonnée par Saint-Chamond » — were cut at the popover's edge.
            Text(title)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                    in: .rect(cornerRadius: 5)
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
