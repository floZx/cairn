import Foundation

/// What a row of the journal list says, and where it sits — kept apart from
/// the drawing so it can be checked.
///
/// The list used to put the weight in the wrong place: the long date in bold,
/// the same on every row, and what was written in grey under it. The date is
/// now a small tile at the left, the month said once per section, and the
/// words lead: the first sentence in the text colour, the rest after it in
/// secondary, one paragraph of three lines at most.
enum JournalRowLayout {
    /// The first sentence and what follows it.
    struct Preview: Equatable {
        var lead: String
        var rest: String
    }

    /// The row's text: the day's note if it has one, otherwise the first thing
    /// written elsewhere that day, led by whose it is — « 8x30″/30″ » then
    /// « 3:50/km ».
    static func preview(of day: JournalDay, matching query: String = "") -> Preview {
        if !query.isEmpty, let passage = day.excerpt(matching: query) {
            return split(passage)
        }
        if !day.note.isEmpty {
            return split(prose(of: day.note.text))
        }
        guard let first = day.elsewhereNotes.first else { return Preview(lead: "", rest: "") }
        let said = prose(of: first)
        if let source = day.elsewhereSources.first, !source.isEmpty {
            return Preview(lead: source, rest: said)
        }
        return split(said)
    }

    /// A note's words as one running paragraph: blocks joined, markers gone,
    /// pictures left out. Capped well past what three lines can show.
    static func prose(of text: String) -> String {
        let words = MarkdownParser.blocks(from: JournalFileNote.body(of: text))
            .compactMap { block -> String? in
                if case .image = block { return nil }
                let said = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return said.isEmpty ? nil : said
            }
            .joined(separator: " ")
        return String(words.prefix(400))
    }

    /// The first sentence — up to a `.`, `!`, `?` or `…` followed by a space —
    /// and the rest. A text that is one sentence is all lead.
    static func split(_ text: String) -> Preview {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var index = trimmed.startIndex
        while index < trimmed.endIndex {
            let next = trimmed.index(after: index)
            if ".!?…".contains(trimmed[index]), next < trimmed.endIndex, trimmed[next].isWhitespace {
                return Preview(
                    lead: String(trimmed[...index]),
                    rest: trimmed[next...].trimmingCharacters(in: .whitespaces)
                )
            }
            index = next
        }
        return Preview(lead: trimmed, rest: "")
    }

    // MARK: - Months

    /// The days grouped by month, in the order they come — newest first.
    struct Month: Identifiable, Equatable {
        let id: String
        let title: String
        let days: [JournalDay]
    }

    static func months(of days: [JournalDay]) -> [Month] {
        var months: [Month] = []
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "LLLL yyyy"
        for day in days {
            let key = String(day.date.raw.prefix(7))
            if months.last?.id == key {
                let last = months.removeLast()
                months.append(Month(id: key, title: last.title, days: last.days + [day]))
            } else {
                months.append(Month(
                    id: key, title: formatter.string(from: day.date.date()).uppercased(), days: [day]
                ))
            }
        }
        return months
    }

    /// Where a day sits in the list's `NSTableView`, whose rows include one
    /// header per month: the tenth day is no longer the tenth row, and the
    /// keyboard's scrolling and the row remeasuring both speak in rows.
    static func tableRow(forDay index: Int, in days: [JournalDay]) -> Int {
        guard index >= 0, index < days.count else { return index }
        var headers = 0
        var previous: Substring?
        for day in days[...index] {
            let month = day.date.raw.prefix(7)
            if month != previous { headers += 1 }
            previous = month
        }
        return index + headers
    }

    static func tableRows(forDays indexes: IndexSet, in days: [JournalDay]) -> IndexSet {
        IndexSet(indexes.map { tableRow(forDay: $0, in: days) })
    }

    // MARK: - Tile

    /// « SAM » and « 26 » — the day of the week shortened, and its number.
    static func tile(for date: DateKey) -> (weekday: String, day: String) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEE"
        let weekday = formatter.string(from: date.date())
            .replacingOccurrences(of: ".", with: "")
            .uppercased()
        let day = String(Int(date.raw.suffix(2)) ?? 0)
        return (weekday, day)
    }

    // MARK: - Detail heading

    /// « Samedi 26 septembre » — the pane's title; the year goes under it.
    static func title(for date: DateKey) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM"
        let text = formatter.string(from: date.date())
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// « 2026 · aujourd'hui · 2 activités » — the year, how long ago in the
    /// words the activity list uses, and how many outings, when there are any.
    static func subtitle(for date: DateKey, activities: Int, today: DateKey = DateKey(Date())) -> String {
        var parts = [String(date.raw.prefix(4))]
        if let relative = relative(date, today: today) { parts.append(relative) }
        if activities > 0 { parts.append(activities == 1 ? "1 activité" : "\(activities) activités") }
        return parts.joined(separator: " · ")
    }

    /// Aujourd'hui, hier, the weekday within the week; nothing further back,
    /// where the title's date already says it all.
    static func relative(_ date: DateKey, today: DateKey) -> String? {
        let calendar = Calendar(identifier: .gregorian)
        guard let days = calendar.dateComponents([.day], from: date.date(), to: today.date()).day
        else { return nil }
        switch days {
        case 0: return "aujourd'hui"
        case 1: return "hier"
        case 2...6:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "fr_FR")
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date.date())
        default: return nil
        }
    }
}
