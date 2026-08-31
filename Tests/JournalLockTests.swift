import Testing
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

    @Test("fermé au lancement")
    func fermeAuDepart() {
        #expect(!JournalLock(authentification: Fausse()).estOuvert)
    }

    @Test("une authentification accordée ouvre le journal")
    func accordeOuvre() async {
        let verrou = JournalLock(authentification: Fausse(accorde: true))
        await verrou.ouvrir()
        #expect(verrou.estOuvert)
    }

    @Test("un refus laisse le journal fermé")
    func refusLaisseFerme() async {
        let verrou = JournalLock(authentification: Fausse(accorde: false))
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
        let verrou = JournalLock(authentification: fausse)
        await verrou.ouvrir()
        #expect(verrou.estOuvert)
        #expect(fausse.demandes == 0)
    }

    /// Une fois par ouverture de l'application, pas une fois par affichage :
    /// la vue redemande à chaque apparition.
    @Test("une seule demande, même en redemandant")
    func uneSeuleDemande() async {
        let fausse = Fausse(accorde: true)
        let verrou = JournalLock(authentification: fausse)
        await verrou.ouvrir()
        await verrou.ouvrir()
        await verrou.ouvrir()
        #expect(fausse.demandes == 1)
    }

    /// Un refus doit pouvoir se rejouer : c'est le bouton « Déverrouiller ».
    @Test("après un refus, on peut redemander")
    func onPeutRedemanderApresUnRefus() async {
        let fausse = Fausse(accorde: false)
        let verrou = JournalLock(authentification: fausse)
        await verrou.ouvrir()
        fausse.accorde = true
        await verrou.ouvrir()
        #expect(verrou.estOuvert)
        #expect(fausse.demandes == 2)
    }
}
