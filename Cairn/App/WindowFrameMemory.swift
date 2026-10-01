import SwiftUI

/// Rouvre la fenêtre là où on l'a laissée, écran compris, tant que cet écran
/// est encore branché.
///
/// SwiftUI range déjà le cadre de la fenêtre, mais de travers. Mesuré le
/// 1er octobre 2026 :
///
/// - Le cadre rangé était sur le PL2409HD, et la fenêtre se rouvrait à la même
///   taille sur l'écran intégré : à la relecture, AppKit la ramène sur l'écran
///   où elle vient de naître. `setFrame(from:)` fait de même.
/// - Il le range sous un nom tiré du type de la vue racine, que chaque `.task`
///   ajouté dans `CairnApp` change : la fenêtre repartait de zéro.
/// - Et un `setFrameAutosaveName` à nous ne tient pas : SwiftUI repose le sien
///   par-dessus dans les secondes qui suivent.
///
/// D'où un cadre rangé à la main, sous une clé à nous, à chaque déplacement,
/// et reposé tel quel — `setFrame(_:display:)` ne recale rien — à l'ouverture.
/// Un écran débranché depuis : on laisse faire SwiftUI, qui ouvre sur l'écran
/// intégré, et le cadre rangé attend que l'écran revienne.
struct WindowFrameMemory: NSViewRepresentable {
    static let key = "fenetrePrincipale.cadre"

    func makeNSView(context: Context) -> NSView { WindowProbe() }

    func updateNSView(_ nsView: NSView, context: Context) {}

    fileprivate static func restore(_ window: NSWindow) {
        guard let saved = UserDefaults.standard.string(forKey: key) else { return }
        let frame = NSRectFromString(saved)
        guard frame.width > 0, frame.height > 0, isOnAConnectedScreen(frame) else { return }
        window.setFrame(frame, display: false)
    }

    fileprivate static func save(_ window: NSWindow) {
        // Plein écran : ce cadre-là n'est pas celui qu'on veut retrouver.
        guard !window.styleMask.contains(.fullScreen) else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: key)
    }

    /// Assez de la barre de titre sur un écran branché pour qu'on puisse la
    /// saisir.
    private static func isOnAConnectedScreen(_ frame: NSRect) -> Bool {
        let titleBar = NSRect(x: frame.minX, y: frame.maxY - 28, width: frame.width, height: 28)
        return NSScreen.screens.contains { screen in
            let overlap = screen.visibleFrame.intersection(titleBar)
            return overlap.width >= 100 && overlap.height >= 10
        }
    }
}

/// Une vue vide qui rend le cadre à sa fenêtre et le range quand il change.
private final class WindowProbe: NSView {
    private var observers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        guard let window else { return }
        WindowFrameMemory.restore(window)
        // Après la restauration, pour ne pas ranger le cadre de naissance.
        observers = [NSWindow.didMoveNotification, NSWindow.didResizeNotification].map {
            NotificationCenter.default.addObserver(forName: $0, object: window, queue: .main) {
                [weak window] _ in
                guard let window else { return }
                MainActor.assumeIsolated { WindowFrameMemory.save(window) }
            }
        }
    }
}
