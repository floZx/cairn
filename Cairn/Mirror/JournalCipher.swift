import CommonCrypto
import CryptoKit
import Foundation

/// Le chiffrement des notes du journal sur leur chemin vers Supabase.
///
/// De bout en bout : le Mac chiffre avant d'envoyer et déchiffre en tirant, le
/// téléphone fait de même, et Supabase ne tient plus qu'un texte illisible. La
/// base locale, elle, reste en clair — FileVault la protège déjà, et la
/// recherche, les citations et l'export Markdown ont besoin du texte.
///
/// La clé vient d'une phrase secrète, par PBKDF2-SHA256 et un sel propre au
/// compte, rangé à côté dans la table `journal_crypto`. Le chiffre est
/// AES-256-GCM. Les deux existent tels quels dans WebCrypto : l'application
/// web refait exactement ce calcul, et c'est ce qui fixe ces choix plutôt que
/// d'autres.
///
/// **Le texte chiffré va dans la même colonne `text`, précédé de `prefix`.**
/// Une colonne à part aurait laissé `text` vide, et un client qui ne connaît
/// pas le chiffrement — une vieille version ouverte par Spotlight, un onglet
/// resté sur l'ancienne application web — aurait lu une note vide et pu
/// l'appliquer : une note effacée. Avec le préfixe, il lit du charabia, qui
/// se voit et ne détruit rien.
struct JournalCipher: Sendable {
    /// Ce qui ouvre un texte chiffré.
    static let prefix = "cairn-chiffre:v1:"
    /// Le texte que chiffre le vérificateur, pour reconnaître la bonne phrase
    /// sans rien déchiffrer du journal.
    private static let verifierText = "cairn-journal"
    /// L'ordre de grandeur que recommande l'OWASP pour PBKDF2-SHA256 : un
    /// tiers de seconde sur le Mac, une fois par appareil.
    static let defaultIterations = 600_000

    let key: SymmetricKey

    init(key: SymmetricKey) { self.key = key }

    init(keyData: Data) { self.key = SymmetricKey(data: keyData) }

    var keyData: Data { key.withUnsafeBytes { Data($0) } }

    /// La clé tirée d'une phrase, par PBKDF2-HMAC-SHA256, sur 32 octets.
    static func deriveKey(passphrase: String, salt: Data, iterations: Int) -> SymmetricKey {
        let motDePasse = Array(passphrase.utf8)
        var derivee = [UInt8](repeating: 0, count: 32)
        let statut = salt.withUnsafeBytes { selOctets in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                motDePasse.map { Int8(bitPattern: $0) }, motDePasse.count,
                selOctets.bindMemory(to: UInt8.self).baseAddress, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                UInt32(iterations),
                &derivee, derivee.count
            )
        }
        precondition(statut == kCCSuccess, "PBKDF2 a échoué : \(statut)")
        return SymmetricKey(data: derivee)
    }

    static func randomSalt() -> Data {
        Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
    }

    static func isSealed(_ text: String) -> Bool { text.hasPrefix(prefix) }

    /// `prefix` puis, en base64, le nonce, le texte chiffré et l'étiquette —
    /// l'ordre de `AES.GCM.SealedBox.combined`, et celui qu'attend WebCrypto
    /// une fois le nonce détaché.
    func seal(_ text: String) throws -> String {
        let boite = try AES.GCM.seal(Data(text.utf8), using: key)
        guard let combine = boite.combined else { throw JournalCipherError.sealFailed }
        return Self.prefix + combine.base64EncodedString()
    }

    /// Le texte en clair. Un texte sans préfixe est rendu tel quel : c'est une
    /// note d'avant le chiffrement, ou écrite par un client qui l'ignore.
    func open(_ text: String) throws -> String {
        guard Self.isSealed(text) else { return text }
        guard let octets = Data(base64Encoded: String(text.dropFirst(Self.prefix.count))),
              let boite = try? AES.GCM.SealedBox(combined: octets),
              let clair = try? AES.GCM.open(boite, using: key),
              let texte = String(data: clair, encoding: .utf8)
        else { throw JournalCipherError.openFailed }
        return texte
    }

    func makeVerifier() throws -> String { try seal(Self.verifierText) }

    /// Si cette clé est celle qui a produit ce vérificateur — la bonne phrase.
    func matches(verifier: String) -> Bool {
        (try? open(verifier)) == Self.verifierText
    }
}

enum JournalCipherError: LocalizedError, Equatable {
    case sealFailed
    case openFailed
    case wrongPassphrase

    var errorDescription: String? {
        switch self {
        case .sealFailed: "Une note n'a pas pu être chiffrée."
        case .openFailed: "Une note du miroir n'a pas pu être déchiffrée."
        case .wrongPassphrase: "Cette phrase secrète ne correspond pas à celle du journal."
        }
    }
}

/// Ce que Supabase garde du chiffrement : de quoi refaire la clé à partir de
/// la phrase, et reconnaître la bonne. Rien qui permette de lire une note.
struct JournalCryptoConfig: Codable, Equatable, Sendable {
    var salt: String
    var iterations: Int
    var verifier: String

    var saltData: Data? { Data(base64Encoded: salt) }
}

/// La clé gardée dans le trousseau de ce Mac, avec le sel dont elle vient :
/// une clé tirée d'un autre sel ne vaut plus rien si le journal a été
/// rechiffré ailleurs.
struct JournalKey: Codable, Equatable, Sendable {
    var keyData: Data
    var salt: String
}
