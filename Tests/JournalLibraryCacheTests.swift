import Testing
import Foundation
import SwiftData
@testable import Cairn

/// La règle qui décide *quand* la bibliothèque est retraversée.
///
/// C'est la moitié risquée de la mémoire de calcul : trop périmer ne coûte que
/// du temps, pas assez sert une bibliothèque d'avant — une sortie importée qui
/// n'apparaît dans le journal qu'au clic suivant.
///
/// Les cas s'observent par un détour assumé : on rappelle le cache avec une
/// liste **différente** de celle du premier appel. S'il renvoie encore
/// l'ancienne, c'est qu'il n'a pas retraversé.
@Suite("La mémoire de calcul du journal")
@MainActor
struct JournalLibraryCacheTests {
    private func contexte() throws -> ModelContext {
        ModelContext(try AppModelContainer.inMemory())
    }

    private func sortie(_ jour: String) -> Activity {
        let activite = Activity(
            stravaID: Int64.random(in: 1...1_000_000), name: "Sortie", sportType: .run
        )
        activite.startDate = DateKey(raw: jour)!.date()
        return activite
    }

    @Test("Une sortie enregistrée fait retraverser")
    func uneSortieFaitPerimer() throws {
        let context = try contexte()
        let cache = JournalLibraryCache()
        let premiere = sortie("2026-08-10")
        context.insert(premiere)
        try context.save()

        #expect(cache.contenu(
            activities: [premiere], notedActivities: [], mealNotes: [], weights: []
        ).jours == ["2026-08-10"])

        let seconde = sortie("2026-08-11")
        context.insert(seconde)
        try context.save()

        #expect(cache.contenu(
            activities: [premiere, seconde], notedActivities: [], mealNotes: [], weights: []
        ).jours == ["2026-08-10", "2026-08-11"])
    }

    /// Le carnet s'enregistre à chaque temporisation de frappe, et ne dit rien
    /// de ce que le cache tient. Sans ce tri, taper refaisait la traversée
    /// toutes les deux secondes.
    @Test("Une note du carnet ne fait pas retraverser")
    func uneNoteNeFaitPasPerimer() throws {
        let context = try contexte()
        let cache = JournalLibraryCache()
        let premiere = sortie("2026-08-10")
        context.insert(premiere)
        try context.save()
        _ = cache.contenu(
            activities: [premiere], notedActivities: [], mealNotes: [], weights: []
        )

        context.insert(JournalNote(dateKey: DateKey(raw: "2026-08-12")!, text: "Écrit."))
        try context.save()

        // La seconde sortie est passée sous silence : le cache n'a pas
        // retraversé, ce qui est exactement ce qu'on lui demande ici.
        let seconde = sortie("2026-08-11")
        #expect(cache.contenu(
            activities: [premiere, seconde], notedActivities: [], mealNotes: [], weights: []
        ).jours == ["2026-08-10"])
    }

    @Test("Une pesée enregistrée fait retraverser")
    func unePeseeFaitPerimer() throws {
        let context = try contexte()
        let cache = JournalLibraryCache()
        _ = cache.contenu(activities: [], notedActivities: [], mealNotes: [], weights: [])

        let pesee = WeightEntry(dateKey: DateKey(raw: "2026-08-10")!, weightKg: 70)
        context.insert(pesee)
        try context.save()

        #expect(cache.contenu(
            activities: [], notedActivities: [], mealNotes: [], weights: [pesee]
        ).jours == ["2026-08-10"])
    }

    /// Dans le doute, périmer : une notification qu'on ne sait pas lire ne doit
    /// jamais laisser servir une bibliothèque d'avant.
    @Test("Une notification illisible fait retraverser")
    func leDouteFaitPerimer() {
        #expect(JournalLibraryCache.toucheLaBibliotheque(
            Notification(name: ModelContext.didSave)
        ))
        #expect(JournalLibraryCache.toucheLaBibliotheque(
            Notification(name: ModelContext.didSave, object: nil, userInfo: ["autre": 1])
        ))
    }
}
