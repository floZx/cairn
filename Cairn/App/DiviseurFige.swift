import AppKit
import ObjectiveC

/// Fige le diviseur entre la liste et le volet de droite : ni glissé, ni
/// curseur de redimensionnement.
///
/// Une bande transparente posée par-dessus a été essayée d'abord : elle ne
/// recevait rien — le diviseur garde la main sur ses clics et son curseur —,
/// et le diviseur se tirait toujours. Signalé.
///
/// AppKit a pourtant un moyen prévu pour ça : le délégué du split view rend
/// la zone « efficace » d'un diviseur, celle qui prend la souris, et une zone
/// vide n'en prend aucune. Mais ce délégué est le `NSSplitViewController`
/// privé de SwiftUI, qu'on ne peut ni remplacer — AppKit le refuse — ni
/// sous-classer. On lui greffe donc, à lui seul, une sous-classe faite à
/// l'exécution, à la façon de KVO : elle répond pour le diviseur 1 quand il
/// est figé, et rend la main à la classe d'origine pour tout le reste.
///
/// Rien de tout cela n'est contractuel ; si la greffe échoue, le diviseur
/// reste simplement mobile, comme avant.
@MainActor
enum DiviseurFige {
    /// Les split views dont le diviseur 1 est figé.
    private static var figes: Set<ObjectIdentifier> = []

    private static let selecteur = #selector(
        NSSplitViewDelegate.splitView(_:effectiveRect:forDrawnRect:ofDividerAt:)
    )

    static func figer(_ fige: Bool, splitView: NSSplitView) {
        let cle = ObjectIdentifier(splitView)
        guard fige != figes.contains(cle) else { return }
        if fige { figes.insert(cle) } else { figes.remove(cle) }
        if fige, let delegate = splitView.delegate as? NSSplitViewController {
            greffer(delegate)
        }
        // Les zones du curseur se recalculent : sans ceci, la flèche de
        // redimensionnement restait jusqu'au prochain redimensionnement.
        splitView.window?.invalidateCursorRects(for: splitView)
        splitView.resetCursorRects()
    }

    private static let suffixe = "_CairnDiviseurFige"

    private static func greffer(_ controleur: NSSplitViewController) {
        guard let origine: AnyClass = object_getClass(controleur) else { return }
        let nomOrigine = NSStringFromClass(origine)
        guard !nomOrigine.hasSuffix(suffixe) else { return }
        let nom = nomOrigine + suffixe

        let classe: AnyClass
        if let deja = NSClassFromString(nom) {
            classe = deja
        } else {
            guard let nouvelle = objc_allocateClassPair(origine, nom, 0) else { return }
            typealias Original = @convention(c) (
                AnyObject, Selector, NSSplitView, NSRect, NSRect, Int
            ) -> NSRect
            // La classe d'origine répond-elle déjà ? Alors on l'appelle pour
            // tout ce qui n'est pas figé ; sinon, la zone proposée par AppKit.
            let original: Original? = class_respondsToSelector(origine, selecteur)
                ? unsafeBitCast(class_getMethodImplementation(origine, selecteur), to: Original.self)
                : nil
            let sel = selecteur
            let bloc: @convention(block) (AnyObject, NSSplitView, NSRect, NSRect, Int) -> NSRect = {
                moi, splitView, proposee, dessinee, index in
                let fige = MainActor.assumeIsolated {
                    index == 1 && figes.contains(ObjectIdentifier(splitView))
                }
                if fige { return .zero }
                return original?(moi, sel, splitView, proposee, dessinee, index) ?? proposee
            }
            let types = "{CGRect={CGPoint=dd}{CGSize=dd}}@:@{CGRect={CGPoint=dd}{CGSize=dd}}{CGRect={CGPoint=dd}{CGSize=dd}}q"
            class_addMethod(nouvelle, selecteur, imp_implementationWithBlock(bloc), types)
            // Comme KVO : la classe se dit toujours celle d'origine, pour qui
            // la compare — SwiftUI le premier.
            let classeOrigine: @convention(block) (AnyObject) -> AnyClass = { _ in origine }
            class_addMethod(
                nouvelle, NSSelectorFromString("class"),
                imp_implementationWithBlock(classeOrigine), "#@:"
            )
            objc_registerClassPair(nouvelle)
            classe = nouvelle
        }
        object_setClass(controleur, classe)
    }
}
