import Testing
import Foundation
import SwiftData
@testable import Cairn

@Suite("Outbox du miroir")
@MainActor
struct MirrorOutboxTests {
    /// Ce test décide l'architecture de la tâche : si `ModelContext.willSave`
    /// donne bien ce qui a changé, l'outbox se remplit depuis un seul endroit.
    /// S'il échoue, appliquer le repli décrit en tête de tâche.
    @Test func uneEcritureLaisseUneTraceDansLOutbox() throws {
        let container = try AppModelContainer.inMemory()
        let recorder = MirrorRecorder(container: container)
        recorder.start()
        defer { recorder.stop() }

        let context = ModelContext(container)
        let entry = WeightEntry(dateKey: DateKey(raw: "2026-08-16")!, weightKg: 70)
        context.insert(entry)
        try context.save()

        let pending = try context.fetch(FetchDescriptor<MirrorOutbox>())
        #expect(pending.contains { $0.rowUUID == entry.uuid && $0.table == "weight_entry" })
    }

    /// Une suppression laisse une trace qui survit à l'objet. Sans elle, une
    /// ligne effacée sur le Mac resterait indéfiniment dans le miroir.
    @Test func uneSuppressionLaisseUneTraceQuiSurvitALObjet() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let entry = WeightEntry(dateKey: DateKey(raw: "2026-08-16")!, weightKg: 70)
        let uuid = entry.uuid
        context.insert(entry)
        try context.save()

        let recorder = MirrorRecorder(container: container)
        recorder.start()
        defer { recorder.stop() }

        context.delete(entry)
        try context.save()

