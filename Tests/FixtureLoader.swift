import Foundation
import Testing
@testable import StravaLocal

/// Reads JSON fixtures from the test bundle. `project.yml` copies everything
/// under `Tests/` into the bundle, so fixtures need no extra build phase.
enum Fixture {
    static func data(_ name: String) throws -> Data {
        guard let url = Bundle(for: BundleToken.self)
            .url(forResource: name, withExtension: "json")
        else {
            throw FixtureError.notFound(name)
        }
        return try Data(contentsOf: url)
    }

    static func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try StravaJSON.decoder.decode(type, from: data(name))
    }

    /// Decodes a fixture with a few top-level values replaced.
    ///
    /// Editing protection has to be tested against the same payload twice with
    /// one field changed; a second fixture file per case would drift from the
    /// first.
    static func decode<T: Decodable>(
        _ type: T.Type, from name: String, patching values: [String: Any]
    ) throws -> T {
        let data = try data(name)
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        for (key, value) in values { object[key] = value }
        let patched = try JSONSerialization.data(withJSONObject: object)
        return try StravaJSON.decoder.decode(type, from: patched)
    }

    enum FixtureError: Error { case notFound(String) }
    private final class BundleToken {}
}
