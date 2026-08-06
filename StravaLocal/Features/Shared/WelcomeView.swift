import SwiftUI

struct WelcomeView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ContentUnavailableView {
            Label("Aucune donnée locale", systemImage: "arrow.down.circle")
        } description: {
            Text(
                app.isAuthenticated
                    ? "Lancez une synchronisation pour récupérer vos activités Strava."
                    : "Connectez votre compte Strava pour commencer, puis lancez une synchronisation."
            )
        } actions: {
            if app.isAuthenticated {
                Button("Synchroniser maintenant") { app.syncNow() }
                    .disabled(app.progress.isRunning)
            } else {
                Button("Ouvrir les réglages…") { openSettings() }
            }
        }
    }
}
