import Foundation

/// Anything carrying per-100 g values and a weight: a journal entry, a
/// recipe item, a favorite. One protocol so the macro arithmetic is written
/// once — suivinut's `entry_macros` accepted the same duck-typed shape.
protocol FoodPortion {
    var kcal100: Double { get }
    var protein100: Double { get }
    var carbs100: Double { get }
    var fat100: Double { get }
    var grams: Double { get }
}

extension FoodEntry: FoodPortion {}
extension RecipeItem: FoodPortion {}
extension FavoriteFood: FoodPortion {}

struct Macros: Equatable, Sendable {
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double

    static let zero = Macros(kcal: 0, protein: 0, carbs: 0, fat: 0)

    init(kcal: Double, protein: Double, carbs: Double, fat: Double) {
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }

    init(of portion: some FoodPortion) {
        let factor = portion.grams / 100
        self.init(
            kcal: portion.kcal100 * factor,
            protein: portion.protein100 * factor,
            carbs: portion.carbs100 * factor,
            fat: portion.fat100 * factor
        )
    }

    static func + (lhs: Macros, rhs: Macros) -> Macros {
        Macros(
            kcal: lhs.kcal + rhs.kcal, protein: lhs.protein + rhs.protein,
            carbs: lhs.carbs + rhs.carbs, fat: lhs.fat + rhs.fat
        )
    }

    func scaled(_ factor: Double) -> Macros {
        Macros(
            kcal: kcal * factor, protein: protein * factor,
            carbs: carbs * factor, fat: fat * factor
        )
    }
}

/// Pure nutrition arithmetic, ported line for line from suivinut's
/// `domain/nutrition.py` — the adaptive algorithm took three iterations to
/// get right over there, so the semantics are copied, not re-derived.
enum NutritionMath {
    /// How badly a target is exceeded — suivinut's `over_color` rule from
    /// `tui/widgets.py`: a moderate overshoot (up to +10 % of the target) is
    /// still fine, a heavy one is not. The half-gram slack keeps a rounding
    /// crumb from lighting up a figure the user reads as exactly on target.
    enum Overshoot {
        case moderate
        case heavy
    }

    static func overshoot(consumed: Double, target: Double) -> Overshoot? {
        guard target > 0, consumed > target + 0.5 else { return nil }
        return consumed > target * 1.10 ? .heavy : .moderate
    }

    /// Daily macro targets: kcal from the day type, protein and fat global,
    /// carbs deduced from what is left — `(kcal − 4P − 9L) / 4`, floored at 0.
    static func dailyTargets(
        kcalTarget: Int?, proteinG: Double, fatG: Double
    ) -> Macros? {
        guard let kcalTarget else { return nil }
        let kcal = Double(kcalTarget)
        let carbs = max(0, (kcal - 4 * proteinG - 9 * fatG) / 4)
        return Macros(kcal: kcal, protein: proteinG, carbs: carbs, fat: fatG)
    }

    static func mealTarget(daily: Macros, pct: Int) -> Macros {
        daily.scaled(Double(pct) / 100)
    }

    /// The day's remaining budget, each macro floored at zero — an exceeded
    /// margin reads as "nothing left", not as a negative allowance.
    static func remainingDay(daily: Macros, consumed: Macros) -> Macros {
        Macros(
            kcal: max(0, daily.kcal - consumed.kcal),
            protein: max(0, daily.protein - consumed.protein),
            carbs: max(0, daily.carbs - consumed.carbs),
            fat: max(0, daily.fat - consumed.fat)
        )
    }

    struct MealState {
        var pct: Int
        var started: Bool
        var consumed: Macros
    }

    /// Per-meal targets that adapt to what was actually eaten.
    ///
    /// A meal is *finished* as soon as a later meal is started. Finished
    /// meals keep their fixed plan share (to see how they compared to the
    /// plan). The current meal takes its share of the remaining budget with
    /// an unchanged formula — so its target does not jump when the first
    /// food lands in it. Upcoming (empty) meals split what is *really* left
    /// of the day, so eating exactly their target lands exactly on the
    /// day's goal whether earlier meals over- or under-shot.
    static func adaptiveMealTargets(
        daily: Macros?, meals: [MealState]
    ) -> [Macros?] {
        guard let daily else { return meals.map { _ in nil } }
        let count = meals.count
        let superseded = (0..<count).map { index in
            meals[(index + 1)...].contains { $0.started }
        }
        // What weighs on the budget without owning a target: finished meals
        // and 0 % slots. The current/upcoming meals' own intake stays in the
        // budget — it counts against their own target.
        let otherConsumed = (0..<count)
            .filter { superseded[$0] || meals[$0].pct <= 0 }
            .map { meals[$0].consumed }
            .reduce(.zero, +)
        let budget = remainingDay(daily: daily, consumed: otherConsumed)
        let inPlay = (0..<count).filter { !superseded[$0] && meals[$0].pct > 0 }
        let inPlayPct = inPlay.reduce(0) { $0 + meals[$1].pct }
        // The current meal is the last started one still in play — there can
        // only be one, anything before a started meal is superseded.
        let current = inPlay.last { meals[$0].started }
        let currentTarget: Macros?
        let currentConsumed: Macros
        if let current, inPlayPct > 0 {
            currentTarget = budget.scaled(
                Double(meals[current].pct) / Double(inPlayPct)
            )
            currentConsumed = meals[current].consumed
        } else {
            currentTarget = nil
            currentConsumed = .zero
        }
        let futureBudget = remainingDay(
            daily: daily, consumed: otherConsumed + currentConsumed
        )
        let futurePct = inPlay
            .filter { $0 != current && !meals[$0].started }
            .reduce(0) { $0 + meals[$1].pct }
        return (0..<count).map { index in
            let meal = meals[index]
            if meal.pct <= 0 { return nil }
            if superseded[index] { return mealTarget(daily: daily, pct: meal.pct) }
            if index == current { return currentTarget }
            return futurePct > 0
                ? futureBudget.scaled(Double(meal.pct) / Double(futurePct))
                : futureBudget
        }
    }
}
