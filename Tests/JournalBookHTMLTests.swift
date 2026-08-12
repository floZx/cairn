import Testing
import SwiftData
import Foundation
@testable import Cairn

@Suite("Le HTML du carnet")
@MainActor
struct JournalBookHTMLTests {
    private func key(_ raw: String) -> DateKey { DateKey(raw: raw)! }

    private func makeContext() throws -> ModelContext {
        ModelContext(try AppModelContainer.inMemory())
    }

    private func book(
        days: [JournalBook.Day], from: String = "2026-08-01", to: String = "2026-08-31"
    ) -> JournalBook {
        JournalBook(
            from: key(from), to: key(to), days: days,
            totals: JournalBook.Totals(
                activityCount: 0, distance: 0, elevation: 0, movingTime: 0,
                bySport: [], firstWeightKg: nil, lastWeightKg: nil
            )
        )
    }

    private func day(
        _ raw: String, note: String = "", activities: [Activity] = [],
        meals: [JournalBook.Meal] = [], weightKg: Double? = nil
    ) -> JournalBook.Day {
        JournalBook.Day(
            date: key(raw), note: note, tags: [], activities: activities,
            meals: meals, weightKg: weightKg, weightNote: nil
        )
    }

    private func makeRun(in context: ModelContext) -> Activity {
        let activity = Activity(stravaID: 7, name: "Footing", sportType: .run)
        activity.startDate = Date(timeIntervalSince1970: 1_786_435_200)
        activity.distance = 10_000
        activity.movingTime = 3000
        activity.averageSpeed = 10_000 / 3000
        context.insert(activity)
        return activity
    }

    @Test("le document est autonome : un seul fichier, style compris")
    func thedocumentStandsAlone() {
        let html = JournalBookHTML.document(
            book(days: [day("2026-08-02", note: "Repos.")]), illustrations: [:]
        )
        #expect(html.hasPrefix("<!DOCTYPE html>"))
        #expect(html.contains("<style>"))
        // Rien à charger de l'extérieur : ni feuille liée, ni image distante.
        #expect(!html.contains("<link"))
        #expect(!html.contains("src=\"http"))
    }

    @Test("la note d'une journée est rendue, pas recopiée")
    func thenoteIsRendered() {
        let html = JournalBookHTML.document(
            book(days: [day("2026-08-02", note: "# Titre\n\nUn **gras**.")]),
            illustrations: [:]
        )
        #expect(html.contains("<h1>Titre</h1>"))
        #expect(html.contains("<strong>gras</strong>"))
        #expect(!html.contains("**gras**"))
    }

    @Test("un caractère réservé d'une note ne casse pas le document")
    func areservedCharacterIsEscaped() {
        let html = JournalBookHTML.document(
            book(days: [day("2026-08-02", note: "Pain & <fromage>")]),
            illustrations: [:]
        )
        #expect(html.contains("Pain &amp; &lt;fromage&gt;"))
    }

    @Test("une journée sans sortie ne produit aucun bloc de sortie")
    func nooutingNoBlock() {
        let html = JournalBookHTML.document(
            book(days: [day("2026-08-02", note: "Repos.")]), illustrations: [:]
        )
        #expect(!html.contains("class=\"activity\""))
    }

    @Test("une sortie sans image ne laisse pas de balise vide")
    func amissingImageLeavesNoTag() throws {
        let context = try makeContext()
        let html = JournalBookHTML.document(
            book(days: [day("2026-08-11", activities: [makeRun(in: context)])]),
            illustrations: [:]
        )
        #expect(html.contains("class=\"activity\""))
        #expect(html.contains("Footing"))
        #expect(!html.contains("src=\"\""))
        #expect(!html.contains("<img"))
    }

