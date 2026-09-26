import Testing
import Foundation
@testable import Cairn

/// Le verrou du journal.
///
/// La boîte du système ne s'éprouve pas ; les règles autour, si — et l'une
/// d'elles ne doit jamais se tromper.
@Suite("Le verrou du journal")
@MainActor
struct JournalLockTests {
    /// Une authentification dont on décide la réponse.
    private final class Fausse: AuthentificationLocale {
        var possible: Bool
        var accorde: Bool
        private(set) var demandes = 0

        init(possible: Bool = true, accorde: Bool = true) {
            self.possible = possible
            self.accorde = accorde
        }

        func peutDemander() -> Bool { possible }

        func demander(raison: String) async -> Bool {
            demandes += 1
            return accorde
        }
    }

    private static let suitePrefix = "journal-lock-tests-"

    /// Un domaine de préférences jetable : le verrou lit et écrit les siennes,
    /// et les vraies ne doivent ni décider d'un test ni en garder la trace.
    private func verrou(_ fausse: Fausse, defaults: UserDefaults? = nil) -> JournalLock {
        JournalLock(authentification: fausse, defaults: defaults ?? jetables())
    }

    private func jetables() -> UserDefaults {
        ThrowawayDefaults.sweep(prefix: Self.suitePrefix)
        let defaults = UserDefaults(suiteName: "\(Self.suitePrefix)\(UUID().uuidString)")!
        defaults.removePersistentDomain(forName: defaults.description)
        return defaults
    }

    private func ouvert(_ delai: JournalLockDelay = .tenMinutes) async -> (JournalLock, Fausse) {
        let fausse = Fausse(accorde: true)
        let v = verrou(fausse)
        v.delay = delai
        await v.ouvrir()
        return (v, fausse)
    }

    @Test("fermé au lancement")
    func fermeAuDepart() {
        #expect(!verrou(Fausse()).estOuvert)
    }

    @Test("une authentification accordée ouvre le journal")
    func accordeOuvre() async {
        let verrou = verrou(Fausse(accorde: true))
        await verrou.ouvrir()
        #expect(verrou.estOuvert)
    }

    @Test("un refus laisse le journal fermé")
    func refusLaisseFerme() async {
        let verrou = verrou(Fausse(accorde: false))
        await verrou.ouvrir()
        #expect(!verrou.estOuvert)
    }

    /// **La règle qui ne doit jamais se tromper.** Sur une machine où le
    /// système ne peut pas poser la question — pas de mot de passe de session —
    /// le journal s'ouvre. Un verrou qu'on ne peut pas ouvrir n'est pas une
    /// sécurité, c'est la perte de ce qu'on a écrit.
    @Test("sans moyen de demander, le journal s'ouvre")
    func sansMoyenDeDemanderOuvre() async {
        let fausse = Fausse(possible: false, accorde: false)
        let verrou = verrou(fausse)
        await verrou.ouvrir()
        #expect(verrou.estOuvert)
        #expect(fausse.demandes == 0)
    }

    /// Une fois par ouverture de l'application, pas une fois par affichage :
    /// la vue redemande à chaque apparition.
    @Test("une seule demande, même en redemandant")
    func uneSeuleDemande() async {
        let fausse = Fausse(accorde: true)
        let verrou = verrou(fausse)
        await verrou.ouvrir()
        await verrou.ouvrir()
        await verrou.ouvrir()
        #expect(fausse.demandes == 1)
    }

    /// Un refus doit pouvoir se rejouer : c'est le bouton « Déverrouiller ».
    @Test("après un refus, on peut redemander")
    func onPeutRedemanderApresUnRefus() async {
        let fausse = Fausse(accorde: false)
        let verrou = verrou(fausse)
        await verrou.ouvrir()
        fausse.accorde = true
        await verrou.ouvrir()
        #expect(verrou.estOuvert)
        #expect(fausse.demandes == 2)
    }

    @Test("après dix minutes ailleurs, il se referme ; après cinq, non")
    func seRefermeApresLeDelai() async {
        let (v, _) = await ouvert(.tenMinutes)
        let depart = Date()
        v.applicationQuittee(a: depart)
        v.applicationRevenue(a: depart.addingTimeInterval(5 * 60))
        #expect(v.estOuvert)
        v.applicationQuittee(a: depart)
        v.applicationRevenue(a: depart.addingTimeInterval(10 * 60))
        #expect(!v.estOuvert)
    }

    @Test("« dès qu'on quitte Cairn » referme tout de suite")
    func immediatement() async {
        let (v, _) = await ouvert(.immediately)
        v.applicationQuittee()
        #expect(!v.estOuvert)
    }

    @Test("l'écran qui se verrouille referme le journal, sauf réglage « au lancement »")
    func ecran() async {
        let (v, _) = await ouvert(.oneHour)
        v.ecranVerrouille()
        #expect(!v.estOuvert)

        let (auLancement, _) = await ouvert(.atLaunchOnly)
        auLancement.ecranVerrouille()
        auLancement.applicationQuittee(a: Date())
        auLancement.applicationRevenue(a: Date().addingTimeInterval(24 * 3600))
        #expect(auLancement.estOuvert)
    }

    @Test("la note en cours est mise à l'abri avant de fermer")
    func sauveAvantDeFermer() async {
        let (v, _) = await ouvert()
        var sauvee = false
        v.avantDeVerrouiller = { sauvee = true }
        v.verrouiller()
        #expect(sauvee)
        #expect(!v.estOuvert)
    }

    @Test("sans verrou, le journal est ouvert sans rien demander")
    func desactive() async {
        let defaults = jetables()
        let fausse = Fausse(accorde: false)
        let v = verrou(fausse, defaults: defaults)
        v.isEnabled = false
        #expect(v.estOuvert)
        v.verrouiller()
        #expect(v.estOuvert)
        // Et le choix tient d'un lancement à l'autre.
        #expect(!verrou(fausse, defaults: defaults).isEnabled)
    }

    @Test("rouvrir après un verrouillage redemande")
    func redemandeApresVerrouillage() async {
        let (v, fausse) = await ouvert()
        v.verrouiller()
        await v.ouvrir()
        #expect(v.estOuvert)
        #expect(fausse.demandes == 2)
    }
}
