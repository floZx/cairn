import SwiftUI

/// The Settings window: one tab per concern.
///
/// Strava holds the Strava credentials and the connection; Garmin holds the
/// Garmin Connect sign-in, the one service Cairn writes to; Synchronisation
/// holds sync state and actions; Cartes holds everything about how maps look
/// and what they store. Track colour and the tile cache used to live in the
/// sync tab, where nobody would look for them. Nutrition holds the food
/// journal's own configuration: macro and weight targets, day types, per-meal
/// shares, catalog status, and the one-shot suivinut import. Journal holds how
/// many notes the base carries, and its lock. Supabase holds the web app's
/// copy: the project, the sign-in, the bootstrap and the journal's encryption
/// — named for the service, as Strava and Garmin are, and placed before
/// Sauvegarde, the copy that stays on the Mac's side.
struct SettingsScene: View {
    var body: some View {
        TabView {
            AccountSettingsView()
                .tabItem { Label("Strava", systemImage: "figure.run") }
            GarminSettingsView()
                .tabItem { Label("Garmin", systemImage: "applewatch") }
            SyncSettingsView()
                .tabItem {
                    Label("Synchronisation", systemImage: "arrow.triangle.2.circlepath")
                }
            MapSettingsView()
                .tabItem { Label("Cartes", systemImage: "map") }
            NutritionSettingsView()
                .tabItem { Label("Nutrition", systemImage: "fork.knife") }
            if !SidebarItem.journal.estMasquee {
                JournalSettingsView()
                    .tabItem { Label("Journal", systemImage: "text.book.closed") }
            }
            MirrorSettingsView()
                .tabItem { Label("Supabase", systemImage: "icloud.and.arrow.up") }
            BackupSettingsView()
                .tabItem { Label("Sauvegarde", systemImage: "externaldrive.badge.icloud") }
        }
        // Assez large pour les huit onglets. À 520, le retour du Journal
        // avait poussé l'onglet du miroir derrière un menu » où il ne s'ouvrait plus
        // — signalé, capture à l'appui. Plus haute aussi : le miroir porte
        // désormais le chiffrement du journal sous l'amorçage.
        .frame(width: 780, height: 540)
    }
}
