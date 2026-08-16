import Testing
import Foundation
@testable import Cairn

@Suite("Lignes du miroir")
struct MirrorRowTests {
    /// Les noms de colonnes sont en `snake_case` côté Postgres et en
    /// `camelCase` côté Swift. Aucune conversion automatique ne fait ce
    /// travail, donc il est écrit à la main — et donc il se teste.
    @Test func uneActiviteDonneSesColonnes() {
        let activity = Activity(stravaID: 42, name: "Sortie", sportType: .ride)
        activity.distance = 12_345
        activity.movingTime = 3_600

        let row = activity.mirrorRow(userID: "u")

        #expect(row["uuid"] == .string(activity.uuid))
        #expect(row["user_id"] == .string("u"))
        #expect(row["strava_id"] == .int(42))
        #expect(row["name"] == .string("Sortie"))
        #expect(row["sport_type_raw"] == .string(SportType.ride.rawValue))
        #expect(row["distance"] == .double(12_345))
        #expect(row["moving_time"] == .int(3_600))
        #expect(Activity.mirrorTable == "activity")
    }

    /// Une valeur absente part en `null` explicite, jamais omise. Une colonne
    /// omise d'un upsert garde son ancienne valeur : un cardio effacé
    /// localement resterait alors indéfiniment dans le miroir.
    @Test func unChampAbsentPartEnNulExplicite() {
        let activity = Activity(stravaID: 1, name: "", sportType: .run)
        activity.averageHeartrate = nil

        let row = activity.mirrorRow(userID: "u")

        #expect(row["average_heartrate"] == .null)
        #expect(row.keys.contains("average_heartrate"))
    }

    /// La trace simplifiée traverse en octets bruts. C'est ce qui permettra au
    /// web de la relire avec un `Float64Array` sans rien décoder d'autre.
    @Test func laTraceSimplifieeTraverseEnOctets() {
        let activity = Activity(stravaID: 1, name: "", sportType: .run)
        activity.apply(simplifiedCoordinates: [
            Coordinate(latitude: 45.1, longitude: 5.7),
        ])

        let row = activity.mirrorRow(userID: "u")

        #expect(row["simplified_track"] == .data(activity.simplifiedTrack!))
    }

    /// Le contenu des blobs ne passe pas par la ligne : il part dans Storage, et
    /// la ligne n'en garde qu'un chemin. Sans cette règle, 178 Mo de photos
    /// finiraient dans une base de 500 Mo.
    @Test func unePhotoNEmportePasSesOctets() {
        let photo = ActivityPhoto(uniqueID: "p1")
        photo.data = Data(repeating: 0xFF, count: 1_000)
        photo.activityUUID = "a1"

        let row = photo.mirrorRow(userID: "u")

        #expect(row["storage_path"] == .string("u/p1"))
        #expect(row["activity_uuid"] == .string("a1"))
        #expect(!row.keys.contains("data"))
    }

    /// `editedFieldsRaw` est la seule propriété `...Raw` dont le nom de
    /// colonne perd le suffixe — le schéma s'en explique dans un commentaire.
    /// Les trois autres (`sourceRaw`, `sportTypeRaw`, `workoutLabelRaw`) le
    /// gardent.
    @Test func editedFieldsPerdSonSuffixeRawSeul() {
        let activity = Activity(stravaID: 1, name: "", sportType: .run)
        activity.markEdited([.name])

        let row = activity.mirrorRow(userID: "u")

        #expect(row["edited_fields"] == .stringArray(["name"]))
        #expect(row.keys.contains("source_raw"))
        #expect(row.keys.contains("sport_type_raw"))
        #expect(row.keys.contains("workout_label_raw"))
        #expect(!row.keys.contains("editedFieldsRaw"))
        #expect(!row.keys.contains("edited_fields_raw"))
    }

