import Testing
import SwiftData
import Foundation
@testable import Cairn

/// Insère deux lignes d'un même modèle portant le même `uuid` — ce qu'une
/// migration légère laisse derrière elle — et rend de quoi relire les deux
/// identités après la passe, sans que l'appelant ait à retenir le type.
///
/// Le chemin de clé est passé explicitement parce que `MirrorRow.uuid` est en
/// lecture seule : c'est `StoreMaintenance` qui écrit, et le protocole n'a pas
/// à s'ouvrir pour un test. La contrainte `MirrorRow` reste, elle, ce qui
/// garantit que la liste ci-dessous ne parle que des modèles qui traversent.
@MainActor
private func seedPair<Model: PersistentModel & MirrorRow>(
    _ uuid: ReferenceWritableKeyPath<Model, String>,
    _ first: Model, _ second: Model,
    sharing shared: String, into context: ModelContext
) -> (table: String, uuids: () -> Set<String>) {
    first[keyPath: uuid] = shared
    second[keyPath: uuid] = shared
    context.insert(first)
    context.insert(second)
    return (Model.mirrorTable, { Set([first.uuid, second.uuid]) })
}

/// La même chose, pour un modèle qui ne traverse pas le miroir — `JournalNote`
/// et `JournalAttachment` ne conforment pas `MirrorRow`, ce que
/// `Tests/MirrorIdentityTests.swift` fige à seize. `StoreMaintenance` répare
/// leur identité tout de même : un défaut SwiftData ne sait pas qu'un modèle
/// reste local. Le libellé est fourni par l'appelant plutôt que lu sur
/// `MirrorRow.mirrorTable`, qui n'existe pas ici — au site d'appel, c'est
/// `Schema.entityName(for:)` qui le fournit, pas un nom inventé à la main.
@MainActor
private func seedLocalPair<Model: PersistentModel>(
    _ label: String,
    _ uuid: ReferenceWritableKeyPath<Model, String>,
    _ first: Model, _ second: Model,
    sharing shared: String, into context: ModelContext
) -> (table: String, uuids: () -> Set<String>) {
    first[keyPath: uuid] = shared
    second[keyPath: uuid] = shared
    context.insert(first)
    context.insert(second)
    return (label, { Set([first[keyPath: uuid], second[keyPath: uuid]]) })
}

@Suite("Maintenance du store")
@MainActor
struct StoreMaintenanceTests {
    @Test("les uuid vides sont complétés, les autres laissés intacts")
    func fillsEmptyUUIDs() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let untouched = Activity(stravaID: 1, name: "Déjà en ordre", sportType: .run)
        let kept = untouched.uuid
        let empty = Activity(stravaID: 2, name: "Sans identité", sportType: .run)
        empty.uuid = ""
        context.insert(untouched)
        context.insert(empty)
        try context.save()

        let changed = try StoreMaintenance.run(context)

