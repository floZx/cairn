import Foundation

// MARK: - Activity

extension Activity: MirrorRow {
    static var mirrorTable: String { "activity" }

    func mirrorRow(userID: String) -> [String: MirrorValue] {
        [
            "uuid": .string(uuid),
            "user_id": .string(userID),

            "strava_id": .int(stravaID),
            "source_raw": .string(sourceRaw),
            // The one `...Raw` property whose column drops the suffix: the
            // schema calls it `edited_fields`, not `edited_fields_raw`.
            "edited_fields": .stringArray(editedFieldsRaw),
            "name": .string(name),
            "sport_type_raw": .string(sportTypeRaw),
            "start_date": .date(startDate),
            "start_local_date": .date(startLocalDate),
            "timezone_identifier": .from(timezoneIdentifier),

            "distance": .double(distance),
            "moving_time": .from(movingTime),
            "elapsed_time": .from(elapsedTime),
            "total_elevation_gain": .double(totalElevationGain),
            "average_speed": .double(averageSpeed),
            "max_speed": .double(maxSpeed),
            "average_heartrate": .from(averageHeartrate),
            "max_heartrate": .from(maxHeartrate),
            "average_watts": .from(averageWatts),
            "weighted_average_watts": .from(weightedAverageWatts),
            "kilojoules": .from(kilojoules),
            "average_cadence": .from(averageCadence),
            "calories": .from(calories),

            "is_favorite": .bool(isFavorite),
            "is_commute": .bool(isCommute),
            "is_trainer": .bool(isTrainer),
            "is_manual": .bool(isManual),
            "is_private": .bool(isPrivate),
            "workout_type": .from(workoutType),
            "workout_label_raw": .from(workoutLabelRaw),

            "kudos_count": .from(kudosCount),
            "achievement_count": .from(achievementCount),
            "pr_count": .from(prCount),
            "athlete_count": .from(athleteCount),

            "start_latitude": .from(startLatitude),
            "start_longitude": .from(startLongitude),
            "end_latitude": .from(endLatitude),
            "end_longitude": .from(endLongitude),

            "min_lat": .double(minLat),
            "max_lat": .double(maxLat),
            "min_lon": .double(minLon),
            "max_lon": .double(maxLon),
            "has_track": .bool(hasTrack),

            // The one blob that does travel in the row: a few kilobytes that
            // let the web's global map render in a single query, per the
            // schema's own comment.
            "simplified_track": simplifiedTrack.map(MirrorValue.data) ?? .null,
            "summary_polyline": .from(summaryPolyline),
            "activity_description": .from(activityDescription),
            "device_name": .from(deviceName),
            "detail_fetched_at": .from(detailFetchedAt),
            "photos_fetched_at": .from(photosFetchedAt),
            "photo_count": .from(photoCount),

            // Strava's own gear identifier, not `gear?.uuid`: the summary
            // endpoint hands this over long before the gear itself is
            // fetched, exactly as the schema's comment on `gear_id` explains.
            "gear_id": .from(gearID),
        ]
    }
}

// MARK: - ActivityStreams

extension ActivityStreams: MirrorRow {
    static var mirrorTable: String { "activity_streams" }

    /// Where this row's packaged streams live in the `streams` bucket — the
    /// same string `mirrorRow(userID:)` writes to `storage_path` and
    /// `MirrorEngine.uploadPendingBlobs()` uploads to, kept in one place so
    /// the two can never drift apart. The natural identifier for a stream is
    /// its own `uuid`.
    func blobStoragePath(userID: String) -> String { "\(userID)/\(uuid)" }

    /// The eleven `Data?` streams, name to bytes, with the empty ones left
    /// out — the JSON object `uploadPendingBlobs()` deposits at
    /// `blobStoragePath(userID:)` is built from exactly this. One object
    /// because the web always reads every stream of an activity together:
    /// eleven objects would mean eleven requests per activity instead of one.
    /// Each value is the untouched `TrackBlob` packing already held locally
    /// (little-endian, headerless) — nothing is decoded or re-encoded here.
    var packagedStreams: [String: Data] {
        let named: [(name: String, data: Data?)] = [
            ("latlng", latlng), ("distance", distance), ("altitude", altitude),
            ("time", time), ("heartrate", heartrate), ("cadence", cadence),
            ("watts", watts), ("velocitySmooth", velocitySmooth), ("temp", temp),
            ("grade", grade), ("moving", moving),
        ]
        var streams: [String: Data] = [:]
        for entry in named {
            if let data = entry.data { streams[entry.name] = data }
        }
        return streams
    }

