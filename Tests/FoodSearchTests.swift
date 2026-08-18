import Testing
@testable import Cairn

@Suite("FoodSearch")
struct FoodSearchTests {
    private func favorite(
        _ name: String, code: String? = nil, grams: Double = 50
    ) -> FoodSearch.Hit {
        FoodSearch.Hit(
            id: "fav:\(name)", name: name, brands: "", kcal100: 100,
            protein100: 5, carbs100: 10, fat100: 3, productCode: code,
            favoriteGrams: grams
        )
    }

    private func plain(
        _ name: String, code: String? = nil, id: String? = nil
    ) -> FoodSearch.Hit {
        FoodSearch.Hit(
            id: id ?? "hit:\(name)", name: name, brands: "", kcal100: 100,
            protein100: 5, carbs100: 10, fat100: 3, productCode: code,
            favoriteGrams: nil
        )
    }

    private func marque(
        _ name: String, _ brand: String, code: String
    ) -> FoodSearch.Hit {
        FoodSearch.Hit(
            id: "hit:\(code)", name: name, brands: brand, kcal100: 100,
            protein100: 5, carbs100: 10, fat100: 3, productCode: code,
            favoriteGrams: nil
        )
    }

    @Test("le générique sans marque passe devant les produits de marque")
    func genericComesFirst() {
        // Une banane est une banane : celle du primeur n'a pas de code-barre,
        // et c'est elle qu'on cherche en tapant « banane ».
        let merged = FoodSearch.assemble(
            query: "banane", favorites: [], recents: [],
            catalog: [
                marque("Banane", "Chiquita", code: "1"),
                marque("Banane bio", "Carrefour", code: "2"),
                plain("Bananes", code: "3"),
            ]
        )
        #expect(merged.map(\.id) == ["hit:Bananes", "hit:1", "hit:2"])
    }

    @Test("la promotion ne touche pas une recherche qui nomme sa marque")
    func brandedQueryIsLeftAlone() {
        // Sans quoi un « Skyr » générique passerait devant le « Skyr Danone »
        // qu'on vient précisément de nommer.
        let merged = FoodSearch.assemble(
            query: "skyr danone", favorites: [], recents: [],
            catalog: [
                marque("Skyr", "Danone", code: "1"),
                plain("Skyr", code: "2"),
            ]
        )
        #expect(merged.map(\.productCode) == ["1", "2"])
    }

    @Test("un nom qui vaut la recherche passe devant un nom qui la contient")
    func wholeNameBeatsPartial() {
        // Chercher « banane » et recevoir la barre chocolatée en premier est un
        // mauvais classement, marque ou pas : c'est ce que rend le moteur d'OFF
        // sur le web, mesuré le 18 août 2026.
        let merged = FoodSearch.assemble(
            query: "banane", favorites: [], recents: [],
            catalog: [
                plain("Barre chocolatée à la banane", code: "1"),
                marque("Banane", "Chiquita", code: "2"),
            ]
        )
        #expect(merged.map(\.productCode) == ["2", "1"])
    }

    @Test("à rang égal, l'ordre du moteur est conservé")
    func equalRanksKeepEngineOrder() {
        let merged = FoodSearch.assemble(
            query: "pain", favorites: [], recents: [],
            catalog: [
                plain("Pain de mie complet", code: "1"),
                plain("Pain aux céréales", code: "2"),
                plain("Pain brioché", code: "3"),
            ]
        )
        #expect(merged.map(\.productCode) == ["1", "2", "3"])
    }

    @Test("champ vide : favoris d'abord, puis les récents non redondants")
    func emptyQueryListsFavoritesThenRecents() {
        let skyr = favorite("Skyr", code: "123")
        let manual = favorite("Ma soupe")
        let merged = FoodSearch.assemble(
            query: "  ",
            favorites: [skyr, manual],
            recents: [
                plain("Skyr", code: "123", id: "r1"),   // déjà en favori
                plain("Pain", code: "456", id: "r2"),
                plain("Ma soupe", id: "r3"),            // favori sans code
            ],
            catalog: [plain("Jamais montré", code: "999")]
        )
        #expect(merged.map(\.name) == ["Skyr", "Ma soupe", "Pain"])
        #expect(merged[0].isFavorite && merged[1].isFavorite)
        #expect(!merged[2].isFavorite)
    }

    @Test("avec requête : les favoris correspondants coiffent le catalogue")
    func queryPutsMatchingFavoritesOnTop() {
        let merged = FoodSearch.assemble(
            query: "creme",
            favorites: [
                favorite("Crème fraîche", code: "123"),
                favorite("Skyr", code: "789"),
            ],
            recents: [plain("Récent ignoré", id: "r1")],
            catalog: [
                plain("Crème fraîche 30%", code: "123"),  // doublon du favori
                plain("Crème anglaise", code: "456"),
            ]
        )
        // Accents ignorés, favori en tête, son produit catalogue absorbé.
        #expect(merged.map(\.name) == ["Crème fraîche", "Crème anglaise"])
        #expect(merged[0].isFavorite)
    }

    @Test("un favori qui ne correspond pas ne masque pas son produit catalogue")
    func nonMatchingFavoriteHidesNothing() {
        let merged = FoodSearch.assemble(
            query: "skyr",
            favorites: [favorite("Crème fraîche", code: "123")],
            recents: [],
            catalog: [plain("Skyr nature", code: "123")]
        )
        #expect(merged.map(\.name) == ["Skyr nature"])
    }
}