        #expect(changed == 1)
        #expect(untouched.uuid == kept)
        #expect(empty.uuid.isEmpty == false)
    }

    @Test("trois lignes partageant un uuid ressortent avec trois uuid distincts")
    func splitsDuplicatedUUIDs() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        // The shape actually measured in the user's store: a lightweight
        // migration applying one default to every existing row.
        let shared = "64D8A062-4BAC-4EAF-BB62-5803626D04E5"
        let one = Activity(stravaID: 1, name: "Une", sportType: .run)
        let two = Activity(stravaID: 2, name: "Deux", sportType: .run)
        let three = Activity(stravaID: 3, name: "Trois", sportType: .run)
        one.uuid = shared
        two.uuid = shared
        three.uuid = shared
        context.insert(one)
        context.insert(two)
        context.insert(three)
        try context.save()

        let changed = try StoreMaintenance.run(context)

        #expect(changed == 2)
        let uuids = Set([one.uuid, two.uuid, three.uuid])
        #expect(uuids.count == 3)
    }

    /// Les seize modèles qui traversent, pas seulement `Activity` : le `uuid`
    /// est arrivé sur quinze autres avec le miroir, et rien ne les répare
    /// qu'ici. Une boucle plutôt que seize tests : ce qui compte est justement
    /// qu'aucun ne manque à l'appel, et un modèle oublié se lit mieux dans une
    /// liste que dans un fichier de seize fonctions jumelles.
    ///
    /// `JournalNote` et `JournalAttachment`, qui ne conforment pas
    /// `MirrorRow`, ont leur propre test juste en dessous plutôt que de
    /// rejoindre `pairs` ici : mélanger les deux aurait rendu l'égalité avec
    /// `MirrorEngine.bootstrapOrder` fausse, et le nom de ce test menteur.
    /// La garantie que rien de ce qui porte un `uuid` n'échappe à la
    /// réparation, mirrorée ou non, est portée plus loin encore par
    /// `everySchemaEntityCarryingAUUIDIsRepaired`, qui lit le schéma au lieu
    /// d'énumérer des modèles à la main.
    ///
    /// La forme reproduite est celle qu'une migration légère laisse : deux
    /// lignes d'une même table portant la même valeur. Le compte attendu est
    /// exactement un réémis par paire — le premier revendiquant garde le sien.
    @Test("chacun des seize modèles ressort avec des uuid distincts")
    func splitsDuplicatedUUIDsForEveryMirroredModel() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let shared = "64D8A062-4BAC-4EAF-BB62-5803626D04E5"
        let day = DateKey(raw: "2026-08-16")!

        let pairs = [
            seedPair(
                \Activity.uuid,
                Activity(stravaID: 1, name: "Une", sportType: .run),
                Activity(stravaID: 2, name: "Deux", sportType: .run),
                sharing: shared, into: context
            ),
            seedPair(
                \ActivityStreams.uuid, ActivityStreams(), ActivityStreams(),
                sharing: shared, into: context
            ),
            seedPair(
                \ActivityPhoto.uuid, ActivityPhoto(uniqueID: "p1"), ActivityPhoto(uniqueID: "p2"),
                sharing: shared, into: context
            ),
            seedPair(
                \Lap.uuid, Lap(stravaID: 1, lapIndex: 0), Lap(stravaID: 2, lapIndex: 1),
                sharing: shared, into: context
            ),
            seedPair(
                \Gear.uuid, Gear(stravaID: "b1", name: "Vélo"),
                Gear(stravaID: "b2", name: "Chaussures"),
                sharing: shared, into: context
            ),
            seedPair(
                \Athlete.uuid, Athlete(stravaID: 1), Athlete(stravaID: 2),
                sharing: shared, into: context
            ),
            seedPair(
                \DiscardedActivity.uuid, DiscardedActivity(stravaID: 1, name: "Annulée"),
                DiscardedActivity(stravaID: 2, name: "Annulée aussi"),
                sharing: shared, into: context
            ),
            seedPair(
                \DayType.uuid, DayType(name: "Repos", kcalTarget: 2000),
                DayType(name: "Sortie", kcalTarget: 3000),
                sharing: shared, into: context
            ),
            seedPair(
                \MealSlot.uuid, MealSlot(name: "Petit-déj"), MealSlot(name: "Dîner"),
                sharing: shared, into: context
            ),
            seedPair(
                \NutritionDay.uuid, NutritionDay(dateKey: day),
                NutritionDay(dateKey: DateKey(raw: "2026-08-17")!),
                sharing: shared, into: context
            ),
            seedPair(
                \FoodEntry.uuid,
                FoodEntry(
                    dateKey: day, mealSlot: nil, foodName: "Pomme",
                    kcal100: 52, protein100: 0.3, carbs100: 14, fat100: 0.2, grams: 150
                ),
                FoodEntry(
                    dateKey: day, mealSlot: nil, foodName: "Poire",
                    kcal100: 57, protein100: 0.4, carbs100: 15, fat100: 0.1, grams: 160
                ),
                sharing: shared, into: context
            ),
            seedPair(
                \MealNote.uuid, MealNote(dateKey: day, mealSlot: nil, note: "Bon appétit"),
                MealNote(dateKey: day, mealSlot: nil, note: "Resservi"),
                sharing: shared, into: context
            ),
            seedPair(
                \Recipe.uuid, Recipe(name: "Porridge"), Recipe(name: "Soupe"),
                sharing: shared, into: context
            ),
            seedPair(
                \RecipeItem.uuid,
                RecipeItem(
                    foodName: "Flocons d'avoine", kcal100: 389, protein100: 13,
                    carbs100: 66, fat100: 7, grams: 80
                ),
                RecipeItem(
                    foodName: "Lait", kcal100: 46, protein100: 3.2,
                    carbs100: 4.8, fat100: 1.6, grams: 200
                ),
                sharing: shared, into: context
            ),
            seedPair(
                \FavoriteFood.uuid,
                FavoriteFood(
                    foodName: "Banane", kcal100: 89, protein100: 1.1,
                    carbs100: 23, fat100: 0.3, grams: 120
                ),
                FavoriteFood(
                    foodName: "Amandes", kcal100: 579, protein100: 21,
                    carbs100: 22, fat100: 50, grams: 30
                ),
                sharing: shared, into: context
            ),
            seedPair(
                \WeightEntry.uuid, WeightEntry(dateKey: day, weightKg: 70),
                WeightEntry(dateKey: DateKey(raw: "2026-08-17")!, weightKg: 71),
                sharing: shared, into: context
            ),
        ]
        #expect(Set(pairs.map(\.table)) == Set(MirrorEngine.bootstrapOrder))
        try context.save()

        let changed = try StoreMaintenance.run(context)

        #expect(changed == pairs.count)
        for pair in pairs {
            let uuids = pair.uuids()
            #expect(uuids.count == 2, "\(pair.table) : les deux lignes partagent encore un uuid")
            #expect(uuids.allSatisfy { !$0.isEmpty }, "\(pair.table) : un uuid vide")
        }

        // La même passe, relancée : plus rien à réparer sur aucune des seize.
        #expect(try StoreMaintenance.run(context) == 0)
    }

    /// Les deux modèles du journal, à part : ils portent un `uuid` sujet au
    /// même défaut SwiftData que les seize mirrorés, mais ne conforment pas
    /// `MirrorRow` (`Tests/MirrorIdentityTests.swift` fige leur nombre à
    /// seize), donc ils ne peuvent pas rejoindre `pairs` ci-dessus sans
    /// fausser sa comparaison à `MirrorEngine.bootstrapOrder`.
    @Test("les deux modèles locaux du journal ressortent avec des uuid distincts")
    func splitsDuplicatedUUIDsForLocalJournalModels() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let shared = "64D8A062-4BAC-4EAF-BB62-5803626D04E5"
        let day = DateKey(raw: "2026-08-16")!

        let pairs = [
            seedLocalPair(
                Schema.entityName(for: JournalNote.self), \JournalNote.uuid,
                JournalNote(dateKey: day, text: "Une"),
                JournalNote(dateKey: DateKey(raw: "2026-08-17")!, text: "Deux"),
                sharing: shared, into: context
            ),
            seedLocalPair(
                Schema.entityName(for: JournalAttachment.self), \JournalAttachment.uuid,
                JournalAttachment(fileName: "un.jpg", data: Data([0x01])),
                JournalAttachment(fileName: "deux.jpg", data: Data([0x02])),
                sharing: shared, into: context
            ),
        ]
        try context.save()

        let changed = try StoreMaintenance.run(context)

        #expect(changed == pairs.count)
        for pair in pairs {
            let uuids = pair.uuids()
            #expect(uuids.count == 2, "\(pair.table) : les deux lignes partagent encore un uuid")
            #expect(uuids.allSatisfy { !$0.isEmpty }, "\(pair.table) : un uuid vide")
        }

        #expect(try StoreMaintenance.run(context) == 0)
    }

    /// La garantie forte, insensible à toute liste écrite à la main : chaque
    /// entité du schéma portant une propriété nommée `uuid` — mirrorée ou
    /// non — doit se retrouver dans `StoreMaintenance.uuidRepairs`. Les deux
    /// côtés de la comparaison sont lus par réflexion sur des sources
    /// indépendantes (`AppModelContainer.schema` d'un côté, le tableau que
    /// `StoreMaintenance.run` parcourt réellement de l'autre), donc un modèle
    /// ajouté au schéma avec un `uuid` par défaut et jamais raccordé à la
    /// réparation fait tomber ce test plutôt que de rester invisible jusqu'à
    /// une restauration de sauvegarde en production — voir l'en-tête de
    /// `Cairn/Model/StoreMaintenance.swift`.
    @Test("toute entité du schéma portant un uuid est raccordée à la réparation")
    func everySchemaEntityCarryingAUUIDIsRepaired() {
        let entitiesWithUUID = Set(
            AppModelContainer.schema.entities
                .filter { entity in
                    entity.storedProperties.contains { $0.name == "uuid" }
                }
                .map(\.name)
        )
        let repairedEntities = Set(StoreMaintenance.uuidRepairs.map(\.entityName))

        #expect(repairedEntities == entitiesWithUUID)
    }

    @Test("relancer sur un store déjà réparé ne change plus rien")
    func isIdempotent() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let shared = "64D8A062-4BAC-4EAF-BB62-5803626D04E5"
        let one = Activity(stravaID: 1, name: "Une", sportType: .run)
        let two = Activity(stravaID: 2, name: "Deux", sportType: .run)
        one.uuid = shared
        two.uuid = shared
        context.insert(one)
        context.insert(two)
        try context.save()
        try StoreMaintenance.run(context)

        let changed = try StoreMaintenance.run(context)

        #expect(changed == 0)
    }
}
