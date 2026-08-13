import Foundation

/// The book, as one self-contained HTML document.
///
/// A pure function from a `JournalBook` to a string: no view, no network, no
/// file. That is what lets the whole appearance of the export be tested — what
/// appears, what is left out, what is escaped — without rendering anything.
///
/// The images are handed in rather than fetched, keyed by the outing they
/// illustrate. An outing with no entry writes no image, which is exactly what
/// an export made offline looks like.
@MainActor
enum JournalBookHTML {
    struct Illustrations {
        /// A `data:` URI, or an inline `<svg>` when no map could be had.
        var map: String?
        var charts: [String]
        var photos: [String]

        init(map: String? = nil, charts: [String] = [], photos: [String] = []) {
            self.map = map
            self.charts = charts
            self.photos = photos
        }
    }

    /// - Parameter noteImages: what a picture written in a note resolves to.
    ///   Empty when the vault could not be read, which the notes then say in
    ///   words rather than in empty frames.
    static func document(
        _ book: JournalBook, illustrations: [Int64: Illustrations],
        noteImages: [String: String] = [:]
    ) -> String {
        let title = "Carnet — \(Format.dateOnly(book.from.date())) au "
            + Format.dateOnly(book.to.date())
        return """
            <!DOCTYPE html>
            <html lang="fr"><head><meta charset="utf-8">\
            <title>\(escape(title))</title><style>\(stylesheet)</style></head>\
            <body>\(cover(book))\
            \(book.days.map { day($0, illustrations: illustrations, noteImages: noteImages) }.joined())\
            </body></html>
            """
    }

    // MARK: - La couverture

    private static func cover(_ book: JournalBook) -> String {
        let totals = book.totals
        var figures = [
            ("Sorties", "\(totals.activityCount)"),
            ("Distance", Format.distance(totals.distance)),
            ("Dénivelé +", Format.elevation(totals.elevation)),
            ("Temps", Format.duration(totals.movingTime)),
        ]
        // A book of a month with no outing at all is a book of notes, and a row
        // of zeroes on its cover says only that the figures were printed.
        if totals.activityCount == 0 { figures = [] }

        let sports = totals.bySport.map { entry in
            "<li><span class=\"sport\">\(escape(entry.sport.displayName))</span> "
                + "\(entry.count) · \(Format.distance(entry.distance))</li>"
        }.joined()

        var weight = ""
        if let first = totals.firstWeightKg, let last = totals.lastWeightKg {
            weight = "<p class=\"weight\">\(Format.typedNumber(first)) kg → "
                + "\(Format.typedNumber(last)) kg</p>"
        }

        return """
            <section class="cover"><h1>Carnet</h1>\
            <p class="period">Du \(escape(Format.dateOnly(book.from.date()))) \
            au \(escape(Format.dateOnly(book.to.date())))</p>\
            \(definitionList(figures, class: "totals"))\
            \(sports.isEmpty ? "" : "<ul class=\"sports\">\(sports)</ul>")\
            \(weight)</section>
            """
    }

    // MARK: - Une journée

    private static func day(
        _ day: JournalBook.Day, illustrations: [Int64: Illustrations],
        noteImages: [String: String]
    ) -> String {
        let note = MarkdownHTML.render(day.note, images: noteImages)
        let tags = day.tags.map { "<li>\(escape($0.name))</li>" }.joined()
        let outings = day.activities
            .map { activity($0, illustrations: illustrations[$0.stravaID]) }
            .joined()

        return """
            <section class="day"><h2>\
            \(escape(Format.fullDate(day.date.date())))</h2>\
            \(note.isEmpty ? "" : "<div class=\"note\">\(note)</div>")\
            \(tags.isEmpty ? "" : "<ul class=\"tags\">\(tags)</ul>")\
            \(outings)\(food(day))</section>
            """
    }

    // MARK: - Une sortie

    private static func activity(
        _ activity: Activity, illustrations: Illustrations?
    ) -> String {
        var figures: [(String, String)] = [
            ("Distance", Format.distance(activity.distance)),
            ("Temps", Format.duration(activity.movingTime)),
        ]
        if activity.totalElevationGain > 0 {
            figures.append(("D+", Format.elevation(activity.totalElevationGain)))
        }
        if activity.averageSpeed > 0 {
            figures.append(
                (
                    speedLabel(for: activity.sportType),
                    Format.speed(activity.averageSpeed, sport: activity.sportType)
                )
            )
        }
        if let heartrate = activity.averageHeartrate, heartrate > 0 {
            figures.append(("FC moy.", Format.heartrate(heartrate)))
        }
        if let cadence = activity.averageCadence, cadence > 0 {
            figures.append(
                ("Cadence", Format.cadence(cadence, sport: activity.sportType))
            )
        }

        let charts = (illustrations?.charts ?? [])
            .map { "<figure class=\"chart\">\(image($0))</figure>" }
            .joined()
        let photos = (illustrations?.photos ?? [])
            .map { "<figure class=\"photo\">\(image($0))</figure>" }
            .joined()
        let map = illustrations?.map.map {
            "<figure class=\"map\">\(image($0))</figure>"
        } ?? ""
        let note = MarkdownHTML.render(
            activity.activityDescription?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )

        return """
            <article class="activity"><header>\
            <span class="time">\
            \(escape(Format.time(activity.startDate, in: activity.timeZone)))</span> \
            <span class="sport">\(escape(activity.sportType.displayName))</span> \
            <span class="name">\(escape(activity.name))</span></header>\
            \(map)\(definitionList(figures, class: "figures"))\(charts)\(photos)\
            \(note.isEmpty ? "" : "<div class=\"note\">\(note)</div>")</article>
            """
    }

