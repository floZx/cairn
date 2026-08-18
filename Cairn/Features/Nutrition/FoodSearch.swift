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
        return matching + catalog.filter { hit in
            hit.productCode.map { !shadowed.contains($0) } ?? true
        }
    }

    private static func key(_ hit: Hit) -> String {
        "\(hit.name)|\(hit.productCode ?? "")"
    }
}
