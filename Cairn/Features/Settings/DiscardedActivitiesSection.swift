import SwiftUI
import SwiftData

/// The activities discarded from the journal, and the way back.
///
/// Without this screen a deletion would be both permanent and invisible, which
/// is the worst of the two: the point of a tombstone is that a resync cannot
/// undo the decision, not that the decision cannot be revisited.
struct DiscardedActivitiesSection: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DiscardedActivity.discardedAt, order: .reverse)
    private var discarded: [DiscardedActivity]
    /// Set when `restore` fails: this section is opened maybe twice a year,
    /// far from `RootView`'s own alert, and a click with no visible effect —
    /// the row simply stays put — would otherwise read as nothing happened
    /// rather than as a failure to report.
    @State private var restoreFailureMessage: String?
    /// What just happened, in words. Reinstating only lifts the tombstone and
    /// pulls the sync cursor back; the activity itself returns on the next pass.
    /// The row vanishing was the only feedback, which read as "it is back" when
    /// nothing had come back yet.
    @State private var confirmation: String?

    /// Lifts the tombstone, then goes and fetches the activity straight away.
    ///
    /// Reinstating without syncing is what made this look broken: the row
    /// disappeared, the journal was unchanged, and the activity only reappeared
    /// at the next launch — because launching is what runs a sync. "Reinstate"
    /// has to mean the activity comes back, not that a flag was cleared.
    private func restore(_ stone: DiscardedActivity) {
        let name = stone.name
        do {
            try ImportMapper(context: modelContext).restore(stone)
        } catch {
            restoreFailureMessage =
                "Cette activité n'a pas pu être réintégrée. \(error.localizedDescription)"
            return
        }
        let canSync = app.isAuthenticated && !app.progress.isRunning
        if canSync { app.syncNow() }
        confirmation = Self.confirmation(name: name, syncStarted: canSync)
    }

    /// Says what will actually bring the activity back, which differs depending
    /// on whether a sync could be started here and now.
    static func confirmation(name: String, syncStarted: Bool) -> String {
        syncStarted
            ? "« \(name) » réintégrée, synchronisation lancée pour la récupérer."
            : "« \(name) » réintégrée. Elle reviendra à la prochaine synchronisation."
    }

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
                        Button("Réintégrer") { restore(stone) }
                    }
                }
            }
            if let confirmation {
                Text(confirmation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Activités écartées")
        } footer: {
            Text(
                "Ces activités Strava ont été supprimées du journal et ne "
                    + "reviendront pas lors d'une synchronisation. Les "
                    + "réintégrer relance une synchronisation pour aller les "
                    + "rechercher."
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
