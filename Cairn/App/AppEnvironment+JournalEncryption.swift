import Foundation

extension AppEnvironment {
    // MARK: - Chiffrement du journal

    /// Relit l'état du chiffrement : la table, la clé de ce Mac.
    func refreshJournalEncryption() async {
        guard isMirrorConfigured, isMirrorSignedIn else {
            journalEncryption = .unknown
            return
        }
        do {
            guard let config = try await mirrorClient.fetchJournalCrypto() else {
                journalEncryption = .plain
                return
            }
            let key = await mirrorClient.journalKey
            let ouvre = key.map {
                $0.salt == config.salt
                    && JournalCipher(keyData: $0.keyData).matches(verifier: config.verifier)
            } ?? false
            journalEncryption = ouvre ? .sealed : .locked
        } catch MirrorError.http(status: 404, _) {
            journalEncryption = .unavailable
        } catch {
            journalEncryption = .unknown
        }
    }

    /// Chiffre le journal avec cette phrase, ou l'ouvre sur ce Mac s'il
    /// l'est déjà. Rend un message d'erreur, ou `nil`.
    ///
    /// La première fois, toutes les notes repartent chiffrées vers Supabase,
    /// par-dessus leur version en clair. Les fois suivantes — un autre Mac, un
    /// trousseau effacé — la phrase est vérifiée, la clé rangée, et les notes
    /// retenues en attendant partent avec la synchronisation suivante.
    func setJournalPassphrase(_ phrase: String) async -> String? {
        guard mirrorTask == nil else { return "Une synchronisation est en cours ; réessayez dans un instant." }
        do {
            guard let userID = await mirrorClient.userID else { return "Connectez d'abord le miroir." }
            let existante = try await mirrorClient.fetchJournalCrypto()
            let config: JournalCryptoConfig
            let premiere: Bool
            if let existante {
                guard let sel = existante.saltData else { return "La configuration du chiffrement est illisible." }
                let cle = JournalCipher.deriveKey(passphrase: phrase, salt: sel, iterations: existante.iterations)
                guard JournalCipher(key: cle).matches(verifier: existante.verifier) else {
                    return JournalCipherError.wrongPassphrase.errorDescription
                }
                config = existante
                premiere = false
            } else {
                let sel = JournalCipher.randomSalt()
                let iterations = JournalCipher.defaultIterations
                let cle = JournalCipher.deriveKey(passphrase: phrase, salt: sel, iterations: iterations)
                config = JournalCryptoConfig(
                    salt: sel.base64EncodedString(), iterations: iterations,
                    verifier: try JournalCipher(key: cle).makeVerifier()
                )
                premiere = true
            }
            let cle = JournalCipher.deriveKey(
                passphrase: phrase, salt: config.saltData!, iterations: config.iterations
            )
            // La clé d'abord, la configuration ensuite : dans l'autre ordre, un
            // échec entre les deux laisserait Supabase exiger une clé que ce Mac
            // n'aurait pas, et le journal cesserait de partir.
            try await mirrorClient.saveJournalKey(
                JournalKey(keyData: JournalCipher(key: cle).keyData, salt: config.salt)
            )
            if premiere {
                try await mirrorClient.createJournalCrypto(config, userID: userID)
                try await mirror.resealJournal()
            } else {
                syncMirrorNow()
            }
            await refreshJournalEncryption()
            return nil
        } catch MirrorError.http(status: 404, _) {
            return "La table journal_crypto n'existe pas encore : passez d'abord le script SQL."
        } catch {
            return error.localizedDescription
        }
    }
}
