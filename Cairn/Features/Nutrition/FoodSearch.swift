// Cairn/Features/Nutrition/FoodSearch.swift
import Foundation

/// Assembly of the food picker's result list, ported from suivinut's
/// `SearchScreen._run_search`: the foods the user actually eats come first.
///
/// Empty query — favorites, then the recently logged foods that are not
/// already favorites. With a query — the favorites whose name matches, then
/// the catalog hits, never showing a product twice.
enum FoodSearch {
    /// One row of the unified list. A non-nil `favoriteGrams` is what makes
    /// a row a favorite: it carries the star and prefills the quantity.
    struct Hit: Equatable, Identifiable {
        var id: String
        var name: String
        var brands: String
        var kcal100: Double
        var protein100: Double
        var carbs100: Double
        var fat100: Double
        var fiber100: Double?
        var productCode: String?
        var favoriteGrams: Double?

        var isFavorite: Bool { favoriteGrams != nil }
    }

    /// Lowercased and stripped of diacritics, matching the catalog's own
    /// tokenizer (`remove_diacritics`) so « creme » finds the « Crème » favorite.
    static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive],
                     locale: Locale(identifier: "fr_FR"))
    }

    static func assemble(
        query: String, favorites: [Hit], recents: [Hit], catalog: [Hit]
    ) -> [Hit] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            // The (name, code) pair is the identity — suivinut's `fav_keys` —
            // because manual foods have no code at all.
            let favoriteKeys = Set(favorites.map { key($0) })
            return favorites + recents.filter { !favoriteKeys.contains(key($0)) }
        }
        let needle = normalized(trimmed)
        let matching = favorites.filter { normalized($0.name).contains(needle) }
        // Only the *matching* favorites shadow their catalog hit: a favorite
        // that is not on screen hides nothing.
        let shadowed = Set(matching.compactMap(\.productCode))
        let visible = catalog.filter { hit in
            hit.productCode.map { !shadowed.contains($0) } ?? true
        }
        // Trié par rang, l'ordre du moteur départageant les égalités : c'est
        // ce que fait l'indice, `sort` n'étant pas stable en Swift.
        let ranked = visible.enumerated()
            .sorted { left, right in
                let a = rank(left.element, needle: needle)
                let b = rank(right.element, needle: needle)
                return a == b ? left.offset < right.offset : a < b
            }
            .map(\.element)
        return matching + ranked
    }

    /// À quel point ce produit *est* ce qu'on a demandé — zéro étant le mieux.
    ///
    /// Trois rangs, et deux défauts distincts à réparer.
    ///
    /// Le premier : « une banane est une banane, c'est pas un code-barre ».
    /// Tout ce qui vient d'un primeur est sans marque — une courgette, une
    /// tomate — et les vingt références de marque qui les précédaient ne
    /// proposaient qu'un choix arbitraire entre des fiches inégalement
    /// remplies. Sans marque et nommé exactement : rang 0.
    ///
    /// Le second : chercher « banane » et recevoir « Barre énergie banane
    /// coco » avant « Bananes » est un mauvais classement, marque ou pas. Un
    /// nom qui vaut la recherche entière passe donc devant un nom qui la
    /// contient : rang 1 contre rang 2.
    ///
    /// L'égalité de nom se juge au pluriel près, et sur la recherche entière :
    /// « banane » vaut « Banane » et « Bananes », jamais « Barre chocolatée à
    /// la banane ». Et « skyr danone » ne promeut rien — aucun produit ne
    /// s'appelle ainsi, tous restent au rang 2 dans l'ordre du moteur. Une
    /// règle plus large ferait passer un « Skyr » générique devant le « Skyr
    /// Danone » qu'on vient précisément de nommer.
    static func rank(_ hit: Hit, needle: String) -> Int {
        let name = normalized(hit.name).trimmingCharacters(in: .whitespaces)
        let whole = name == needle || name == needle + "s" || needle == name + "s"
        guard whole else { return 2 }
        return hit.brands.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : 1
    }

    private static func key(_ hit: Hit) -> String {
        "\(hit.name)|\(hit.productCode ?? "")"
    }
}
