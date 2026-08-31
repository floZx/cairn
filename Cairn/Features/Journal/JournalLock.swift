import Foundation
import LocalAuthentication

/// Ce qui sait demander au système que c'est bien vous.
///
/// Un protocole pour une seule vraie implémentation, et c'est assumé :
/// `LAContext` ouvre une boîte de dialogue du système, qu'aucun essai ne peut
/// ni afficher ni renvoyer. Ce qui s'éprouve ici, ce sont les **règles autour**
/// — et l'une d'elles ne doit jamais se tromper, voir `JournalLock`.
@MainActor
protocol AuthentificationLocale {
    /// Si le système est en mesure de poser la question.
    func peutDemander() -> Bool
    /// - Returns: vrai quand c'est bien vous.
    func demander(raison: String) async -> Bool
}

/// Touch ID, avec repli sur le mot de passe de session.
///
/// `.deviceOwnerAuthentication` et non `…WithBiometrics` : sur un Mac sans
/// capteur, ou quand le doigt ne passe pas, le système propose le mot de passe
/// de la session au lieu d'échouer.
///
/// Un `LAContext` neuf à chaque demande : un contexte réutilisé garde son
/// authentification pendant un moment, et « une fois par ouverture de
/// l'application » doit vouloir dire une vraie fois.
@MainActor
struct AuthentificationSysteme: AuthentificationLocale {
    func peutDemander() -> Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func demander(raison: String) async -> Bool {
        (try? await LAContext().evaluatePolicy(
            .deviceOwnerAuthentication, localizedReason: raison
        )) ?? false
    }
}

/// Le verrou du journal : une fois par ouverture de l'application.
///
/// Ce que ce verrou est, et ce qu'il n'est pas. Il empêche un regard par-dessus
/// l'épaule, sur une machine déjà ouverte. Il ne chiffre rien : les notes sont
/// en clair dans la base, le miroir les envoie à Supabase et le téléphone les
/// affiche. Le dire vaut mieux que le laisser croire.
///
/// **La règle qui ne doit jamais se tromper** : quand le système n'est pas en
/// mesure de poser la question — un Mac sans mot de passe de session — le
/// journal s'ouvre. Un verrou qu'on ne peut pas ouvrir n'est pas une sécurité,
/// c'est la perte de ce qu'on a écrit.
@MainActor
@Observable
final class JournalLock {
    private(set) var estOuvert = false
    /// Vrai pendant que la boîte du système est à l'écran, pour ne pas en
    /// ouvrir deux — la vue redemande à chaque apparition.
    private(set) var enCours = false

    private let authentification: any AuthentificationLocale

    init(authentification: any AuthentificationLocale = AuthentificationSysteme()) {
        self.authentification = authentification
    }

    /// Ouvre le journal, en demandant si nécessaire.
    ///
    /// Ne rend rien : ce qu'il y a à savoir est dans `estOuvert`, que la vue
    /// observe. Un refus laisse simplement le journal fermé, avec de quoi
    /// redemander — jamais de message d'erreur pour un geste que l'utilisateur
    /// vient peut-être d'annuler exprès.
    func ouvrir() async {
        guard !estOuvert, !enCours else { return }
        guard authentification.peutDemander() else {
            estOuvert = true
            return
        }
        enCours = true
        let accorde = await authentification.demander(raison: "ouvrir votre journal")
        enCours = false
        if accorde { estOuvert = true }
    }
}
