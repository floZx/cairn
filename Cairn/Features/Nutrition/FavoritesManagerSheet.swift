// Cairn/Features/Nutrition/FavoritesManagerSheet.swift
import SwiftUI
import SwiftData

/// The favourites library: rename, adjust the usual serving, prune.
///
/// Favourites are created from the journal's star, and until now that was
/// also the only place they could be undone — the star of a food no longer
/// eaten is unreachable once the entry it was set on has scrolled into last
/// winter. Here they are all in one list.
struct FavoritesManagerSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FavoriteFood.foodName) private var favorites: [FavoriteFood]
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Favoris")
                .font(.headline)
            if favorites.isEmpty {
                ContentUnavailableView(
                    "Aucun favori",
                    systemImage: "star",
                    description: Text(
                        "L'étoile d'une ligne du journal ajoute l'aliment ici, "
                        + "avec la quantité de cette ligne."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(favorites) {
                    TableColumn("Aliment") { favorite in
                        // Editable in place: a favourite imported from Open
                        // Food Facts carries the brand's own capitalisation
                        // and a trailing weight nobody wants to read daily.
                        TextField("Nom", text: binding(for: favorite).foodName)
                            .textFieldStyle(.plain)
                            .onSubmit { save() }
                    }
                    TableColumn("Quantité") { favorite in
                        HStack(spacing: 4) {
                            TextField(
                                "g", value: binding(for: favorite).grams,
                                format: .number
                            )
                            .textFieldStyle(.plain)
                            .frame(width: 52)
                            .monospacedDigit()
                            .onSubmit { save() }
                            Text("g").foregroundStyle(.secondary)
                        }
                    }
                    .width(80)
                    TableColumn("Pour 100 g") { favorite in
                        Text(macros(of: favorite))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .width(min: 180, ideal: 220)
                    TableColumn("") { favorite in
                        Button {
                            remove(favorite)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Retirer des favoris")
                    }
                    .width(28)
                }
                .frame(minHeight: 260)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Fermer") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 400)
    }

    /// `@Bindable` cannot be declared inside a `TableColumn` builder, so the
    /// bindings are made by hand from the model object.
    private func binding(for favorite: FavoriteFood) -> Bindable<FavoriteFood> {
        Bindable(favorite)
    }

    private func macros(_ value: Double) -> String {
        "\(Int(value.rounded()))"
    }

    private func macros(of favorite: FavoriteFood) -> String {
        "\(macros(favorite.kcal100)) kcal · P \(macros(favorite.protein100))"
            + " · G \(macros(favorite.carbs100)) · L \(macros(favorite.fat100))"
    }

    private func remove(_ favorite: FavoriteFood) {
        do {
            try NutritionJournal.removeFavorite(favorite, in: modelContext)
        } catch {
            errorMessage =
                "Le favori n'a pas pu être retiré. \(error.localizedDescription)"
        }
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            errorMessage =
                "Votre modification n'a pas pu être enregistrée. \(error.localizedDescription)"
        }
    }
}
