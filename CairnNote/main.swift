import AppKit
import Foundation
import SwiftData

// `cairn-note` — the day's note, in vim.
//
// The journal lives in the store, not in a folder of `.md` files any more, so
// this opens the very same SwiftData container the application opens, with the
// very same schema. That last point is not a detail: a partial schema would
// read as a migration, and SwiftData would set about rewriting 132 MB of
// irreplaceable data as a side effect of editing one note.
//
// Top-level code in `main.swift` runs on the main actor, which is what lets
// the recorder be started from here.

let toolName = "cairn-note"

/// The draft's directory, once there is one, so that leaving by any door
/// takes it with us.
///
/// A variable and an explicit sweep rather than a `defer`: top-level `defer`
/// does not run when the program leaves through `exit()`, and every ending
/// here but one does exactly that. Measured — two abandoned directories in
/// `/var/folders` after a run that said "inchangée" and one the editor left
/// on an error.
var draftFolder: URL?

@MainActor func sweep() {
    if let draftFolder { try? FileManager.default.removeItem(at: draftFolder) }
    draftFolder = nil
}

@MainActor func fail(_ message: String) -> Never {
    sweep()
    FileHandle.standardError.write(Data("\(toolName): \(message)\n".utf8))
    exit(1)
}

/// The other door out: says its piece, sweeps, and stops.
@MainActor func done(_ message: String) -> Never {
    sweep()
    print(message)
    exit(0)
}

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.contains(where: { $0 == "-h" || $0 == "--help" }) {
    print("""
    usage: \(toolName) [jour]

      (rien)       la note d'aujourd'hui
      2026-08-14   ce jour-là
      20260814     le même, sans les tirets
      -1  +3       en jours depuis aujourd'hui, signe compris

    La note s'ouvre dans $VISUAL, à défaut $EDITOR, à défaut nvim ou vim
    selon ce qui est installé. Un alias du shell n'est pas vu d'ici.

    Sortir sans rien changer n'écrit rien ; sortir en laissant la note vide
    la supprime.
    """)
    exit(0)
}

guard arguments.count <= 1 else {
    fail("un seul jour à la fois. « \(toolName) --help » pour les formats.")
}

// The guard, before anything is opened. The application keeps the note in
// memory and has no way of learning that another process has touched the
// base: a note written here while it runs would be invisible to it, then
// overwritten by the next keystroke. Refusing outright is the only honest
// answer — there is no merge to offer.
let bundleID = "com.florianmaisonnial.Cairn"
if !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
    fail("Cairn est ouvert. Ferme l'application avant d'écrire depuis le terminal.")
}

guard let date = JournalNoteDate.parse(arguments.first, today: DateKey(Date())) else {
    fail("« \(arguments.first ?? "") » n'est pas un jour. « \(toolName) --help » pour les formats.")
}

let container: ModelContainer
do {
    container = try AppModelContainer.make()
} catch {
    fail("base illisible : \(error.localizedDescription)")
}

// Without this the note would be written locally and never leave the Mac: the
// outbox is fed by an observer of `ModelContext.willSave`, and until now only
// the application installed one. Started before the context is touched.
let recorder = MirrorRecorder(container: container)
recorder.start()

let context = ModelContext(container)
let before = JournalNoteWrite.row(for: date, in: context)?.text ?? ""

// A directory of its own, so the file can keep the day as its name: vim shows
// it in the status line, and the `.md` turns the markdown syntax on.
let folder = URL.temporaryDirectory.appending(path: "\(toolName)-\(UUID().uuidString)")
let file = folder.appending(path: "\(date.raw).md")
do {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try before.write(to: file, atomically: true, encoding: .utf8)
} catch {
    fail("brouillon impossible à écrire : \(error.localizedDescription)")
}
draftFolder = folder

/// Whether a command exists on the PATH, which is the question the default
/// editor turns on.
@MainActor func isOnPath(_ command: String) -> Bool {
    let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
    return path.split(separator: ":").contains {
        FileManager.default.isExecutableFile(
            atPath: URL(filePath: String($0)).appending(path: command).path
        )
    }
}

