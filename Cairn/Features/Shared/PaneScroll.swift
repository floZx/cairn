import SwiftUI
import SwiftData

/// Le sens dans lequel le clavier fait défiler le volet : 1 vers le bas, -1
/// vers le haut, 0 à l'arrêt.
struct PaneScrollRequest: Equatable {
    var direction = 0
}

/// Le défilement du volet au clavier, image par image.
///
/// Continu et non par crans : une animation relancée à chaque répétition de la
/// touche partait de la position mesurée, encore en plein mouvement, et le
/// volet sautait par à-coups — « pas fluide », signalé. Ici la position suivie
/// est la nôtre, avancée à chaque image d'une vitesse qui monte en quelques
/// dixièmes de seconde, et le volet s'arrête net au relâchement — comme un
/// défilement au trackpad.
///
/// Une pression brève, qui n'aurait presque rien parcouru, finit en glissant
/// jusqu'à la longueur d'un tap : un tap doit faire avancer quelque chose.
@MainActor
final class PaneScroller {
    private var timer: Timer?
    private var direction = 0
    private var position: CGFloat = 0
    private var origin: CGFloat = 0
    private var maximum: CGFloat = 0
    private var startedAt = Date()
    private var lastTick = Date()
    private var apply: ((CGFloat) -> Void)?
    /// After a short press: the glide to the tap's end, run by this same
    /// timer. It used to be a SwiftUI animation, and a press made while one
    /// was still running fought it for the position — the pane jumped back
    /// 23 pt before going on, measured with a probe on 26 September.
    private var settle: (from: CGFloat, to: CGFloat, at: Date)?

    /// Points par seconde au départ, et au bout de la montée.
    private static let initialSpeed: CGFloat = 700
    private static let topSpeed: CGFloat = 1800
    private static let rampSeconds: CGFloat = 0.35
    /// Un tap parcourt au moins ça.
    private static let tapDistance: CGFloat = 120
    private static let settleSeconds: Double = 0.18
    /// No step longer than a frame's worth: the first tick could come 40 ms
    /// after the key, and the pane leapt 28 pt at once.
    private static let longestStep: CGFloat = 1.0 / 60

