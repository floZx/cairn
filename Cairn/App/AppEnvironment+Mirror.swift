import AppKit
import Foundation
import SwiftData

// The Supabase mirror, as the app drives it: configuring, signing in,
// bootstrapping, and the automatic passes.
extension AppEnvironment {
    // MARK: - Mirror

    /// Whether a Supabase project is on file — decided purely from the
    /// keychain, never the network. Gates the settings screen's sign-in and
    /// bootstrap controls, and is what `Tests/MirrorAutonomyTests.swift`
    /// (task 11) checks stays `false`, never throws, when nothing is
    /// configured.
    var isMirrorConfigured: Bool { store.mirrorCredentials() != nil }

    /// Whether a session is on file — `MirrorClient.isSignedIn`'s
    /// synchronous counterpart, read the same way `isMirrorConfigured` is:
    /// straight from the keychain, so a settings screen can gate its
    /// buttons without an `await`.
    ///
    /// Expiry is deliberately not consulted here; `MirrorClient.isSignedIn`
    /// carries the measurement that says why.
    var isMirrorSignedIn: Bool {
        store.mirrorSession() != nil
    }

    /// Records the project the mirror writes to — the settings screen's
    /// « Enregistrer les identifiants » button.
    ///
    /// Changing the URL wipes the bootstrap cursor and the session, exactly as
    /// `forgetMirror()` does, and for the same reason its own doc comment
    /// gives: the cursor records progress against *one* project, and the field
    /// holding the URL is editable at all times. Without this, pointing the
    /// Mac at a second Supabase project — new URL, sign in again, « Lancer
    /// l'amorçage » — would silently skip every row whose `uuid` sorts before
    /// the old project's cursor, on a project that has never seen any of them.
    /// The session goes too: it was issued by the old project's GoTrue and
    /// means nothing to the new one.
    func saveMirrorCredentials(projectURL: String, anonKey: String) {
        let trimmedURL = projectURL.trimmingCharacters(in: .whitespaces)
        let trimmedKey = anonKey.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmedURL), !trimmedURL.isEmpty else {
            mirrorErrorMessage = "L'URL du projet est invalide."
            return
        }
        guard !trimmedKey.isEmpty else {
            mirrorErrorMessage = "La clé anon ne peut pas être vide."
            return
        }
        // Read before the save, or there is nothing left to compare against.
        // `nil` — no project on file yet — counts as different: a cursor
        // surviving a crash mid-`forgetMirror()` would otherwise still be
        // read against a project that has never received a row, and nobody
        // can hold a session for a project they have not configured.
        let previousURL = store.mirrorCredentials()?.projectURL
        do {
            try store.save(MirrorCredentials(projectURL: url, anonKey: trimmedKey))
            if previousURL != url {
                mirrorCursor.clear()
                try? store.clearMirrorSession()
                mirrorProgress.phase = .idle
                mirrorProgress.lastPushAt = nil
                mirrorProgress.failedUploads = 0
            }
            mirrorErrorMessage = nil
            // Configuring the project is exactly the moment `MirrorRecorder`
            // is meant to start — see its own "When to start it" doc comment,
            // and the identical guard in `init` above for a Mac that already
            // had credentials on launch. `start()` is a no-op if it is
            // already running, so this is safe to call again after an edit.
            mirrorRecorder.start()
        } catch {
            mirrorErrorMessage =
                "Impossible d'enregistrer les identifiants : \(error.localizedDescription)"
        }
    }

    func signInMirror(email: String, password: String) async {
        do {
            try await mirrorClient.signIn(email: email, password: password)
            mirrorErrorMessage = nil
        } catch {
            mirrorErrorMessage = error.localizedDescription
        }
    }

    /// Drops the project, the session, and every trace of them from the
    /// settings screen — the « Oublier ce miroir » button. Never touches a
    /// single local model: the mirror is a copy, and forgetting it must not
    /// cost the user any data.
    ///
    /// Clears `mirrorCursor` along with the keychain, not just the keychain:
    /// the outbox is left alone (its entries only ever name `table + uuid`,
    /// which stay correct against any project), but the bootstrap cursor
    /// records progress against *this* project specifically. Left in place,
    /// reconfiguring a *different* Supabase project afterward would silently
    /// skip every row sorting before the old cursor — see
    /// `MirrorBootstrapCursor.clear()`'s own doc comment.
    ///
    /// La clé du journal part aussi : elle ouvre les notes de ce projet-là, et
    /// un miroir oublié n'a plus à laisser sur ce Mac de quoi les déchiffrer.
    /// Reconfigurer le même projet redemandera la phrase.
    func forgetMirror() {
        cancelMirror()
        mirrorRecorder.stop()
        try? store.clearMirror()
        try? store.clearJournalKey()
        journalEncryption = .unknown
        mirrorCursor.clear()
        mirrorProgress.phase = .idle
        mirrorProgress.lastPushAt = nil
        mirrorProgress.failedUploads = 0
        mirrorErrorMessage = nil
    }

    /// Uploads the whole library once, resuming wherever a previous attempt
    /// left off — the settings screen's « Lancer l'amorçage » button.
    func startBootstrap() {
        runMirror { [mirror] in try await mirror.bootstrap() }
    }

    /// Les quatre objectifs nutritionnels, lus dans `defaults` — jamais dans
    /// `UserDefaults.standard` en dur : c'est l'instance que cet environnement
    /// a reçue, et un test qui en injecte une jetable doit rester jetable.
    ///
    /// `double(forKey:)` répond `0` pour une clé absente, ce qui n'est pas la
    /// valeur par défaut voulue : les quatre sont donc lues par `object(forKey:)`
    /// avant de retomber sur celles de `NutritionSettings`, la même précaution
    /// que `syncsOnLaunch` prend juste au-dessus.
    var nutritionTargets: MirrorEngine.NutritionTargets {
        func lire(_ key: String, _ defaut: Double) -> Double {
            defaults.object(forKey: key) as? Double ?? defaut
        }
        return MirrorEngine.NutritionTargets(
            proteinG: lire(
                NutritionSettings.proteinTargetKey,
                NutritionSettings.defaultProteinTargetG
            ),
            fatG: lire(
                NutritionSettings.fatTargetKey, NutritionSettings.defaultFatTargetG
            ),
            fiberG: lire(
                NutritionSettings.fiberTargetKey,
                NutritionSettings.defaultFiberTargetG
            ),
            weightGoalKg: lire(
                NutritionSettings.weightGoalKey, NutritionSettings.defaultWeightGoalKg
            )
        )
    }

    /// The full round trip: read what was written elsewhere, then send what
    /// was written here.
    ///
    /// Read first, and the order is load-bearing in one direction only. Both
    /// sequences converge — a note edited on both sides is arbitrated by
    /// `edited_at` either way — but reading first means the store already
    /// holds the web's version when the push looks at the outbox, so the two
    /// never cross on the wire. Pushing first would send the Mac's copy, then
    /// immediately pull the web's back over it: the same end state, one
    /// wasted request, and a moment where the wrong text was in Supabase.
    ///
    /// A failed pull does not stop the push. The two carry different data in
    /// different directions, and a network that refused the read has no say
    /// over whether three days of local edits get to leave.
    func syncMirrorNow() {
        runMirror { [mirror, journal, mirrorProgress, targets = nutritionTargets] in
            var echecDeLecture: Error?
            do {
                // Le journal ne se relit pas tout seul : il tient sa liste en
                // mémoire et ne la reconstruit que sur ses propres écritures.
                // Une note venue du téléphone est bien dans la base sans être
                // à l'écran, et n'y serait qu'au lancement suivant.
                if try await mirror.pull() > 0 {
                    await MainActor.run {
                        // Les images d'abord : `refresh` reconstruit la liste
                        // des notes, et une note dont l'image n'est pas encore
                        // sur le disque s'afficherait avec un cadre vide.
                        journal.rebuildAttachments()
                        journal.refresh()
                    }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                echecDeLecture = error
            }
            try await mirror.push(nutritionTargets: targets)
            // La poussée vient de reposer `.idle` en finissant proprement, et
            // sans cette ligne l'échec de la lecture disparaîtrait derrière
            // elle sans un mot. Une première version se contentait d'un
            // `catch {}` : une lecture qui échouait à chaque lancement était
            // rigoureusement indiscernable d'une lecture qui n'avait rien à
            // faire.
            if let echecDeLecture {
                await MainActor.run {
                    mirrorProgress.phase = .failed(echecDeLecture.localizedDescription)
                }
            }
        }
    }

    /// Runs one mirror operation with the same shape `runSync` gives Strava,
    /// and for the same reason: `MirrorEngine.bootstrap()` and `.push()` are
    /// actors, but they suspend at every request, so two calls left
    /// unguarded — an automatic push racing a hand-started bootstrap, say —
    /// would interleave freely instead of running one after the other.
    /// Harmless today (both are idempotent) but doubled traffic all the same,
    /// and worth ruling out here rather than trusting every future caller to
    /// remember it.
    ///
    /// Unlike `runSync`, nothing here sets `errorMessage`: `MirrorEngine`
    /// already records its own outcome straight into `mirrorProgress.phase`
    /// (`.failed(message)` on failure, back to `.idle` on a clean finish or a
    /// deliberate cancellation), which is the one place the settings screen
    /// already reads from. A second, separate error channel here would just
    /// be two sources of truth for the same fact.
    func runMirror(_ operation: @escaping @Sendable () async throws -> Void) {
        guard mirrorTask == nil else { return }
        let task = Task {
            do { try await operation() } catch {}
        }
        mirrorTask = task
        Task {
            _ = await task.value
            if mirrorTask == task { mirrorTask = nil }
        }
    }

    /// Cancellation is cooperative, exactly as `cancelSync` explains: the slot
    /// can only be released by the task itself once it has actually unwound,
    /// so clearing it here would let a second bootstrap or push start
    /// alongside the one still dying.
    func cancelMirror() {
        guard let task = mirrorTask else { return }
        task.cancel()
        Task { _ = await task.value }
    }

    // MARK: - Relève automatique

    /// Relève le miroir à intervalle régulier, tant que l'application vit.
    ///
    /// C'est la réponse à un défaut que Florian a signalé le 18 août 2026 :
    /// une note écrite sur le téléphone n'arrivait sur le Mac qu'au lancement
    /// suivant, la seule lecture étant celle de `pushMirrorOnLaunch`. Relancer
    /// l'application pour lire son propre journal n'est pas un usage.
    ///
    /// La boucle tourne sans se soucier des réglages, et c'est délibéré :
    /// c'est au moment de partir qu'on regarde si le miroir est configuré et
    /// la session ouverte. Redémarrer la boucle à chaque changement de réglage
    /// demanderait de les observer ; deux conditions relues toutes les cinq
    /// minutes coûtent moins qu'un observateur de plus.
    ///
    /// Rien ici ne s'inquiète d'un recouvrement : `runMirror` garde un seul
    /// créneau et rend la main tout de suite s'il est pris. Un tic qui tombe
    /// pendant un amorçage est un tic sauté, ce qui est le bon comportement.
    func startMirrorPolling() {
        mirrorPollTask?.cancel()
        mirrorPollTask = Task { [weak self] in
            while !Task.isCancelled {
                // Le sommeil d'abord : le lancement vient de pousser, et une
                // relève immédiate ne ferait que doubler la précédente.
                try? await Task.sleep(for: Self.mirrorPollInterval)
                guard !Task.isCancelled, let self else { return }
                self.syncMirrorAutomatically()
            }
        }
        observeActivation()
    }

    /// Relève le miroir en revenant au Mac.
    ///
    /// C'est le moment même où l'on vient voir ce qui a été écrit ailleurs, et
    /// attendre le prochain quart de tour serait exactement ce qu'on cherche à
    /// éviter. L'observateur ne capture pas `self` fortement : l'application
    /// vit aussi longtemps que lui, mais un cycle de rétention n'a jamais
    /// arrangé personne.
    func observeActivation() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: nil,
        ) { [weak self] _ in
            // Par une tâche du grand acteur plutôt qu'en supposant l'isolement
            // depuis la file principale : la notification arrive sur le fil
            // qui la publie, et l'ordonnancer est plus honnête que l'affirmer.
            Task { @MainActor in self?.syncMirrorAutomatically() }
        }
    }

    /// Une relève que personne n'a demandée : elle ne part que si le miroir a
    /// de quoi parler, et jamais dans la foulée d'une autre.
    func syncMirrorAutomatically() {
        guard isMirrorConfigured, isMirrorSignedIn else { return }
        if let derniere = lastAutomaticMirrorSync,
           Date().timeIntervalSince(derniere) < Self.mirrorPollFloor {
            return
        }
        lastAutomaticMirrorSync = Date()
        syncMirrorNow()
    }

    /// Sends whatever the outbox has accumulated since the last successful
    /// push, once per launch.
    ///
    /// Nothing else calls `syncMirrorNow()` but the settings button, and a mirror
    /// nobody ever opens the settings for would keep a trail that only ever
    /// grows: `MirrorRecorder`'s own doc comment justifies its conditional
    /// start by "a recorder started at launch would grow the store by one
    /// row per write, indefinitely" — a bound only an actual push can hold,
    /// never the fact that a project happens to be configured.
    ///
    /// Before Strava's own launch sync and independent of it: the mirror has
    /// nothing to do with `syncsOnLaunch` or with being signed in to Strava.
    /// Gated on the mirror's own two conditions instead, exactly as the
    /// settings button is — `push()` on an unconfigured Mac would throw
    /// `.notConfigured` and leave « Échec : Aucun projet Supabase… » on a
    /// screen belonging to a feature its owner never asked for.
    func pushMirrorOnLaunch() {
        guard isMirrorConfigured, isMirrorSignedIn else { return }
        syncMirrorNow()
    }
}