// `$VISUAL` before `$EDITOR`, which is the convention and not a preference:
// both name an editor, but `VISUAL` is the one meant for a full-screen
// terminal, while `EDITOR` may name a line editor a script can drive.
//
// The fallback asks the PATH rather than naming `vim` outright. A shell alias
// is invisible from here — `alias vim=nvim` is a rule of the interactive
// shell, and nothing spawned by another program ever sees it — so a Mac where
// nvim is installed is a Mac where "vim" almost certainly meant nvim. Note
// that this only decides when *neither* variable is set: someone who exports
// `EDITOR=vim` is asking for vim, and gets it.
//
// Split on spaces, so a setting like `nvim -p` still works.
let environment = ProcessInfo.processInfo.environment
let asked = (environment["VISUAL"] ?? environment["EDITOR"] ?? "")
    .trimmingCharacters(in: .whitespaces)
let editor = asked.isEmpty ? (isOnPath("nvim") ? "nvim" : "vim") : asked
let words = editor.split(separator: " ").map(String.init)

/// Runs the editor on `path` and gives back its exit code, or nil when it was
/// killed rather than finished.
///
/// `posix_spawn` bare — no file actions, no attributes — and **not**
/// `Foundation.Process`, which is the whole point of the function existing.
/// `Process` sets `POSIX_SPAWN_SETPGROUP` and puts the child in a process
/// group of its own; measured on 31 August 2026, parent group 63770 against
/// child group 63774. That group is not the terminal's foreground one, so a
/// full-screen editor never gets the screen: vim opened on a blank terminal,
/// the keystrokes meant for it were echoed by the shell instead, and leaving
/// killed it with SIGHUP. Spawning without those attributes leaves the child
/// in our group — the foreground one — and it inherits the three standard
/// descriptors, which is all vim asks for.
///
/// `posix_spawnp`, with a `p`: `$EDITOR` names a command, and whichever vim
/// is on the PATH is the one meant.
@MainActor func runEditor(_ words: [String], on path: String) -> Int32? {
    var argv: [UnsafeMutablePointer<CChar>?] = (words + [path]).map { strdup($0) }
    argv.append(nil)
    defer { for argument in argv { free(argument) } }

    var pid: pid_t = 0
    guard posix_spawnp(&pid, words[0], nil, nil, &argv, environ) == 0 else {
        return nil
    }

    var raw: Int32 = 0
    while waitpid(pid, &raw, 0) == -1 {
        // A signal delivered to us while waiting is not the editor finishing.
        guard errno == EINTR else { return nil }
    }
    // `WIFEXITED` and `WEXITSTATUS` are C macros with no Swift counterpart:
    // the low seven bits hold the signal that killed the child, zero meaning
    // it left on its own, and the next eight its exit code.
    guard raw & 0x7f == 0 else { return nil }
    return (raw >> 8) & 0xff
}

let editorStatus = runEditor(words, on: file.path(percentEncoded: false))

guard let editorStatus else {
    fail("« \(words.joined(separator: " ")) » n'a pas pu être lancé, ou s'est arrêté brutalement ; rien n'a été écrit.")
}
guard editorStatus == 0 else {
    fail("l'éditeur s'est arrêté sur une erreur ; rien n'a été écrit.")
}

guard let after = try? String(contentsOf: file, encoding: .utf8) else {
    fail("brouillon illisible en retour ; rien n'a été écrit.")
}

guard after != before else {
    done("\(date.raw) : inchangée.")
}

let outcome = JournalNoteWrite.apply(after, for: date, in: context)
do {
    try context.save()
} catch {
    fail("écriture refusée : \(error.localizedDescription)")
}

switch outcome {
case .created: done("\(date.raw) : note créée.")
case .updated: done("\(date.raw) : note mise à jour.")
case .deleted: done("\(date.raw) : note supprimée.")
case .nothing: done("\(date.raw) : rien à garder.")
}
