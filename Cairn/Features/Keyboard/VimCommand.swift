import Foundation

/// What a key sequence means, once resolved.
enum VimCommand: Equatable, Sendable {
    /// Relative move in the list; negative goes up.
    case move(Int)
    case first
    case last
    /// Half a screen, the way `⌃d` and `⌃u` do it: the caller knows how many
    /// rows fit, which this layer deliberately does not.
    case halfPage(down: Bool)
    case openSearch
    /// Escape: drop the search text if there is any, otherwise the selection.
    case clear
    case section(SidebarItem)
    case edit
    case delete
    case toggleFavorite
    case expandMap
    /// Close the detail pane. Distinct from `.clear`, which peels the search
    /// first: `h` has one meaning and no order of operations.
    case closePane
    case showHelp
}

/// Resolves keystrokes into commands, holding the state a modal editor needs.
///
/// Two things make this worth having on its own rather than inline in a view:
/// counts (`5j`) and prefixes (`gg`, `gm`) are *state*, and state that lives in
/// a key handler is state nothing can test. Everything here is a value.
///
/// Digits are counts, as in vim, which is why sections are reached with `g`
/// rather than with `1`, `2`, `3`: `2j` has to mean two rows down and cannot
/// also mean "go to the map".
struct VimKeyBuffer: Equatable {
    /// The count typed so far, or nil when none is pending.
    private(set) var count: Int?
    /// Whether `g` is waiting for its second key.
    private(set) var awaitingG = false

    /// A guard against `999999999j` overflowing, and against a stray lean on a
    /// digit key turning into a move nothing can undo.
    static let maximumCount = 9_999

    var isEmpty: Bool { count == nil && !awaitingG }

    /// Drops any half-typed sequence. Escape does this before anything else, so
    /// a mistyped prefix is never left armed for the next keystroke.
    mutating func reset() {
        count = nil
        awaitingG = false
    }

    /// - Parameters:
    ///   - key: the character typed, already lowercased by the caller only when
    ///     shift was not held — `G` and `g` are different commands.
    /// - Returns: the command to run, or nil when the sequence is incomplete.
    mutating func accept(_ key: Character, control: Bool = false) -> VimCommand? {
        if control {
            let pending = takeCount()
            _ = pending
            switch key {
            case "d": return .halfPage(down: true)
            case "u": return .halfPage(down: false)
            default: return nil
            }
        }

        if awaitingG {
            awaitingG = false
            let repeated = takeCount()
            _ = repeated
            switch key {
            case "g": return .first
            case "a": return .section(.all)
            case "m": return .section(.globalMap)
            case "s": return .section(.statistics)
            // An unknown second key cancels rather than falling through to the
            // one-key table: `gz` must not quietly behave like `z`.
            default: return nil
            }
        }

        if let digit = key.wholeNumberValue, digit >= 0, digit <= 9 {
            // A leading zero is not a count — in vim it is a motion of its own —
            // so it only counts once a number is under way.
            if digit == 0, count == nil { return nil }
            count = min((count ?? 0) * 10 + digit, Self.maximumCount)
            return nil
        }

        switch key {
        case "j": return .move(takeCount() ?? 1)
        case "k": return .move(-(takeCount() ?? 1))
        case "g":
            awaitingG = true
            return nil
        case "G":
            _ = takeCount()
            return .last
        case "/":
            reset()
            return .openSearch
        case "e": _ = takeCount(); return .edit
        case "x": _ = takeCount(); return .delete
        case "f": _ = takeCount(); return .toggleFavorite
        case "o": _ = takeCount(); return .expandMap
        // Left, as in vim: the pane on the right goes away.
        case "h": _ = takeCount(); return .closePane
        case "?": reset(); return .showHelp
        default:
            // Anything unrecognised clears the pending state. Leaving a count
            // armed across an unknown key is how `3` followed by a typo becomes
            // a three-row jump on the next `j`.
            reset()
            return nil
        }
    }

    private mutating func takeCount() -> Int? {
        defer { count = nil }
        return count
    }
}

/// Where a motion lands in a list of `count` rows.
///
/// Clamping rather than wrapping: `G` then `j` should stay on the last row, not
/// jump back to the top — a list that loops silently loses your place.
enum VimMotion {
    /// Rows a half-page motion covers.
    ///
    /// A fixed number rather than the visible height: the table does not publish
    /// how many rows it shows, and a half-page that is roughly right beats
    /// threading a measurement through three views to be exactly right.
    static let halfPageRows = 12

    static func destination(from current: Int?, delta: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let current else {
            // Nothing selected yet: a downward motion starts at the top and an
            // upward one at the bottom, so `j` and `k` both do something
            // sensible on a list nobody has touched.
            return delta >= 0 ? 0 : count - 1
        }
        return min(max(current + delta, 0), count - 1)
    }
}
