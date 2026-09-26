import Foundation

/// Ce que devient le texte d'une note en passant par le miroir.
enum JournalSealing: Sendable {
    /// Pas de chiffrement côté Supabase : le texte passe en clair, comme avant.
    case plain
    /// Chiffré, et la clé est sur ce Mac.
    case sealed(JournalCipher)
    /// Chiffré, sans la clé ici : les notes ne partent ni n'arrivent.
    case locked
}

extension MirrorEngine {
    /// L'état du chiffrement, demandé à Supabase une fois par passe.
    ///
    /// Une table `journal_crypto` absente — le script SQL pas encore passé —
    /// vaut « en clair » : c'est l'état d'avant, rien ne doit s'arrêter.
    func journalSealing() async throws -> JournalSealing {
        if let journalSealingCache { return journalSealingCache }
        let config: JournalCryptoConfig?
        do {
            config = try await client.fetchJournalCrypto()
        } catch MirrorError.http(status: 404, _) {
            config = nil
        }
        let resolved: JournalSealing
        if let config {
            if let key = await client.journalKey, key.salt == config.salt,
               JournalCipher(keyData: key.keyData).matches(verifier: config.verifier) {
                resolved = .sealed(JournalCipher(keyData: key.keyData))
            } else {
                resolved = .locked
            }
        } else {
            resolved = .plain
        }
        journalSealingCache = resolved
        return resolved
    }

    /// Chiffre le texte d'une ligne de `journal_note` si le journal l'est.
    ///
    /// Les étiquettes partent vides : tirées du texte, elles en diraient une
    /// part en clair. Le téléphone les retrouve en déchiffrant.
    ///
    /// Un état pas encore lu est une erreur, jamais un envoi en clair : c'est
    /// le seul sens dans lequel se tromper ne coûte rien.
    func sealIfJournal(_ row: inout [String: MirrorValue], table: String) throws {
        guard table == "journal_note" else { return }
        switch journalSealingCache {
        case .plain:
            return
        case let .sealed(cipher):
            guard case let .string(text)? = row["text"] else { return }
            row["text"] = .string(try cipher.seal(text))
            row["tags_raw"] = .stringArray([])
        case .locked, nil:
            throw JournalCipherError.sealFailed
        }
    }

    /// Le texte en clair d'une note tirée du miroir.
    func openJournalText(_ text: String) throws -> String {
        guard JournalCipher.isSealed(text) else { return text }
        guard case let .sealed(cipher)? = journalSealingCache else {
            throw JournalCipherError.openFailed
        }
        return try cipher.open(text)
    }

    /// Rechiffre toutes les notes vers Supabase — au moment où le chiffrement
    /// est activé, pour que les lignes en clair y soient remplacées.
    ///
    /// Tire d'abord : une note écrite sur le téléphone et pas encore descendue
    /// serait sinon écrasée par la version plus ancienne du Mac.
    func resealJournal() async throws {
        guard let userID = await client.userID else { throw MirrorError.notConfigured }
        try await pull()
        journalSealingCache = nil
        guard case .sealed = try await journalSealing() else {
            throw JournalCipherError.wrongPassphrase
        }
        cursor.resetTable("journal_note")
        try await sendTable("journal_note", userID: userID)
        await finish()
    }
}
