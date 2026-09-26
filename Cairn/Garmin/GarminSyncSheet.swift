import SwiftUI

/// Finds an activity on Garmin Connect, shows what differs from Cairn field
/// by field, and writes the fields left ticked.
///
/// Nothing is written before the button is pressed: the first thing this
/// sheet does is read, and what it reads is shown old → new so the change
/// can be judged before it happens.
struct GarminSyncSheet: View {
    let activityUUID: String
    let source: GarminSource
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case loading
        case noMatch
        case failed(String)
        case ready(GarminActivity, GarminProposal, currentGear: [GarminGear])
        case applying
        case done
    }

    @State private var phase = Phase.loading
    @State private var selected: Set<GarminProposal.Field> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Envoyer sur Garmin Connect").font(.headline)

            content
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer()
                Button(isFinished ? "Fermer" : "Annuler") { dismiss() }
                    .keyboardShortcut(isFinished ? .defaultAction : .cancelAction)
                if case let .ready(garmin, proposal, currentGear) = phase, !proposal.isEmpty {
                    Button("Envoyer") {
                        apply(proposal, to: garmin, currentGear: currentGear)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected.isEmpty)
                }
            }
        }
        .padding(20)
        .frame(width: 520)
        .task { await load() }
    }

    private var isFinished: Bool {
        switch phase {
        case .done, .noMatch, .failed: true
        case let .ready(_, proposal, _): proposal.isEmpty
        default: false
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView("Recherche de l'activité sur Garmin…")
                .controlSize(.small)
        case .applying:
            ProgressView("Envoi…").controlSize(.small)
        case .noMatch:
            Label(
                "Aucune activité Garmin ne commence à moins de 20 minutes de celle-ci.",
                systemImage: "questionmark.circle"
            )
            .foregroundStyle(.secondary)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        case .done:
            Label("Garmin Connect est à jour.", systemImage: "checkmark.circle")
        case let .ready(garmin, proposal, _):
            VStack(alignment: .leading, spacing: 12) {
                Text("« \(garmin.name) » sur Garmin")
                    .foregroundStyle(.secondary)
                if proposal.isEmpty {
                    Label("Rien à changer : Garmin dit déjà la même chose.", systemImage: "checkmark.circle")
                } else {
                    ForEach(proposal.changes) { change in
                        changeRow(change)
                    }
                }
                if let gear = proposal.unmatchedGearName {
                    Label(
                        "Pas de matériel Garmin dont le nom ressemble à « \(gear) ».",
                        systemImage: "info.circle"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func changeRow(_ change: GarminProposal.Change) -> some View {
        Toggle(isOn: Binding(
            get: { selected.contains(change.field) },
            set: { on in
                if on { selected.insert(change.field) } else { selected.remove(change.field) }
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(change.field.displayName).fontWeight(.medium)
                Text(change.current.isEmpty ? "—" : change.current)
                    .strikethrough()
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Text(change.proposed)
                    .lineLimit(6)
            }
            .textSelection(.enabled)
        }
        .toggleStyle(.checkbox)
    }

    private func load() async {
        phase = .loading
        do {
            try await show(app.garmin.compare(source))
        } catch {
            fail(error)
        }
    }

    /// Shows a comparison and tells the tracker, so the pane behind says
    /// the same thing as this sheet once it closes.
    private func show(_ comparison: GarminComparison?) {
        guard let comparison else {
            phase = .noMatch
            return
        }
        app.garminSync.record(comparison, uuid: activityUUID, source: source)
        selected = Set(comparison.proposal.changes.map(\.field))
        phase = .ready(
            comparison.activity, comparison.proposal, currentGear: comparison.currentGear
        )
    }

    private func apply(
        _ proposal: GarminProposal, to activity: GarminActivity, currentGear: [GarminGear]
    ) {
        phase = .applying
        Task {
            do {
                let garmin = app.garmin
                var type: GarminActivityType?
                if selected.contains(.type), let key = proposal.typeKey {
                    type = try await garmin.activityTypes().first { $0.typeKey == key }
                    if type == nil {
                        throw GarminError.http(404, "type « \(key) » inconnu de Garmin")
                    }
                }
                try await garmin.updateActivity(
                    id: activity.id,
                    name: selected.contains(.name) ? proposal.name : nil,
                    description: selected.contains(.description) ? proposal.description : nil,
                    type: type
                )
                if selected.contains(.gear), let wanted = proposal.gearUUIDs {
                    let current = Set(currentGear.map(\.uuid))
                    for uuid in current.subtracting(wanted) {
                        try await garmin.unlink(gear: uuid, fromActivity: activity.id)
                    }
                    for uuid in Set(wanted).subtracting(current) {
                        try await garmin.link(gear: uuid, toActivity: activity.id)
                    }
                }
                // Read back rather than assumed: it confirms the write, and a
                // field left unticked keeps the activity « à synchroniser ».
                let after = try await garmin.compare(source)
                if let after, after.proposal.isEmpty {
                    app.garminSync.record(after, uuid: activityUUID, source: source)
                    phase = .done
                } else {
                    show(after)
                }
            } catch {
                fail(error)
            }
        }
    }

    private func fail(_ error: Error) {
        phase = .failed(error.localizedDescription)
        // A refused refresh signs out inside the client; the settings and
        // the button should say so without waiting for a relaunch.
        app.refreshGarminState()
    }
}