    /// `Athlete.updatedAt` est le rafraîchissement Strava du profil, sans
    /// rapport avec la colonne standard `updated_at` du miroir — le schéma le
    /// range donc sous `profile_updated_at`.
    @Test func laDateDuProfilAthleteEviteUpdatedAt() {
        let athlete = Athlete(stravaID: 1)
        athlete.updatedAt = Date(timeIntervalSince1970: 1_000)

        let row = athlete.mirrorRow(userID: "u")

        #expect(row["profile_updated_at"] == .date(Date(timeIntervalSince1970: 1_000)))
        #expect(!row.keys.contains("updated_at"))
        #expect(Athlete.mirrorTable == "athlete")
    }

    /// `WeightEntry` n'a jamais porté `day` ni `kilograms` : seuls
    /// `date_key_raw` et `weight_kg` ont existé sur ce modèle.
    @Test func lePoidsEmetDateKeyRawEtWeightKg() {
        let entry = WeightEntry(dateKey: DateKey(raw: "2026-08-16")!, weightKg: 70.5)

        let row = entry.mirrorRow(userID: "u")

        #expect(row["date_key_raw"] == .string("2026-08-16"))
        #expect(row["weight_kg"] == .double(70.5))
        #expect(!row.keys.contains("day"))
        #expect(!row.keys.contains("kilograms"))
        #expect(WeightEntry.mirrorTable == "weight_entry")
    }

    /// Un flux, comme une photo, n'emporte jamais ses octets — seulement un
    /// chemin. L'identifiant naturel d'un flux est son propre `uuid`, pas
    /// celui de l'activité qui le porte. Les onze flux `Data?` du modèle sont
    /// tous couverts, pas seulement `latlng`: chacun coûte une ligne, et un
    /// seul vérifié en aurait laissé dix sans filet.
    @Test func unFluxNEmportePasNonPlusSesOctets() {
        let streams = ActivityStreams()
        streams.latlng = Data(repeating: 0x01, count: 100)
        streams.distance = Data(repeating: 0x02, count: 100)
        streams.altitude = Data(repeating: 0x03, count: 100)
        streams.time = Data(repeating: 0x04, count: 100)
        streams.heartrate = Data(repeating: 0x05, count: 100)
        streams.cadence = Data(repeating: 0x06, count: 100)
        streams.watts = Data(repeating: 0x07, count: 100)
        streams.velocitySmooth = Data(repeating: 0x08, count: 100)
        streams.temp = Data(repeating: 0x09, count: 100)
        streams.grade = Data(repeating: 0x0A, count: 100)
        streams.moving = Data(repeating: 0x0B, count: 100)
        streams.pointCount = 42

        let row = streams.mirrorRow(userID: "u")

        #expect(row["storage_path"] == .string("u/\(streams.uuid)"))
        #expect(row["point_count"] == .int(42))
        let streamColumnNames = [
            "latlng", "distance", "altitude", "time", "heartrate",
            "cadence", "watts", "velocity_smooth", "temp", "grade", "moving",
        ]
        for name in streamColumnNames {
            #expect(!row.keys.contains(name), "\(name) ne doit pas devenir une colonne")
        }
    }

    /// `Activity.gear_id` porte l'identifiant Strava du matériel, pas un uuid
    /// local — le schéma le commente explicitement. Un `Gear` est attaché ici
    /// avec un `uuid` distinct de `gearID`, pour que le test distingue
    /// vraiment « lit `gearID` » de « lit `gear?.uuid`, qui n'existe pas
    /// encore » : sans le matériel attaché, les deux lectures auraient donné
    /// la même ligne.
    @Test func gearIdPorteLIdentifiantStravaPasUnUuid() {
        let activity = Activity(stravaID: 1, name: "", sportType: .run)
        let gear = Gear(stravaID: "b1234567890", name: "Vélo")
        activity.gear = gear
        activity.gearID = "b1234567890"

        let row = activity.mirrorRow(userID: "u")

        #expect(row["gear_id"] == .string("b1234567890"))
        #expect(row["gear_id"] != .string(gear.uuid))
    }
}
