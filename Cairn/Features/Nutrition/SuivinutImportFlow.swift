// Cairn/Features/Nutrition/SuivinutImportFlow.swift
import SwiftUI
import SwiftData
import AppKit

/// The one import flow both entry points share (onboarding banner and the
/// settings tab): pick the journal, import on a context of its own, apply
/// the journal's targets, copy the sibling catalog. Returns the message the
/// caller shows in its alert.
@MainActor
enum SuivinutImportFlow {
    static func chooseAndImport(container: ModelContainer) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choisir le journal.db de suivinut"
        let iCloudFolder = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Mobile Documents/com~apple~CloudDocs/suivinut")
        if FileManager.default.fileExists(atPath: iCloudFolder.path) {
            panel.directoryURL = iCloudFolder
        }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return importJournal(from: url, container: container)
    }

    static func importJournal(
        from url: URL, container: ModelContainer
    ) -> String {
        // A context of its own: `run` rolls back on failure, and rolling
        // back a shared context would discard unrelated pending edits. The
        // cross-context @Query refresh was verified live in phase 3.
        let importContext = ModelContext(container)
        do {
            let summary = try SuivinutImporter(context: importContext)
                .run(journalPath: url.path)
            let defaults = UserDefaults.standard
            if let value = summary.proteinTargetG {
                defaults.set(value, forKey: NutritionSettings.proteinTargetKey)
            }
            if let value = summary.fatTargetG {
                defaults.set(value, forKey: NutritionSettings.fatTargetKey)
            }
            if let value = summary.weightGoalKg {
                defaults.set(value, forKey: NutritionSettings.weightGoalKey)
            }
            _ = try? SuivinutImporter.copyCatalog(
                nextTo: url,
                to: URL.applicationSupportDirectory.appending(path: "Cairn")
            )
            return "\(summary.entries) aliments, \(summary.weights) pesées et "
                + "\(summary.recipes) recettes importés."
        } catch {
            return "L'import a échoué : \(error.localizedDescription) "
                + "Rien n'a été modifié."
        }
    }
}
