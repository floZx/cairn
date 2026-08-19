import Foundation

// MARK: - PlannedSession

extension PlannedSession: MirrorRow {
    static var mirrorTable: String { "planned_session" }

    func mirrorRow(userID: String) -> [String: MirrorValue] {
        [
            "uuid": .string(uuid),
            "user_id": .string(userID),

            "date_key_raw": .string(dateKeyRaw),
            "sport_type_raw": .string(sportTypeRaw),
            "title": .string(title),
            // `.from` et non `.double` : une séance sans objectif chiffré n'en
            // vise pas zéro, elle n'en vise pas. Voir `FoodEntry.fiber100`,
            // qui a valu la même distinction.
            "planned_distance": .from(plannedDistance),
            "planned_duration": .from(plannedDuration),
            "planned_elevation": .from(plannedElevation),
            "notes": .string(notes),
            "day_type_uuid": .from(dayType?.uuid),
            "sort_order": .from(sortOrder),
        ]
    }
}
