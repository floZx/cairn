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

    /// À quel point ce produit répond à ce qu'on a demandé — zéro étant le
    /// mieux.
    ///
    /// Trois critères, dans cet ordre, et le second vient d'une mesure qui a
    /// renversé l'intuition de départ.
    ///
    /// **Le nom d'abord.** Chercher « banane » et recevoir « Barre énergie
    /// banane coco » avant « Bananes » est un mauvais classement, marque ou
    /// pas. L'égalité se juge au pluriel près et sur la recherche entière :
    /// « skyr danone » ne promeut donc rien, aucun produit ne s'appelant
    /// ainsi, et tout reste dans l'ordre du moteur.
    ///
    /// **La donnée ensuite.** L'intention était « le générique d'abord, une
    /// banane est une banane ». Puis j'ai compté, le 18 août 2026, sur les
    /// cinquante premiers de trois catégories d'Open Food Facts : dix-sept
    /// bananes génériques sans marque, sept courgettes, une tomate — et
    /// **aucune** ne porte de fibres. Ce sont des fiches nues, un nom et rien
    /// d'autre. Mettre le générique devant sans réserve, c'était donc garantir
    /// un tiret à chaque saisie. Un produit renseigné passe devant un produit
    /// muet.
    ///
    /// **L'absence de marque enfin**, pour départager. C'est là qu'elle a sa
    /// place : entre deux bananes également documentées, celle du primeur.
    static func rank(_ hit: Hit, needle: String) -> Int {
        let name = normalized(hit.name).trimmingCharacters(in: .whitespaces)
        let whole = name == needle || name == needle + "s" || needle == name + "s"
        guard whole else { return 4 }
        let documented = hit.fiber100 != nil
        let brandless = hit.brands.trimmingCharacters(in: .whitespaces).isEmpty
        return (documented ? 0 : 2) + (brandless ? 0 : 1)
    }

    private static func key(_ hit: Hit) -> String {
        "\(hit.name)|\(hit.productCode ?? "")"
    }
}
