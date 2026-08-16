import Testing
import Foundation
@testable import Cairn

/// Makes the task 5 brief's step-5 cross-check permanent: a one-off script
/// run once and discarded would not catch a drift introduced by a later
/// task. This reads `supabase/schema.sql` itself, so any of the sixteen
/// conformances that gains or loses a column — or starts emitting a reserved
/// one — fails here instead of as a 400 from PostgREST at push time.
@Suite("Lignes du miroir face au schéma")
struct MirrorRowSchemaTests {
    /// Posed by the Postgres trigger (`updated_at`) or by the engine at push
    /// time (`edited_at`, `deleted_at`, tasks 6 and 9), or left empty until a
    /// later tranche (`field_edited_at`). Every mirrored table carries all
    /// four in the schema; no `mirrorRow` may ever emit any of them.
    static let reservedColumns: Set<String> = [
        "updated_at", "edited_at", "deleted_at", "field_edited_at",
    ]

    /// The repository root, found from this source file's own path rather
    /// than from a bundled resource: `#filePath` needs no entry in
    /// `project.yml`, so there is nothing an `xcodegen generate` could ever
    /// forget to wire up.
    static func repositoryRoot(from filePath: String = #filePath) -> URL {
        URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // repository root
    }

    /// Every `create table`'s columns, keyed by table name — `nil` when
    /// `schema.sql` cannot be read or parses to nothing, which the caller
    /// must treat as a failure. A guard rail that silently no-ops when its
    /// input goes missing is worse than having none.
    static func schemaColumns(from filePath: String = #filePath) -> [String: Set<String>]? {
        let url = repositoryRoot(from: filePath).appendingPathComponent("supabase/schema.sql")
        guard let contents = try? String(contentsOf: url, encoding: .utf8),
              !contents.isEmpty
        else { return nil }

        guard let regex = try? NSRegularExpression(
            pattern: #"create table (\w+) \(\n(.*?)\n\);"#,
            options: [.dotMatchesLineSeparators]
        ) else { return nil }

        let fullRange = NSRange(contents.startIndex..., in: contents)
        var tables: [String: Set<String>] = [:]
        for match in regex.matches(in: contents, range: fullRange) {
            guard let nameRange = Range(match.range(at: 1), in: contents),
                  let bodyRange = Range(match.range(at: 2), in: contents)
            else { continue }
            let name = String(contents[nameRange])
            let body = contents[bodyRange]
            let columns = body.split(separator: "\n").compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Blank separator lines and the prose comments explaining a
                // column (`edited_fields`, `simplified_track`, `gear_id`) are
                // not columns.
                guard !trimmed.isEmpty, !trimmed.hasPrefix("--") else { return nil }
                return trimmed.split(separator: " ").first.map(String.init)
            }
            tables[name] = Set(columns)
        }
        return tables.isEmpty ? nil : tables
    }

    /// One minimal instance per model that crosses to the mirror — the
    /// values themselves do not matter here, only the row's *keys* do.
    /// Sixteen, matching `AppModelContainer.schema` minus `SyncState`, the
    /// same count `MirrorIdentityTests` pins down independently.
    static func allRows() -> [any MirrorRow] {
        [
            Activity(stravaID: 1, name: "Sortie", sportType: .run),
            ActivityStreams(),
            ActivityPhoto(uniqueID: "p1"),
            Lap(stravaID: 1, lapIndex: 0),
            Gear(stravaID: "b1", name: "Vélo"),
            Athlete(stravaID: 1),
            DiscardedActivity(stravaID: 1, name: "Sortie annulée"),
            DayType(name: "Repos", kcalTarget: 2000),
            MealSlot(name: "Petit-déj"),
            NutritionDay(dateKey: DateKey(raw: "2026-08-16")!),
            FoodEntry(
                dateKey: DateKey(raw: "2026-08-16")!, mealSlot: nil, foodName: "Pomme",
                kcal100: 52, protein100: 0.3, carbs100: 14, fat100: 0.2, grams: 150
            ),
            MealNote(dateKey: DateKey(raw: "2026-08-16")!, mealSlot: nil, note: "Bon appétit"),
            Recipe(name: "Porridge"),
            RecipeItem(
                foodName: "Flocons d'avoine", kcal100: 389, protein100: 13, carbs100: 66,
                fat100: 7, grams: 80
            ),
            FavoriteFood(
                foodName: "Banane", kcal100: 89, protein100: 1.1, carbs100: 23, fat100: 0.3,
                grams: 120
            ),
            WeightEntry(dateKey: DateKey(raw: "2026-08-16")!, weightKg: 70),
        ]
    }

    /// Every model's row matches its table's columns exactly, once the four
    /// reserved ones are set aside — no column either side is missing, none
    /// is extra, and none of the sixteen ever emits a reserved column. This
    /// single test is what task 5's brief asked to verify by hand at step 5;
    /// it now runs on every build instead of once.
    @Test func chaqueLigneCorrespondExactementAuSchema() throws {
        let schema = try #require(
            Self.schemaColumns(),
            "schema.sql introuvable ou vide : le garde-fou ne peut pas s'exécuter"
        )
        // Sanity on the parse itself: sixteen tables, matching the sixteen
        // conformances below. A regression in the regex would otherwise show
        // up as every table silently missing rather than as a clear failure.
        #expect(schema.count == 16)

        for row in Self.allRows() {
            let table = type(of: row).mirrorTable
            let columns = try #require(
                schema[table], "table « \(table) » absente de supabase/schema.sql"
            )
            let expected = columns.subtracting(Self.reservedColumns)
            let emitted = Set(row.mirrorRow(userID: "u").keys)

            #expect(
                emitted == expected,
                """
                \(table) : manquantes \(expected.subtracting(emitted).sorted()), \
                en trop \(emitted.subtracting(expected).sorted())
                """
            )
            #expect(
                emitted.isDisjoint(with: Self.reservedColumns),
                "\(table) émet une colonne réservée : \(emitted.intersection(Self.reservedColumns))"
            )
        }
    }
}
