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

    enum FixtureError: Error { case notFound(String) }
    private final class BundleToken {}
}