    func mirrorRow(userID: String) -> [String: MirrorValue] {
        [
            "uuid": .string(uuid),
            "user_id": .string(userID),

            "activity_uuid": .from(activity?.uuid),
            "point_count": .from(pointCount),
            // None of the eleven `Data?` streams cross the row — they land in
            // one Storage object, and this path is where it lives.
            "storage_path": .string(blobStoragePath(userID: userID)),
        ]
    }
}

// MARK: - ActivityPhoto

extension ActivityPhoto: MirrorRow {
    static var mirrorTable: String { "activity_photo" }

    /// Where this photo's bytes live in the `photos` bucket — the same
    /// string `mirrorRow(userID:)` writes to `storage_path` and
    /// `MirrorEngine.uploadPendingBlobs()` uploads to, kept in one place so
    /// the two can never drift apart.
    func blobStoragePath(userID: String) -> String { "\(userID)/\(uniqueID)" }

    func mirrorRow(userID: String) -> [String: MirrorValue] {
        [
            "uuid": .string(uuid),
            "user_id": .string(userID),

            // `activityUUID`, not `activity?.uuid`: Postgres has only one
            // representation of the link, and `activityUUID` is the
            // non-optional copy the schema's comment asks for.
            "activity_uuid": .string(activityUUID),
            "unique_id": .string(uniqueID),
            "source_url": .from(sourceURL),
            "caption": .from(caption),
            "taken_at": .from(takenAt),
            "sort_index": .from(sortIndex),
            // The bytes never leave this Mac's disk for the row itself — only
            // a Storage path does, keyed on Strava's own photo identifier.
            "storage_path": .string(blobStoragePath(userID: userID)),
        ]
    }
}

// MARK: - Lap

extension Lap: MirrorRow {
    static var mirrorTable: String { "lap" }

    func mirrorRow(userID: String) -> [String: MirrorValue] {
        [
            "uuid": .string(uuid),
            "user_id": .string(userID),

            "activity_uuid": .from(activity?.uuid),
            "strava_id": .int(stravaID),
            "lap_index": .from(lapIndex),
            "name": .string(name),
            "distance": .double(distance),
            "moving_time": .from(movingTime),
            "elapsed_time": .from(elapsedTime),
            "total_elevation_gain": .double(totalElevationGain),
            "average_speed": .double(averageSpeed),
            "max_speed": .double(maxSpeed),
            "average_heartrate": .from(averageHeartrate),
            "average_cadence": .from(averageCadence),
            "start_index": .from(startIndex),
            "end_index": .from(endIndex),
        ]
    }
}

// MARK: - Gear

extension Gear: MirrorRow {
    static var mirrorTable: String { "gear" }

    func mirrorRow(userID: String) -> [String: MirrorValue] {
        [
            "uuid": .string(uuid),
            "user_id": .string(userID),

            "strava_id": .string(stravaID),
            "name": .string(name),
            "brand_name": .from(brandName),
            "model_name": .from(modelName),
            "is_bike": .bool(isBike),
            "total_distance": .double(totalDistance),
        ]
    }
}

// MARK: - Athlete

extension Athlete: MirrorRow {
    static var mirrorTable: String { "athlete" }

    func mirrorRow(userID: String) -> [String: MirrorValue] {
        [
            "uuid": .string(uuid),
            "user_id": .string(userID),

            "strava_id": .int(stravaID),
            "first_name": .string(firstName),
            "last_name": .string(lastName),
            "city": .from(city),
            "country": .from(country),
            "profile_image_url": .from(profileImageURL),
            "weight": .from(weight),
            // Strava's own refresh timestamp, not this mirror's `updated_at` —
            // the schema renames it precisely to avoid that collision.
            "profile_updated_at": .date(updatedAt),
        ]
    }
}

// MARK: - DiscardedActivity

extension DiscardedActivity: MirrorRow {
    static var mirrorTable: String { "discarded_activity" }

    func mirrorRow(userID: String) -> [String: MirrorValue] {
        [
            "uuid": .string(uuid),
            "user_id": .string(userID),

            "strava_id": .int(stravaID),
            "name": .string(name),
            "discarded_at": .date(discardedAt),
            "start_date": .date(startDate),
        ]
    }
}
