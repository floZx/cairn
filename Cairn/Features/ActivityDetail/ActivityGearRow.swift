import SwiftUI
import SwiftData

/// The gear an activity was done with, on a line of its own.
///
/// It used to be the last tile of the figures grid: a name among numbers,
/// wrapping onto two lines, read as one more statistic. It isn't one, so it
/// gets the surface the note has. Changing it is the editor's job, like every
/// other field of the activity.
struct ActivityGearRow: View {
    let activity: Activity
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if let gear = activity.gear {
            HStack(spacing: 10) {
                Image(systemName: gear.isBike ? "bicycle" : "shoe")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(gear.name).fontWeight(.medium)
                    // Always a second line, as the weather card beside it has:
                    // two cards of different heights side by side looked
                    // unfinished.
                    Text((Self.detail(for: gear) ?? (gear.isBike ? "Vélo" : "Chaussures"))
                         + " · " + Format.distance(totalDistance(of: gear)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            // The note's surface, a few lines up: the same vocabulary for the
            // two things on this screen that aren't a figure.
            .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
            .help("Se change dans « Modifier l'activité » (⌘E)")
        }
    }

    /// The kilometres the gear carries, summed over every outing in the
    /// store — the same count as the statistics' « Matériel ». Not Strava's
    /// own total: it drifted, 1 043 km for a pair that has run 1 405.
    private func totalDistance(of gear: Gear) -> Double {
        let id = gear.stravaID
        let descriptor = FetchDescriptor<Activity>(predicate: #Predicate { $0.gearID == id })
        let activities = (try? modelContext.fetch(descriptor)) ?? []
        return activities.reduce(0) { $0 + $1.distance }
    }

    /// Brand and model when the name doesn't already say them.
    static func detail(for gear: Gear) -> String? {
        let name = gear.name.lowercased()
        let make = [gear.brandName, gear.modelName]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !name.contains($0.lowercased()) }
            .joined(separator: " ")
        return make.isEmpty ? nil : make
    }
}
