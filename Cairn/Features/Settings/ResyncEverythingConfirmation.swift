import SwiftUI
import SwiftData

/// « Resynchroniser tout », demandé avant d'être lancé.
///
/// Le seul geste de synchronisation qui coûte cher : il redemande à Strava le
/// détail de chaque sortie, une requête par activité, soit environ une heure
/// de quota pour une bibliothèque de neuf cents. Il part du menu Strava comme
/// des réglages, d'où un modificateur plutôt qu'un dialogue écrit deux fois.
struct ResyncEverythingConfirmation: ViewModifier {
    @Binding var isPresented: Bool
    @Environment(AppEnvironment.self) private var app
    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Resynchroniser toutes les activités ?",
            isPresented: $isPresented,
            titleVisibility: .visible
        ) {
            Button("Resynchroniser") { app.resyncEverything() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(Self.message(activityCount: stravaActivityCount))
        }
    }

    private var stravaActivityCount: Int {
        let strava = ActivitySource.strava.rawValue
        let descriptor = FetchDescriptor<Activity>(predicate: #Predicate { $0.sourceRaw == strava })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Strava laisse passer 200 requêtes par quart d'heure et 2 000 par jour :
    /// ce sont ces deux plafonds qui font la durée.
    static func message(activityCount: Int) -> String {
        let quarters = max(1, Int((Double(activityCount) / 200).rounded(.up)))
        let duration = activityCount > 2_000
            ? "plusieurs jours, Strava n'en laissant passer que 2 000 par jour,"
            : quarters * 15 < 60
            ? "\(quarters * 15) minutes"
            : "environ \(Int((Double(quarters) / 4).rounded())) h"
        return """
            Cairn redemande à Strava le résumé et le détail de chacune des \
            \(activityCount) activités : une requête par activité, soit \(duration) \
            au rythme que Strava autorise. Les corrections faites dans Cairn sont gardées.
            """
    }
}

extension View {
    func resyncEverythingConfirmation(isPresented: Binding<Bool>) -> some View {
        modifier(ResyncEverythingConfirmation(isPresented: isPresented))
    }
}
