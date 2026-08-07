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
    /// Set when `restore` fails: this section is opened maybe twice a year,
    /// far from `RootView`'s own alert, and a click with no visible effect —
    /// the row simply stays put — would otherwise read as nothing happened
    /// rather than as a failure to report.
    @State private var restoreFailureMessage: String?

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
                            do {
                                try ImportMapper(context: modelContext).restore(stone)
                            } catch {
                                restoreFailureMessage =
                                    "Cette activité n'a pas pu être réintégrée. \(error.localizedDescription)"
                            }
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
        .alert(
            "Échec de la réintégration",
            isPresented: Binding(
                get: { restoreFailureMessage != nil },
                set: { if !$0 { restoreFailureMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { restoreFailureMessage = nil }
        } message: {
            Text(restoreFailureMessage ?? "")
        }
    }
}
