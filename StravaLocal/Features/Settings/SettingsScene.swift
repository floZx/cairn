import SwiftUI

/// The Settings window: one tab per concern.
///
/// Account holds the Strava credentials and the connection; Synchronisation
/// holds sync state and actions; Cartes holds everything about how maps look
/// and what they store. Track colour and the tile cache used to live in the
/// sync tab, where nobody would look for them.
struct SettingsScene: View {
    var body: some View {
        TabView {
            AccountSettingsView()
                .tabItem { Label("Compte", systemImage: "person.crop.circle") }
            SyncSettingsView()
                .tabItem {
                    Label("Synchronisation", systemImage: "arrow.triangle.2.circlepath")
                }
            MapSettingsView()
                .tabItem { Label("Cartes", systemImage: "map") }
        }
        .frame(width: 520, height: 380)
    }
}
