import SwiftUI
import SwiftData

/// The activities discarded from the journal, and the way back.
///
/// Without this screen a deletion would be both permanent and invisible, which
/// is the worst of the two: the point of a tombstone is that a resync cannot
/// undo the decision, not that the decision cannot be revisited.
struct DiscardedActivitiesSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DiscardedActivity.discardedAt, order: .reverse)
    private var discarded: [DiscardedActivity]

    var body: some View {
        Section {
            if discarded.isEmpty {
                Text("Aucune activité écartée.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(discarded) { stone in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(stone.name)
                            Text("Écartée le \(Format.dateOnly(stone.discardedAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Réintégrer") {
                            try? ImportMapper(context: modelContext).restore(stone)
                        }
                    }
                }
            }
        } header: {
            Text("Activités écartées")
        } footer: {
            Text(
                "Ces activités Strava ont été supprimées du journal et ne "
                    + "reviendront pas lors d'une synchronisation. Les "
                    + "réintégrer les laissera revenir au passage suivant."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
