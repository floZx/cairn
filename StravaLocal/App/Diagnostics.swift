import Foundation

/// Opt-in diagnostics, off unless an environment variable asks for them.
///
/// Exists because some layout behaviour can only be observed by running the
/// app: writing what a probe actually found beats guessing at it. Left in
/// place rather than added and removed each time the question comes back.
enum Diagnostics {
    /// Set `STRAVALOCAL_DEBUG=splitview` to see what the split-view probe finds.
    private static let enabled: Set<String> = {
        guard let value = ProcessInfo.processInfo.environment["STRAVALOCAL_DEBUG"] else {
            return []
        }
        return Set(value.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) })
    }()

    static func splitView(_ message: @autoclosure () -> String) {
        log(topic: "splitview", message())
    }

    private static func log(topic: String, _ message: String) {
        guard enabled.contains(topic) else { return }
        FileHandle.standardError.write(Data("[\(topic)] \(message)\n".utf8))
    }
}
