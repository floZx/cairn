// Cairn/Features/Nutrition/RecipesManagerSheet.swift
import SwiftUI
import SwiftData

/// The recipe library: composition, totals, pruning, and adding items via
/// the shared food picker. Creation happens from a filled meal ("Enregistrer
/// ce repas comme recette") — a recipe born empty is a recipe nobody applies.
struct RecipesManagerSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @State private var selectedID: PersistentIdentifier?
    @State private var isAddingItem = false
    @State private var errorMessage: String?
    @State private var addItemErrorMessage: String?

    private var selectedRecipe: Recipe? {
        recipes.first { $0.persistentModelID == selectedID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recettes")
                .font(.headline)
            HStack(alignment: .top, spacing: 16) {
                List(recipes, selection: $selectedID) { recipe in
                    Text(recipe.name)
                        .lineLimit(1)
                        .tag(recipe.persistentModelID)
                }
                .frame(width: 200)
                Group {
                    if let recipe = selectedRecipe {
                        composition(of: recipe)
                    } else {
                        ContentUnavailableView(
                            "Aucune recette sélectionnée",
                            systemImage: "book"
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                // Saved on the way out as well as on Return: a field left
                // filled but not validated has already changed the object in
                // memory, and closing on it would be the silent loss this
                // project exists to prevent.
                Button("Fermer") {
                    save()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 420)
        .onSubmit { save() }
        .sheet(isPresented: $isAddingItem) {
            addItemSheet
        }
    }

    private func composition(of recipe: Recipe) -> some View {
        let items = recipe.orderedItems
        let total = items.map { Macros(of: $0) }.reduce(.zero, +)
        return VStack(alignment: .leading, spacing: 8) {
            // The name is editable where the recipe is read, not only where it
            // was born: a recipe used to keep whatever it was called at
            // creation, so a typo meant building the whole thing again.
            TextField("Nom de la recette", text: Bindable(recipe).name)
                .textFieldStyle(.roundedBorder)
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Text("Aliment")
                    Text("g").gridColumnAlignment(.trailing)
                    Text("kcal").gridColumnAlignment(.trailing)
                    Text("").gridColumnAlignment(.trailing)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                ForEach(items, id: \.persistentModelID) { item in
                    GridRow {
                        // Editable in place, like the favourites manager
                        // beside it: changing 100 g into 120 used to mean
                        // removing the line and searching the food again.
                        TextField("Aliment", text: Bindable(item).foodName)
                            .textFieldStyle(.plain)
                            .lineLimit(1)
                        DecimalField(
                            placeholder: "g", value: Bindable(item).grams,
                            width: 56
                        )
                        // The kilocalories follow the quantity and are not
                        // typed: they are the per-100 g values captured when
                        // the food was picked, which stay what was eaten.
                        Text("\(Int(Macros(of: item).kcal.rounded()))")
                        HStack(spacing: 2) {
                            Button { move(item, direction: -1) } label: {
                                Image(systemName: "chevron.up")
                            }
                            .help("Monter dans la recette")
                            .disabled(item.persistentModelID
                                == items.first?.persistentModelID)
                            Button { move(item, direction: 1) } label: {
                                Image(systemName: "chevron.down")
                            }
                            .help("Descendre dans la recette")
                            .disabled(item.persistentModelID
                                == items.last?.persistentModelID)
                            Button { delete(item) } label: {
                                Image(systemName: "minus.circle")
                            }
                            .help("Retirer de la recette")
                        }
                        .buttonStyle(.borderless)
                    }
                    .font(.body.monospacedDigit())
                }
            }
            Text(
                "Total : \(Int(total.kcal.rounded())) kcal · "
                + "P \(Int(total.protein.rounded())) · "
                + "G \(Int(total.carbs.rounded())) · "
                + "L \(Int(total.fat.rounded()))"
            )
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            HStack {
                Button("Ajouter un aliment…") {
                    addItemErrorMessage = nil
                    isAddingItem = true
                }
                Spacer()
                Button("Supprimer la recette", role: .destructive) {
                    delete(recipe)
                }
            }
        }
    }

    private var addItemSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ajouter à « \(selectedRecipe?.name ?? "") »")
                .font(.headline)
            FoodPickerView { pick in addItem(pick) }
            if let addItemErrorMessage {
                Text(addItemErrorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Annuler") { isAddingItem = false }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 640)
    }

    private func addItem(_ pick: FoodPick) {
        guard let recipe = selectedRecipe else { return }
        do {
            try NutritionJournal.addRecipeItem(
                to: recipe, foodName: pick.foodName, kcal100: pick.kcal100,
                protein100: pick.protein100, carbs100: pick.carbs100,
                fat100: pick.fat100, grams: pick.grams,
                productCode: pick.productCode, fiber100: pick.fiber100,
                in: modelContext
            )
            errorMessage = nil
            isAddingItem = false
        } catch {
            addItemErrorMessage =
                "L'aliment n'a pas pu être ajouté. \(error.localizedDescription)"
        }
    }

    /// Written on Return, as the favourites manager does: a field one is
    /// still typing in is not a value to store, and the sheet has no other
    /// moment that means "done".
    private func save() {
        do {
            try modelContext.save()
            errorMessage = nil
        } catch {
            errorMessage = "Votre modification n'a pas pu être enregistrée. "
                + error.localizedDescription
        }
    }

    private func move(_ item: RecipeItem, direction: Int) {
        do {
            try NutritionJournal.moveRecipeItem(
                item, direction: direction, in: modelContext
            )
            errorMessage = nil
        } catch {
            errorMessage = "Le déplacement n'a pas pu être enregistré. "
                + error.localizedDescription
        }
    }

    private func delete(_ item: RecipeItem) {
        do {
            try NutritionJournal.deleteRecipeItem(item, in: modelContext)
            errorMessage = nil
        } catch {
            errorMessage =
                "La suppression n'a pas pu être enregistrée. \(error.localizedDescription)"
        }
    }

    private func delete(_ recipe: Recipe) {
        selectedID = nil
        do {
            try NutritionJournal.deleteRecipe(recipe, in: modelContext)
            errorMessage = nil
        } catch {
            errorMessage =
                "La suppression n'a pas pu être enregistrée. \(error.localizedDescription)"
        }
    }
}
