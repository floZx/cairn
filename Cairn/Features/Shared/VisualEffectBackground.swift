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
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

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