        let pending = try context.fetch(FetchDescriptor<MirrorOutbox>())
        #expect(pending.contains { $0.rowUUID == uuid && $0.isDeletion })
    }

    /// L'outbox ne s'enregistre pas elle-même. Sans cette garde, écrire une
    /// entrée déclencherait la notification qui en écrirait une autre.
    @Test func lOutboxNeSEnregistrePasElleMeme() throws {
        let container = try AppModelContainer.inMemory()
        let recorder = MirrorRecorder(container: container)
        recorder.start()
        defer { recorder.stop() }

        let context = ModelContext(container)
        context.insert(WeightEntry(dateKey: DateKey(raw: "2026-08-16")!, weightKg: 70))
        try context.save()

        let pending = try context.fetch(FetchDescriptor<MirrorOutbox>())
        #expect(pending.allSatisfy { $0.table != "mirror_outbox" })
        #expect(pending.count == 1)
    }

    /// Une modification compte autant qu'une création : c'est le cas le plus
    /// courant dans l'usage réel — une note ajoutée, un nom de sortie corrigé
    /// — et celui qu'un `changedAt` posé à la main aurait le plus de chances
    /// d'oublier.
    @Test func uneModificationLaisseAussiUneTrace() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let entry = WeightEntry(dateKey: DateKey(raw: "2026-08-16")!, weightKg: 70)
        context.insert(entry)
        try context.save()

        let recorder = MirrorRecorder(container: container)
        recorder.start()
        defer { recorder.stop() }

        entry.weightKg = 71
        try context.save()

        let pending = try context.fetch(FetchDescriptor<MirrorOutbox>())
        #expect(pending.count == 1)
        #expect(pending.first?.rowUUID == entry.uuid)
        #expect(pending.first?.isDeletion == false)
    }

    /// Un enregistreur n'écoute que son propre magasin. C'est ce qui permet à
    /// un observateur global de `NotificationCenter` de cohabiter avec une
    /// suite dont des centaines de tests écrivent chacun dans le leur.
    @Test func lEnregistreurIgnoreLesAutresMagasins() throws {
        let observed = try AppModelContainer.inMemory()
        let other = try AppModelContainer.inMemory()
        let recorder = MirrorRecorder(container: observed)
        recorder.start()
        defer { recorder.stop() }

        let otherContext = ModelContext(other)
        otherContext.insert(WeightEntry(dateKey: DateKey(raw: "2026-08-16")!, weightKg: 70))
        try otherContext.save()

        #expect(try otherContext.fetch(FetchDescriptor<MirrorOutbox>()).isEmpty)
        #expect(try ModelContext(observed).fetch(FetchDescriptor<MirrorOutbox>()).isEmpty)
    }

    /// Après `stop()`, plus rien ne s'enregistre — et `stop()` supporte d'être
    /// appelé deux fois, ce dont les `defer` des tests ci-dessus dépendent.
    @Test func apresStopPlusRienNeSEnregistre() throws {
        let container = try AppModelContainer.inMemory()
        let recorder = MirrorRecorder(container: container)
        recorder.start()
        recorder.stop()
        recorder.stop()

        let context = ModelContext(container)
        context.insert(WeightEntry(dateKey: DateKey(raw: "2026-08-16")!, weightKg: 70))
        try context.save()

        #expect(try context.fetch(FetchDescriptor<MirrorOutbox>()).isEmpty)
    }

    /// Deux `start()` ne font pas deux abonnements : sans la garde, chaque
    /// sauvegarde laisserait deux entrées identiques.
    @Test func deuxDemarragesNAbonnentQuUneFois() throws {
        let container = try AppModelContainer.inMemory()
        let recorder = MirrorRecorder(container: container)
        recorder.start()
        recorder.start()
        defer { recorder.stop() }

        let context = ModelContext(container)
        context.insert(WeightEntry(dateKey: DateKey(raw: "2026-08-16")!, weightKg: 70))
        try context.save()

        #expect(try context.fetch(FetchDescriptor<MirrorOutbox>()).count == 1)
    }

    /// Une sauvegarde qui touche plusieurs modèles laisse une trace par ligne,
    /// chacune sous le nom de table que `MirrorRow` donne déjà — c'est ce
    /// groupement par table que la tâche 9 rejouera.
    @Test func plusieursModelesLaissentUneTraceChacun() throws {
        let container = try AppModelContainer.inMemory()
        let recorder = MirrorRecorder(container: container)
        recorder.start()
        defer { recorder.stop() }

        let context = ModelContext(container)
        let activity = Activity(stravaID: 1, name: "Sortie", sportType: .run)
        let weight = WeightEntry(dateKey: DateKey(raw: "2026-08-16")!, weightKg: 70)
        context.insert(activity)
        context.insert(weight)
        try context.save()

        let pending = try context.fetch(FetchDescriptor<MirrorOutbox>())
        #expect(Set(pending.map(\.table)) == ["activity", "weight_entry"])
        #expect(Set(pending.map(\.rowUUID)) == [activity.uuid, weight.uuid])
    }

    /// `SyncState` décrit la relation avec Strava et ne traverse pas : il ne
    /// conforme pas `MirrorRow`, donc l'écrire ne doit rien laisser. Le même
    /// filtre protège l'outbox d'elle-même.
    @Test func unModeleQuiNeTraversePasNeLaisseRien() throws {
        let container = try AppModelContainer.inMemory()
        let recorder = MirrorRecorder(container: container)
        recorder.start()
        defer { recorder.stop() }

        let context = ModelContext(container)
        context.insert(SyncState())
        try context.save()

        #expect(try context.fetch(FetchDescriptor<MirrorOutbox>()).isEmpty)
    }

    /// Une suppression en cascade laisse une pierre tombale par ligne, la
    /// fille comprise. C'est la question que le mécanisme aurait pu perdre en
    /// silence : si SwiftData ne propageait la cascade qu'après le `willSave`,
    /// les `RecipeItem` d'une recette effacée resteraient dans le miroir sans
    /// que rien ne les mentionne plus jamais. Il la propage avant.
    @Test func uneSuppressionEnCascadeLaisseUneTraceParLigne() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let recipe = Recipe(name: "Porridge")
        let item = RecipeItem(
            foodName: "Flocons d'avoine", kcal100: 389, protein100: 13, carbs100: 66,
            fat100: 7, grams: 80
        )
        item.recipe = recipe
        context.insert(recipe)
        context.insert(item)
        try context.save()

        let recipeUUID = recipe.uuid
        let itemUUID = item.uuid

        let recorder = MirrorRecorder(container: container)
        recorder.start()
        defer { recorder.stop() }

        context.delete(recipe)
        try context.save()

        let pending = try context.fetch(FetchDescriptor<MirrorOutbox>())
        #expect(pending.contains { $0.rowUUID == recipeUUID && $0.table == "recipe" && $0.isDeletion })
        #expect(pending.contains { $0.rowUUID == itemUUID && $0.table == "recipe_item" && $0.isDeletion })
    }

    /// L'outbox est un modèle local : elle ne conforme pas `MirrorRow`, donc
    /// aucune table `mirror_outbox` n'a à exister dans `supabase/schema.sql`.
    /// `Tests/MirrorRowSchemaTests.swift` tiendrait le raisonnement inverse —
    /// ici on l'énonce dans l'autre sens.
    @Test func lOutboxNeConformePasMirrorRow() {
        #expect(!(MirrorOutbox(table: "weight_entry", rowUUID: "u", isDeletion: false) is any MirrorRow))
    }
}
