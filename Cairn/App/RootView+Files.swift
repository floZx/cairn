import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// Files in and out: GPX, the journal's pictures, the journal as a PDF book.
extension RootView {
    func chooseGPXFilesToImport() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [Self.gpxType]
        panel.prompt = "Importer"
        panel.message = "Choisissez un ou plusieurs fichiers GPX à ajouter au journal"
        guard panel.runModal() == .OK else { return }
        importGPX(from: panel.urls)
    }

    /// Imports every chosen file, keeping the ones that worked.
    ///
    /// One bad file among ten does not cancel the other nine: the failures are
    /// listed by name at the end instead. Selecting what came in is what makes
    /// an import visible — otherwise the rows land somewhere in 840 others.
    func importGPX(from urls: [URL]) {
        let importer = GPXImporter(context: modelContext)
        var imported: [Activity] = []
        var failures: [String] = []

        for url in urls {
            do {
                let track = try GPXParser.parse(data: try Data(contentsOf: url))
                imported.append(
                    try importer.import(
                        track,
                        fallbackName: url.deletingPathExtension().lastPathComponent
                    )
                )
            } catch {
                failures.append("\(url.lastPathComponent) : \(error.localizedDescription)")
            }
        }

        if !imported.isEmpty {
            do {
                try modelContext.save()
                selectedActivities = Set(imported.map(\.id))
                hasAutoSelected = true
            } catch {
                failures.append(
                    "L'enregistrement a échoué : \(error.localizedDescription)"
                )
            }
        }
        fileMessage = Self.importReport(imported: imported.count, failures: failures)
    }

    /// What to tell the user afterwards, or nil when everything worked and the
    /// new rows on screen already say so.
    static func importReport(imported: Int, failures: [String]) -> String? {
        guard !failures.isEmpty else { return nil }
        let head = imported == 0
            ? "Aucun fichier n'a pu être importé."
            : "\(imported) activité\(imported > 1 ? "s importées" : " importée"), les autres non :"
        return ([head] + failures).joined(separator: "\n")
    }

    /// Writes the book: gather, draw, paginate, save.
    ///
    /// The order matters. The days are gathered first so an empty period can be
    /// refused before anything slow starts — and before a save panel asks where
    /// to put a PDF that would hold nothing but its cover.
    /// Takes each picture into the journal and appends its link to the note.
    ///
    /// Through the store, which owns the bytes, the cache and the text alike:
    /// this view only says which files were dropped, and hears back which of
    /// them were refused.
    func addJournalPhotos(_ urls: [URL], to date: DateKey) {
        let refused = app.journal.addAttachments(from: urls, to: date)
        guard !refused.isEmpty else { return }
        // Named rather than dropped in silence: a file one believes was added
        // is worse than one that says why it was not.
        fileMessage = refused.count == 1
            ? "« \(refused[0]) » n'a pas pu être ajouté : seules les images "
                + "JPEG, PNG et HEIC entrent dans une note."
            : "Ces fichiers n'ont pas pu être ajoutés : "
                + refused.joined(separator: ", ")
    }

    /// The same from the clipboard, which carries bytes and no name.
    func pasteJournalPhoto(_ data: Data, to date: DateKey) {
        guard !app.journal.addAttachment(data, to: date) else { return }
        fileMessage = "La photo collée n'a pas pu être ajoutée à la note."
    }

    func exportJournalPDF() async {
        let from = journalExportFrom
        let to = journalExportTo
        let book = JournalBook.build(
            from: from, to: to, notes: app.journal.notes,
            activities: allActivities, entries: foodEntries, slots: mealSlots,
            mealNotes: mealNotes, weights: weightEntries
        )
        guard !book.days.isEmpty else {
            showsJournalExport = false
            fileMessage = "Aucune journée à exporter sur cette période."
            return
        }

        journalExportProgress = .drawing(done: 0, total: 1)
        let illustrations = await JournalBookAssets.illustrations(for: book) {
            done, total in
            journalExportProgress = .drawing(done: done, total: total)
        }

        // The pictures written in the notes themselves, read from the cache
        // the store materialises them into.
        let noteImages = JournalBookAssets.noteImages(
            for: book, vault: app.journal.attachmentsBase
        ) { done, total in
            journalExportProgress = .drawing(done: done, total: total)
        }

        do {
            // Said out loud, because it is the phase nobody expects: every
            // picture is drawn and WebKit still has a book to paginate.
            journalExportProgress = .layingOut
            let data = try await JournalBookExporter.pdf(
                from: JournalBookHTML.document(
                    book, illustrations: illustrations, noteImages: noteImages
                )
            )
            journalExportProgress = nil
            showsJournalExport = false

            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = "Carnet \(from.raw) — \(to.raw).pdf"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url)
        } catch {
            journalExportProgress = nil
            showsJournalExport = false
            writeFailureMessage =
                "Le carnet n'a pas pu être écrit. \(error.localizedDescription)"
        }
    }

    func exportGPX(_ activities: [Activity]) {
        guard !activities.isEmpty else { return }
        if let single = activities.count == 1 ? activities.first : nil {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [Self.gpxType]
            panel.nameFieldStringValue = GPXWriter.fileName(for: single)
            guard panel.runModal() == .OK, let url = panel.url else { return }
            write([single], into: url.deletingLastPathComponent(), names: [url.lastPathComponent])
            return
        }
        // Several at once go to a folder: a save panel per activity would mean
        // twenty dialogs for twenty rows.
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Exporter"
        panel.message = "Choisissez le dossier où écrire les \(activities.count) fichiers GPX"
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        write(activities, into: directory, names: activities.map(GPXWriter.fileName(for:)))
    }

    func write(_ activities: [Activity], into directory: URL, names: [String]) {
        var failures: [String] = []
        for (activity, name) in zip(activities, names) {
            do {
                try GPXWriter.document(for: activity)
                    .write(to: directory.appending(path: name), atomically: true, encoding: .utf8)
            } catch {
                failures.append("\(name) : \(error.localizedDescription)")
            }
        }
        if !failures.isEmpty {
            fileMessage = (["Certains fichiers n'ont pas pu être écrits :"] + failures)
                .joined(separator: "\n")
        }
    }

    /// `.gpx` is not a system-declared type, so it is built from the extension;
    /// `.xml` is the honest fallback, since a GPX is one.
    static let gpxType = UTType(filenameExtension: "gpx") ?? .xml
}
