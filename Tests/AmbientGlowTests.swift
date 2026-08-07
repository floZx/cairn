import Testing
import SwiftUI
@testable import Cairn

@Suite("Diffusion de couleur")
@MainActor
struct AmbientGlowTests {
    @Test("le mode sombre reçoit une teinte plus marquée que le mode clair")
    func darkModeGetsMore() {
        // The same alpha that is barely visible over white turns muddy over
        // near-black, where a colour has nothing to lighten. Two values chosen
        // on purpose rather than one that happens to suit one of the two.
        #expect(
            AmbientGlow.opacity(for: .dark) > AmbientGlow.opacity(for: .light)
        )
    }

    @Test("la teinte reste une ambiance, jamais un aplat")
    func staysAWash() {
        // Past roughly a third, the wash stops reading as light on a surface and
        // starts reading as a coloured box behind the content — which is the one
        // thing this must not become.
        for scheme in [ColorScheme.light, .dark] {
            let opacity = AmbientGlow.opacity(for: scheme)
            #expect(opacity > 0)
            #expect(opacity <= 0.35)
        }
    }
}
