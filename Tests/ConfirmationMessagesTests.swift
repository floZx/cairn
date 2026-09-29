import Testing
@testable import Cairn

@Suite("Ce que les confirmations annoncent")
struct ConfirmationMessagesTests {
    @Test func unJourTypeDitCombienDeJourneesIlLaisseSansType() {
        #expect(NutritionSettingsView.dayTypeDeletionMessage(days: 0)
                == "Aucune journée du journal ne le porte.")
        #expect(NutritionSettingsView.dayTypeDeletionMessage(days: 1)
                .hasPrefix("Une journée du journal le porte"))
        #expect(NutritionSettingsView.dayTypeDeletionMessage(days: 12)
                .hasPrefix("12 journées du journal le portent"))
    }

    /// 200 requêtes par quart d'heure : neuf cents sorties font cinq quarts
    /// d'heure, qu'on annonce en heures.
    @Test func resynchroniserToutAnnonceUneDureeAuRythmeDeStrava() {
        #expect(ResyncEverythingConfirmation.message(activityCount: 150).contains("15 minutes"))
        #expect(ResyncEverythingConfirmation.message(activityCount: 900).contains("environ 1 h"))
        #expect(ResyncEverythingConfirmation.message(activityCount: 900).contains("900 activités"))
        #expect(ResyncEverythingConfirmation.message(activityCount: 2_500).contains("plusieurs jours"))
    }
}
