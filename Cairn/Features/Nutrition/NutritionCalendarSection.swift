import SwiftUI
import SwiftData

/// The food journal's calendar, for the sidebar.
///
/// A view of its own rather than a `@Query` on `SidebarView`: the sidebar is on
/// screen in every section, and a query there would fetch every food entry ever
/// logged while one browses activities. Held here, the fetch exists only while
/// the food journal is the section showing — SwiftUI never builds this view
/// otherwise, so the query never runs.
struct NutritionCalendarSection: View {
    @Binding var selected: DateKey

    @Query private var entries: [FoodEntry]

    /// The days that have something logged. Only the dates are read, so this
    /// deliberately does not go through `NutritionSidePanelModel.compute`,
    /// which also averages macros and fits a weight trend — work the calendar
    /// has no use for.
    private var loggedDays: Set<String> {
        Set(entries.map(\.dateKeyRaw))
    }

    var body: some View {
        MiniCalendarView(selected: $selected, loggedDays: loggedDays)
    }
}
