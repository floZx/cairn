import Foundation

// MARK: - Person

extension Person: MirrorRow {
    static var mirrorTable: String { "person" }

    func mirrorRow(userID: String) -> [String: MirrorValue] {
        [
            "uuid": .string(uuid),
            "user_id": .string(userID),

            "key": .string(key),
            "name": .string(name),
            "note": .string(note),
        ]
    }
}
