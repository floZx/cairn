import CryptoKit
import Foundation
import Testing
@testable import Cairn

@Suite("Journal chiffré : la clé et le chiffre")
struct JournalCipherTests {
    /// Le vecteur que calcule `hashlib.pbkdf2_hmac('sha256', b'correct horse',
    /// b'cairn-sel-essai!', 1000, 32)` — et donc WebCrypto : c'est ce qui
    /// garantit que le téléphone et le Mac tirent la même clé de la même phrase.
    @Test func pbkdf2RendLaMemeCleQuePython() {
        let cle = JournalCipher.deriveKey(
            passphrase: "correct horse", salt: Data("cairn-sel-essai!".utf8), iterations: 1000
        )
        let hex = cle.withUnsafeBytes { $0.map { String(format: "%02x", $0) }.joined() }
        #expect(hex == "9fec9f2576d67fd06e932520b6324e08c21a72ca64289f69f569c82f473d9751")
    }

    @Test func allerRetour() throws {
        let chiffre = JournalCipher(key: SymmetricKey(size: .bits256))
        let texte = "Balade avec @Sam.\n\n#PI — ça a été 😫"
        let scelle = try chiffre.seal(texte)
        #expect(scelle.hasPrefix(JournalCipher.prefix))
        #expect(!scelle.contains("Balade"))
        #expect(try chiffre.open(scelle) == texte)
    }

    @Test func unTexteEnClairPasseTelQuel() throws {
        let chiffre = JournalCipher(key: SymmetricKey(size: .bits256))
        #expect(try chiffre.open("Une note d'avant") == "Une note d'avant")
    }

    @Test func uneAutreCleNOuvreRien() throws {
        let scelle = try JournalCipher(key: SymmetricKey(size: .bits256)).seal("secret")
        #expect(throws: JournalCipherError.openFailed) {
            try JournalCipher(key: SymmetricKey(size: .bits256)).open(scelle)
        }
    }

    @Test func leVerificateurReconnaitLaBonnePhrase() throws {
        let sel = JournalCipher.randomSalt()
        let bonne = JournalCipher(key: JournalCipher.deriveKey(passphrase: "bonne", salt: sel, iterations: 1000))
        let mauvaise = JournalCipher(key: JournalCipher.deriveKey(passphrase: "mauvaise", salt: sel, iterations: 1000))
        let verificateur = try bonne.makeVerifier()
        #expect(bonne.matches(verifier: verificateur))
        #expect(!mauvaise.matches(verifier: verificateur))
    }
}