    /// Runners read a pace, cyclists a speed — the same split
    /// `Format.speed(_:sport:)` makes. Change one and read the other.
    private static func speedLabel(for sport: SportType) -> String {
        switch sport {
        case .run, .trailRun, .walk, .hike, .swim: "Allure"
        default: "Vitesse"
        }
    }

    // MARK: - Alimentation et poids

    private static func food(_ day: JournalBook.Day) -> String {
        var weight = ""
        if let kilograms = day.weightKg {
            let note = day.weightNote.map { " — \(escape($0))" } ?? ""
            weight = "<p class=\"weight\">\(Format.typedNumber(kilograms)) kg\(note)</p>"
        }
        let meals = day.meals.map { meal in
            let macros = "\(Int(meal.kcal.rounded())) kcal · "
                + "\(Int(meal.protein.rounded())) P · "
                + "\(Int(meal.carbs.rounded())) G · "
                + "\(Int(meal.fat.rounded())) L"
            let note = meal.note.map {
                " <span class=\"note\">\(escape($0))</span>"
            } ?? ""
            return "<li><span class=\"meal\">\(escape(meal.name))</span> "
                + "<span class=\"macros\">\(macros)</span>\(note)</li>"
        }.joined()

        guard !weight.isEmpty || !meals.isEmpty else { return "" }
        return "<section class=\"food\">\(weight)"
            + (meals.isEmpty ? "" : "<ul class=\"meals\">\(meals)</ul>")
            + "</section>"
    }

    // MARK: - Les petites briques

    /// An `<img>` for a `data:` URI, the SVG itself when the map came out as
    /// vector. Never an empty `src`: a missing image writes nothing at all.
    private static func image(_ source: String) -> String {
        guard !source.isEmpty else { return "" }
        return source.hasPrefix("<svg") ? source : "<img src=\"\(source)\" alt=\"\">"
    }

    private static func definitionList(
        _ figures: [(String, String)], class name: String
    ) -> String {
        guard !figures.isEmpty else { return "" }
        let items = figures.map { label, value in
            "<div><dt>\(escape(label))</dt><dd>\(escape(value))</dd></div>"
        }.joined()
        return "<dl class=\"\(name)\">\(items)</dl>"
    }

    private static func escape(_ text: String) -> String {
        MarkdownHTML.escape(text)
    }

    // MARK: - La feuille de style

    /// Where the book's looks live. Changing them means changing this string,
    /// and nothing else — which is why the export offers no appearance setting.
    ///
    /// The page breaks are stated here rather than computed anywhere: a day may
    /// be cut between two outings, never in the middle of one, and never across
    /// a map or a photo.
    private static let stylesheet = """
        @page { size: A4; margin: 18mm 16mm; }
        * { box-sizing: border-box; }
        body {
          font: 11pt/1.5 -apple-system, "Helvetica Neue", sans-serif;
          color: #1c1c1e; margin: 0;
        }
        h1, h2, h3 { font-weight: 600; margin: 0 0 .4em; }
        .day { break-after: page; }
        .day:last-child { break-after: auto; }
        .activity, figure, .food, .cover { break-inside: avoid; }
        .cover { height: 100%; break-after: page; }
        .cover h1 { font-size: 34pt; letter-spacing: -.5pt; }
        .cover .period { font-size: 13pt; color: #6c6c70; margin-bottom: 2em; }
        .day > h2 {
          font-size: 17pt; border-bottom: 1px solid #d8d8dc;
          padding-bottom: .3em; margin-bottom: .8em;
        }
        .note { margin: .6em 0; }
        .note p { margin: 0 0 .5em; }
        .note blockquote {
          margin: .5em 0; padding-left: .8em; border-left: 2px solid #d8d8dc;
          color: #6c6c70; font-style: italic;
        }
        .tags { list-style: none; padding: 0; margin: .2em 0 1em; }
        .tags li {
          display: inline-block; font-size: 8.5pt; color: #6c6c70;
          background: #f2f2f7; border-radius: 9pt; padding: 1pt 7pt;
          margin-right: 4pt;
        }
        .activity {
          margin: 1em 0; padding: .8em 1em; background: #f7f7f9;
          border-radius: 6pt;
        }
        .activity header { display: flex; gap: .6em; align-items: baseline; }
        .activity .time { font-variant-numeric: tabular-nums; color: #6c6c70; }
        .activity .name { font-weight: 600; }
        .sport { color: #6c6c70; }
        figure { margin: .7em 0; }
        figure img, figure svg {
          width: 100%; height: auto; border-radius: 4pt; display: block;
        }
        figure.photo img { max-height: 90mm; object-fit: cover; }
        dl.figures, dl.totals {
          display: flex; flex-wrap: wrap; gap: .2em 1.6em; margin: .6em 0;
        }
        dl dt { font-size: 8.5pt; color: #6c6c70; }
        dl dd { margin: 0; font-variant-numeric: tabular-nums; }
        dl.totals dd { font-size: 15pt; }
        .sports, .meals { list-style: none; padding: 0; margin: .4em 0; }
        .meals li { margin: .2em 0; }
        .meals .macros { font-variant-numeric: tabular-nums; color: #6c6c70; }
        .food .weight { font-variant-numeric: tabular-nums; }
        figure.note-photo { margin: .7em 0; break-inside: avoid; }
        figure.note-photo img {
          width: 100%; height: auto; border-radius: 4pt; display: block;
        }
        .missing-photo { color: #6c6c70; font-style: italic; }
        """
}
