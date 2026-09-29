import Foundation

/// Les fiches rangées par mois, sous un en-tête collant — celui du journal.
///
/// Seulement triées par date : rangées par distance ou par nom, deux sorties
/// voisines n'ont pas de mois en commun, et un en-tête par fiche ne dirait
/// rien.
enum ActivityMonths {
    struct Month<Row>: Identifiable {
        let id: String
        let title: String
        let rows: [Row]
    }

    /// Des mois consécutifs, dans l'ordre des lignes, qui doivent donc être
    /// triées par date — un mois qui reviendrait plus bas porterait le même
    /// identifiant que le premier.
    static func months<Row>(of rows: [Row], day: (Row) -> DateKey) -> [Month<Row>] {
        var months: [Month<Row>] = []
        var current: (key: String, date: DateKey, rows: [Row])?
        for row in rows {
            let date = day(row)
            let key = String(date.raw.prefix(7))
            if current?.key == key {
                current?.rows.append(row)
            } else {
                if let current { months.append(month(current)) }
                current = (key, date, [row])
            }
        }
        if let current { months.append(month(current)) }
        return months
    }

    private static func month<Row>(_ part: (key: String, date: DateKey, rows: [Row])) -> Month<Row> {
        Month(id: part.key, title: JournalRowLayout.monthTitle(part.date), rows: part.rows)
    }

    /// La ligne de l'`NSTableView` qui porte la `index`-ième sortie, en-têtes
    /// comptés — sans quoi `j` et `k` faisaient défiler vers la mauvaise fiche.
    static func tableRow<Row>(forRow index: Int, in rows: [Row], day: (Row) -> DateKey) -> Int {
        guard index >= 0, index < rows.count else { return index }
        var headers = 0
        var previous: Substring?
        for row in rows[...index] {
            let month = day(row).raw.prefix(7)
            if month != previous { headers += 1 }
            previous = month
        }
        return index + headers
    }
}

extension Activity {
    /// Le jour de la sortie là où elle a eu lieu : une course du soir à New
    /// York reste celle du 12.
    var localDay: DateKey {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return DateKey(startDate, calendar: calendar)
    }
}
