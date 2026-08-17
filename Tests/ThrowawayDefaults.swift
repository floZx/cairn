import Foundation

/// Le balai des suites `UserDefaults` jetables.
///
/// Une suite jetable — `UserDefaults(suiteName: "…-\(UUID())")` — laisse un
/// fichier `~/Library/Preferences/<nom>.plist` derrière elle, un par test et
/// par exécution. `removePersistentDomain(forName:)` vide le domaine et ne
/// touche pas au fichier : des milliers s'y étaient accumulés avant d'être
/// retirés à la main. Le bundle de test tourne dans l'application hôte, qui
/// n'est pas en bac à sable (`Cairn.entitlements`), donc c'est bien ce
/// dossier-là qui se remplit.
///
/// Retirer le fichier de la suite qu'on vient de vider ne suffit pas, et
/// c'est mesuré : `cfprefsd` écrit quand il veut, et un `removeItem` lancé
/// avant qu'il l'ait fait supprime un fichier qui n'existe pas encore — le
/// démon l'écrit ensuite derrière nous. Sur la suite complète, neuf fichiers
/// sur douze survivaient ainsi à un retrait pourtant précédé d'un
/// `synchronize()`.
///
/// D'où un balai plutôt qu'un retrait : chaque test efface **tous** les
/// fichiers portant le préfixe de sa suite, donc ceux que le démon a fini
/// d'écrire pour les tests précédents, de cette exécution comme des
/// précédentes. Ce qui reste au sol est borné — au pire le dernier fichier
/// d'une exécution, ramassé par la suivante — au lieu de croître sans fin.
enum ThrowawayDefaults {
    static func sweep(prefix: String) {
        let folder = URL.homeDirectory.appending(path: "Library/Preferences")
        let names =
            (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names where name.hasPrefix(prefix) && name.hasSuffix(".plist") {
            try? FileManager.default.removeItem(at: folder.appending(path: name))
        }
    }
}
