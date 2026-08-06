import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppEnvironment.self) private var app
    @Query private var activities: [Activity]

    var body: some View {
        VStack(spacing: 12) {
            Text("\(activities.count) activités en local")
                .font(.title2)
            Text(app.progress.statusText)
                .foregroundStyle(.secondary)
            if !app.isAuthenticated {
                Text("Connectez-vous depuis Réglages (⌘,)")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}
