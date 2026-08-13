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
/// The picker's own value, so the sheet computes a portion with the same
/// arithmetic as everything that stores one.
extension FoodPick: FoodPortion {}

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

    /// Each macro at the unit, which is how every one of them is written.
    ///
    /// Summed from these rather than from the decimals behind them, a column
    /// of figures adds up to the total printed under it. It did not: seven
    /// rows of a meal read 24, 1, 5, 3, 19, 13, 0 — sixty-five — under a
    /// heading saying 64, because the heading was the rounded sum of numbers
    /// nobody could see. Reported 13 August 2026.
    ///
    /// The same choice `overshoot` makes for its colours, and for the same
    /// reason: a screen that disagrees with itself reads as a bug, and here it
    /// was one.
    func rounded() -> Macros {
        Macros(
            kcal: kcal.rounded(), protein: protein.rounded(),
            carbs: carbs.rounded(), fat: fat.rounded()
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
    /// still fine, a heavy one is not.
    enum Overshoot {
        case moderate
        case heavy
    }

    /// How much a target may be passed by before anything is said.
    ///
    /// A gram over 149 is not an overshoot, it is the same meal weighed twice.
    /// Two per cent covers the large targets — a day of 2400 kcal is not blown
    /// by 48 — and two units cover the small ones, where two per cent of 18 g
    /// would be a fifth of a gram and the colour would fire on any rounding.
    ///
    /// Both nudged the same way: what the reader sees turn orange should be
    /// something they would themselves call "over".
    static func tolerance(for target: Double) -> Double {
        max(target * 0.02, 2)
    }

    /// Judged on the figures as displayed, not on what is behind them.
    ///
    /// Every macro in the journal is written to the unit, so a rule reading
    /// the decimals contradicts the screen: 33.4 against a target of 32.8 is
    /// genuinely over, and used to come out orange — under the label "33/33".
    /// A colour that disagrees with its own number reads as a bug, and it
    /// was one. Rounding first also subsumes the half-gram slack ported from
    /// suivinut, which only ever guarded the same crumb from one side.
    ///
    /// Both bands are shifted by the tolerance rather than only the first:
    /// otherwise a small target would jump straight from green to red, its
    /// grace having already passed the ten-per-cent mark.
    static func overshoot(consumed: Double, target: Double) -> Overshoot? {
        guard target > 0 else { return nil }
        let shownConsumed = consumed.rounded()
        let shownTarget = target.rounded()
        let grace = tolerance(for: shownTarget)
        guard shownConsumed > shownTarget + grace else { return nil }
        return shownConsumed > shownTarget * 1.10 + grace ? .heavy : .moderate
    }

    /// Whether a meal has landed on its plan: nine tenths of the target, and
    /// not past it.
    ///
    /// The counterpart of `overshoot`, and its opposite in spirit. Overshooting
    /// is the thing to warn about; this is the thing to say well done for, and
    /// a journal that only ever colours a figure to scold is a journal one
    /// stops reading. Ninety per cent rather than a hundred because a meal is
    /// planned, not weighed to the gram: landing within a tenth of the plan is
    /// hitting it.
    ///
    /// Judged on the rounded figures, like `overshoot` and for the same
    /// reason: a colour that disagrees with the number it sits on reads as a
    /// bug, and once was one.
    static func isOnTarget(consumed: Double, target: Double) -> Bool {
        guard target > 0 else { return false }
        let shownConsumed = consumed.rounded()
        let shownTarget = target.rounded()
        // Up to the tolerance above it as well: a gram past a target one was
        // aiming at is still having hit it, and `overshoot` says nothing about
        // that gram either — the two share one rule so the screen cannot show
        // a figure that is neither on target nor over it.
        return shownConsumed >= shownTarget * 0.90
            && shownConsumed <= shownTarget + tolerance(for: shownTarget)
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

    /// Which meals are finished: a meal is, as soon as a later one has been
    /// started.
    ///
    /// Named and shared rather than inlined where it is used: the targets
    /// below depend on it, and so does what the screen *says* a target is —
    /// a finished meal shows its share of the plan, the others show what is
    /// left. Two readings of the same rule would eventually disagree.
    static func superseded(in meals: [MealState]) -> [Bool] {
        (0..<meals.count).map { index in
            meals[(index + 1)...].contains { $0.started }
        }
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
        let superseded = superseded(in: meals)
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
