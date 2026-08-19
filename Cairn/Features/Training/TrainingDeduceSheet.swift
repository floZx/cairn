import SwiftUI
import SwiftData

/// « Déduire les types manquants » : l'aperçu, puis l'écriture.
///
/// La même forme que la reprise du calendrier — voir, puis décider — parce que
/// c'est la même nature d'opération : une devinette appliquée en masse.
struct TrainingDeduceSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var propositions: [TrainingNutrition.Proposition] = []
    @State private var posees: Int?
    @State private var echec: String?

    private static let jourCourt: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEE d MMM yyyy"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Déduire les types de journée")
                .font(.headline)
            Text("""
                D'après ce qui est prévu : repos les jours vides, sortie longue \
                au-delà d'une heure et demie, qualité sur les séries. \
                Les journées dont le type est déjà choisi ne sont pas touchées.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)

            if let echec {
                Label(echec, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else if let posees {
                Label(
                    posees == 0
                        ? "Rien à poser : tout est déjà réglé."
                        : "\(posees) journée\(posees > 1 ? "s" : "") réglée\(posees > 1 ? "s" : "").",
                    systemImage: "checkmark.circle"
                )
                .foregroundStyle(.green)
            } else if propositions.isEmpty {
                Text("Aucune journée à régler.")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(propositions.count) journées à régler")
                    .font(.callout.weight(.medium))
                Table(propositions) {
                    TableColumn("Jour") { proposition in
                        Text(Self.jourCourt.string(from: proposition.dateKey.date()))
                            .monospacedDigit()
                    }
                    .width(120)
                    TableColumn("Type") { proposition in
                        Text("\(proposition.type.name) · \(proposition.type.kcalTarget) kcal")
                    }
                    .width(200)
                    TableColumn("Ce qui est prévu") { proposition in
                        Text(proposition.resume).lineLimit(1)
                    }
                }
                .frame(height: 320)
            }

            HStack {
                Spacer()
                Button("Fermer", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if posees == nil, !propositions.isEmpty {
                    Button("Appliquer") { appliquer() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 640)
        .onAppear(perform: preparer)
    }

    private func preparer() {
        do { propositions = try TrainingNutrition.propositions(dans: context) }
        catch { echec = error.localizedDescription }
    }

    private func appliquer() {
        do { posees = try TrainingNutrition.ecrire(propositions, dans: context) }
        catch { echec = error.localizedDescription }
    }
}