    /// Starts, or carries on from where a motion still running has got to:
    /// the pane's reported offset lags the timer by a frame or two, and
    /// restarting from it went backwards.
    func start(
        direction: Int, from offset: CGFloat, maximum: CGFloat,
        apply: @escaping @MainActor (CGFloat) -> Void
    ) {
        let running = timer != nil
        timer?.invalidate()
        timer = nil
        settle = nil
        self.apply = apply
        self.direction = direction
        self.maximum = maximum
        position = running ? clamp(position) : clamp(offset)
        origin = position
        startedAt = Date()
        lastTick = startedAt
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// A long press stops where it is; a short one glides on to a tap's
    /// length, so a tap always moves something.
    func stop() {
        guard timer != nil, settle == nil else { return }
        if abs(position - origin) < Self.tapDistance {
            let target = clamp(origin + CGFloat(direction) * Self.tapDistance)
            settle = (position, target, Date())
        } else {
            cancel()
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        settle = nil
    }

    private func tick() {
        let now = Date()
        if let settle {
            let t = min(1, now.timeIntervalSince(settle.at) / Self.settleSeconds)
            // Ease-out: fast at first, carrying the press's speed, then soft.
            let eased = 1 - pow(1 - t, 3)
            position = settle.from + (settle.to - settle.from) * CGFloat(eased)
            apply?(position)
            if t >= 1 { cancel() }
            return
        }
        let dt = min(CGFloat(now.timeIntervalSince(lastTick)), Self.longestStep)
        lastTick = now
        let elapsed = CGFloat(now.timeIntervalSince(startedAt))
        let ramp = min(1, elapsed / Self.rampSeconds)
        let speed = Self.initialSpeed + (Self.topSpeed - Self.initialSpeed) * ramp
        let next = clamp(position + CGFloat(direction) * speed * dt)
        guard next != position else { return }
        position = next
        apply?(next)
    }

    private func clamp(_ y: CGFloat) -> CGFloat {
        min(max(y, 0), maximum)
    }
}

/// The pane's scroll view, with the keyboard scrolling that drives it.
///
/// Apart from the pane on purpose: everything that changes while scrolling —
/// the position, the geometry, the key scroller — is state of this view, so a
/// frame of scrolling redraws this and not the content, which was built once
/// by the pane and is only handed over.
struct PaneScrollView<Content: View>: View {
    /// Another activity opens at the top of its pane, not where the last one
    /// was left.
    let resetKey: AnyHashable
    let request: PaneScrollRequest
    /// Trop étroite pour son contenu, la page défile aussi de côté au lieu
    /// d'être rognée des deux bords. Les statistiques, serrées par le volet
    /// d'une sortie ouverte depuis un record, devenaient illisibles.
    var scrollsSidewaysWhenNarrow = false
    @ViewBuilder let content: Content

    @State private var position = ScrollPosition()
    /// Written on every frame and read only when a key goes down: in a box,
    /// so writing it redraws nothing.
    @State private var geometry = GeometryBox()
    @State private var scroller = PaneScroller()
    @State private var containerWidth: CGFloat = 0

    @MainActor
    final class GeometryBox {
        var value = PaneScrollGeometry()
    }

    var body: some View {
        ScrollView(scrollsSidewaysWhenNarrow ? [.vertical, .horizontal] : .vertical) {
            if scrollsSidewaysWhenNarrow {
                AtLeastItsNarrowest(width: containerWidth) { content }
            } else {
                content
            }
        }
        .scrollPosition($position)
        // De côté seulement s'il y a de quoi : une page qui tient dans sa
        // largeur n'a pas à rebondir sous le trackpad.
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.width } action: { _, new in
            containerWidth = new
        }
        // In the coordinates `scrollTo(y:)` takes, which start below the
        // toolbar: the content offset starts above it, 51 pt higher. Handed
        // the raw offset, `J` began every press by jumping back those 51 pt
        // — the bounce each tap made, measured with a probe on 26 September.
        .onScrollGeometryChange(for: PaneScrollGeometry.self) { g in
            PaneScrollGeometry(
                offset: g.contentOffset.y + g.contentInsets.top,
                sideways: g.contentOffset.x + g.contentInsets.leading,
                maximum: max(
                    0,
                    g.contentSize.height + g.contentInsets.top + g.contentInsets.bottom
                        - g.containerSize.height
                )
            )
        } action: { _, new in
            geometry.value = new
        }
        .onChange(of: request.direction) { _, direction in
            if direction == 0 {
                scroller.stop()
            } else {
                scroller.start(
                    direction: direction,
                    from: geometry.value.offset,
                    maximum: geometry.value.maximum
                ) { [geometry] y in
                    // Le point entier : la page peut avoir défilé de côté, et
                    // `j` n'a pas à la ramener au bord gauche.
                    position.scrollTo(point: CGPoint(x: geometry.value.sideways, y: y))
                }
            }
        }
        .onChange(of: resetKey) { _, _ in
            scroller.cancel()
            position.scrollTo(edge: .top)
        }
        .onDisappear { scroller.cancel() }
    }
}

/// Où en est le défilement du volet, et jusqu'où il peut aller.
struct PaneScrollGeometry: Equatable {
    var offset: CGFloat = 0
    var sideways: CGFloat = 0
    var maximum: CGFloat = 0
}


/// Propose à son contenu la largeur de la page, ou la plus étroite qu'il
/// puisse tenir si la page est plus étroite encore.
///
/// Dans une vue qui défile de côté, la largeur proposée est libre, et chaque
/// texte s'y étalerait sur une seule ligne. Mesurée plutôt que fixée : la plus
/// petite largeur est celle que le contenu rend à une proposition nulle — ses
/// textes repliés au mot, ses rangées de chiffres côte à côte — et elle suit
/// ce que les cartes deviennent.
private struct AtLeastItsNarrowest: Layout {
    let width: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        return subview.sizeThatFits(ProposedViewSize(width: resolvedWidth(subview), height: nil))
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        guard let subview = subviews.first else { return }
        subview.place(
            at: bounds.origin, anchor: .topLeading,
            proposal: ProposedViewSize(width: resolvedWidth(subview), height: nil)
        )
    }

    private func resolvedWidth(_ subview: LayoutSubview) -> CGFloat {
        max(width, subview.sizeThatFits(ProposedViewSize(width: 0, height: nil)).width)
    }
}