    @Test("les images fournies sont posées dans la sortie")
    func illustrationsLandInTheOuting() throws {
        let context = try makeContext()
        let html = JournalBookHTML.document(
            book(days: [day("2026-08-11", activities: [makeRun(in: context)])]),
            illustrations: [7: JournalBookHTML.Illustrations(
                map: "data:image/png;base64,AAA",
                charts: ["data:image/png;base64,BBB"],
                photos: ["data:image/png;base64,CCC"]
            )]
        )
        #expect(html.contains("data:image/png;base64,AAA"))
        #expect(html.contains("data:image/png;base64,BBB"))
        #expect(html.contains("data:image/png;base64,CCC"))
    }

    @Test("une carte vectorielle entre telle quelle, pas dans une image")
    func avectorMapIsInlined() throws {
        let context = try makeContext()
        let html = JournalBookHTML.document(
            book(days: [day("2026-08-11", activities: [makeRun(in: context)])]),
            illustrations: [7: JournalBookHTML.Illustrations(
                map: "<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>"
            )]
        )
        // Un SVG en ligne reste net et se style ; l'emballer dans un `src`
        // aurait demandé de l'encoder pour rien.
        #expect(html.contains("<figure class=\"map\"><svg"))
        #expect(!html.contains("<img"))
    }

    @Test("les chiffres sont ceux de l'écran, allure comprise")
    func figuresReadLikeTheApp() throws {
        let context = try makeContext()
        let html = JournalBookHTML.document(
            book(days: [day("2026-08-11", activities: [makeRun(in: context)])]),
            illustrations: [:]
        )
        #expect(html.contains(Format.distance(10_000)))
        #expect(html.contains(Format.speed(10_000 / 3000, sport: .run)))
        // Une course se lit en allure, pas en vitesse.
        #expect(html.contains("<dt>Allure</dt>"))
    }

    @Test("le repas et le poids d'une journée s'écrivent quand ils existent")
    func mealsAndWeightAppear() {
        let html = JournalBookHTML.document(
            book(days: [day(
                "2026-08-03",
                meals: [JournalBook.Meal(
                    name: "Déjeuner", kcal: 700, protein: 16, carbs: 156, fat: 2,
                    note: "Bien."
                )],
                weightKg: 70.2
            )]),
            illustrations: [:]
        )
        #expect(html.contains("Déjeuner"))
        #expect(html.contains("700 kcal"))
        #expect(html.contains("70,2 kg"))
    }

    @Test("une journée sans repas ni poids n'ouvre pas de bloc alimentation")
    func nofoodNoBlock() {
        let html = JournalBookHTML.document(
            book(days: [day("2026-08-02", note: "Repos.")]), illustrations: [:]
        )
        #expect(!html.contains("class=\"food\""))
    }

    @Test("la page de garde dit la période et ce qu'elle pèse")
    func thecoverSaysWhatThePeriodWeighs() {
        let full = JournalBook(
            from: key("2026-08-01"), to: key("2026-08-31"),
            days: [day("2026-08-02", note: "Repos.")],
            totals: JournalBook.Totals(
                activityCount: 12, distance: 140_000, elevation: 1_200,
                movingTime: 40_000, bySport: [
                    (sport: .run, count: 8, distance: 90_000),
                    (sport: .ride, count: 4, distance: 50_000),
                ],
                firstWeightKg: 70.6, lastWeightKg: 69.8
            )
        )
        let html = JournalBookHTML.document(full, illustrations: [:])
        #expect(html.contains("class=\"cover\""))
        #expect(html.contains("<dd>12</dd>"))
        #expect(html.contains(Format.distance(140_000)))
        #expect(html.contains("Course"))
        #expect(html.contains("70,6"))
        #expect(html.contains("69,8"))
    }

    @Test("une période sans une seule sortie n'affiche pas une rangée de zéros")
    func anemptyPeriodPrintsNoZeroes() {
        let html = JournalBookHTML.document(
            book(days: [day("2026-08-02", note: "Repos.")]), illustrations: [:]
        )
        #expect(html.contains("class=\"cover\""))
        #expect(!html.contains("class=\"totals\""))
    }
}
