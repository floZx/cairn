import SwiftUI
import AppKit

/// A slab of system material, for the surfaces SwiftUI leaves flat.
///
/// `NavigationSplitView`'s sidebar column arrives with no `NSVisualEffectView`
/// of its own — verified in the live view tree — so the pane draws as one more
/// rectangle of window grey, the same shade as the list and the detail beside
/// it. Every other macOS app blends something behind its sidebar, and that
/// blending is the whole reason a sidebar reads as a surface of its own rather
/// than a column painted on the window.
///
/// `SwiftUI`'s own `.background(.ultraThinMaterial)` cannot do this job: its
/// materials blend what is *inside* the window, and inside the window there is
/// nothing behind a sidebar. Only `behindWindow` blending reaches the desktop.
struct VisualEffectBackground: View {
    var material: NSVisualEffectView.Material = .sidebar
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    /// How much of the window's own colour is laid over the material.
    ///
    /// `windowBackgroundColor` rather than a fixed grey, so the veil is pale
    /// over a light theme and dark over a dark one without being told.
    ///
    /// Note what this cannot do. `behindWindow` blending samples *everything*
    /// behind the window, and other applications' windows are part of
    /// everything: a browser under the bottom edge showed as a white band, a
    /// window under the middle as a violet cast. A veil dilutes that, it does
    /// not decide what is sampled — the surfaces that must not show it use
    /// `.opaque` below instead.
    var veil: Double = 0

    var body: some View {
        Material(material: material, blending: blending)
            .overlay(Color(nsColor: .windowBackgroundColor).opacity(veil))
    }

    /// A content surface: the window's own colour, and nothing sampled.
    ///
    /// What macOS itself does, and for this reason. A translucent sidebar is
    /// chrome and reads as a pane floating over the desktop; a translucent
    /// *document* reads as whatever happens to be behind the window, which on a
    /// normal desktop is other applications. The list and the detail pane are
    /// documents.
    ///
    /// A view rather than the window's own opacity: the sidebar still blends,
    /// so the window has to stay non-opaque, and every surface that must not
    /// show through therefore has to paint itself.
    static var opaque: some View {
        Color(nsColor: .windowBackgroundColor)
    }
}

/// The slab itself. Kept apart so the veil above can sit on top of it in
/// SwiftUI, where a colour is one modifier rather than a second subview to
/// place and resize by hand.
private struct Material: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = TransparencyClaimingEffectView()
        view.material = material
        view.blendingMode = blending
        // Follows the window rather than staying `.active`: a sidebar still
        // glowing under a window the user has clicked away from is the one
        // thing that reads as a bug rather than as depth.
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

/// Opens the window up so `behindWindow` blending has something to sample.
///
/// A material alone changed nothing, and the reason was one flag: the window
/// arrives opaque with a solid background painted under everything, so the
/// blend read that grey instead of the desktop. Asking for it here, from the
/// view that needs it, rather than at the window's creation: the window is
/// SwiftUI's to build, and this is the only place that knows the effect is
/// wanted at all.
private final class TransparencyClaimingEffectView: NSVisualEffectView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard blendingMode == .behindWindow, let window else { return }
        window.isOpaque = false
        // Clear, not merely translucent: any colour left here is a wash the
        // material would blend on top of the desktop.
        window.backgroundColor = .clear
    }
}
