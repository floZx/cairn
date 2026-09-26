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

/// Au bout de combien de temps ailleurs le journal se referme.
enum JournalLockDelay: Int, CaseIterable, Identifiable, Sendable {
    case immediately = 0
    case oneMinute = 1
    case fiveMinutes = 5
    case tenMinutes = 10
    case thirtyMinutes = 30
    case oneHour = 60
    /// Seulement à l'ouverture de Cairn — le comportement d'avant.
    case atLaunchOnly = -1

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .immediately: "Dès qu'on quitte Cairn"
        case .oneMinute: "Après 1 minute"
        case .fiveMinutes: "Après 5 minutes"
        case .tenMinutes: "Après 10 minutes"
        case .thirtyMinutes: "Après 30 minutes"
        case .oneHour: "Après 1 heure"
        case .atLaunchOnly: "Seulement à l'ouverture de Cairn"
        }
    }
}

/// Le verrou du journal.
///
/// Ce que ce verrou est, et ce qu'il n'est pas. Il empêche un regard par-dessus
/// l'épaule, sur une machine déjà ouverte. Il ne chiffre rien : les notes sont
/// en clair dans la base, le miroir les envoie à Supabase et le téléphone les
/// affiche. Le dire vaut mieux que le laisser croire.
///
/// Il se referme de lui-même, et c'est ce qui lui manquait : demandé une fois
/// par ouverture de l'application, il ne se refermait jamais sur un Mac où
/// Cairn reste ouvert des jours. Désormais : quand l'écran se verrouille ou
/// que le Mac s'endort, et après un moment passé dans une autre application
/// (`delay`). Et à la demande, ⌃⌘L.
///
/// **La règle qui ne doit jamais se tromper** : quand le système n'est pas en
/// mesure de poser la question — un Mac sans mot de passe de session — le
/// journal s'ouvre. Un verrou qu'on ne peut pas ouvrir n'est pas une sécurité,
/// c'est la perte de ce qu'on a écrit.
@MainActor
@Observable
final class JournalLock {
    static let enabledKey = "journalLockEnabled"
    static let delayKey = "journalLockDelay"

    /// Vrai pendant que la boîte du système est à l'écran, pour ne pas en
    /// ouvrir deux — la vue redemande à chaque apparition.
    private(set) var enCours = false

    /// Le journal est lisible : déverrouillé, ou pas de verrou du tout.
    var estOuvert: Bool { !isEnabled || deverrouille }

    /// Réglages > Journal. Désactivé, le journal s'ouvre sans rien demander.
    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }

    var delay: JournalLockDelay {
        didSet { defaults.set(delay.rawValue, forKey: Self.delayKey) }
    }

    /// Appelé juste avant de refermer : la note en cours part dans la base,
    /// pour qu'un verrou ne coûte jamais une phrase.
    var avantDeVerrouiller: (() -> Void)?

    private var deverrouille = false
    private var ailleursDepuis: Date?
    private let authentification: any AuthentificationLocale
    private let defaults: UserDefaults

    init(
        authentification: any AuthentificationLocale = AuthentificationSysteme(),
        defaults: UserDefaults = .standard
    ) {
        self.authentification = authentification
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        if defaults.object(forKey: Self.delayKey) != nil,
           let stored = JournalLockDelay(rawValue: defaults.integer(forKey: Self.delayKey)) {
            delay = stored
        } else {
            delay = .tenMinutes
        }
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
            deverrouille = true
            return
        }
        enCours = true
        let accorde = await authentification.demander(raison: "ouvrir votre journal")
        enCours = false
        if accorde { deverrouille = true }
    }

    /// Referme le journal, après avoir mis la note en cours à l'abri.
    func verrouiller() {
        guard isEnabled, deverrouille else { return }
        avantDeVerrouiller?()
        deverrouille = false
    }

    /// Cairn passe à l'arrière-plan : on note l'heure, ou on referme tout de
    /// suite si c'est le réglage.
    func applicationQuittee(a date: Date = Date()) {
        if delay == .immediately {
            verrouiller()
        } else {
            ailleursDepuis = date
        }
    }

    /// Cairn revient au premier plan : fermé si l'absence a duré.
    func applicationRevenue(a date: Date = Date()) {
        defer { ailleursDepuis = nil }
        guard let depuis = ailleursDepuis, delay != .atLaunchOnly else { return }
        if date.timeIntervalSince(depuis) >= Double(delay.rawValue) * 60 {
            verrouiller()
        }
    }

    /// L'écran se verrouille, le Mac s'endort, la session change : fermé,
    /// quel que soit le délai — sauf pour qui ne veut le verrou qu'au
    /// lancement.
    func ecranVerrouille() {
        guard delay != .atLaunchOnly else { return }
        verrouiller()
    }
}
