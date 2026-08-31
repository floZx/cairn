import SwiftUI

/// Ce qui s'affiche à la place du journal tant qu'il est fermé.
///
/// La demande part toute seule en arrivant : cliquer « Journal » est déjà le
/// geste par lequel on demande à l'ouvrir, et faire cliquer une seconde fois
/// serait une porte de plus devant la porte. Le bouton est là pour après —
/// après un refus, une annulation, un doigt qui n'a pas pris.
struct JournalLockView: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        ContentUnavailableView {
            Label("Journal verrouillé", systemImage: "lock")
        } description: {
            Text("Une fois par ouverture de Cairn, pour que ce qui est écrit là reste à vous.")
        } actions: {
            Button("Déverrouiller") {
                Task { await app.journalLock.ouvrir() }
            }
            .disabled(app.journalLock.enCours)
        }
        .task { await app.journalLock.ouvrir() }
    }
}
