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

    /// `mirrorRow` ne produit jamais les quatre colonnes que le moteur ou le
    /// trigger posent ailleurs — les émettre ici les ferait écraser par une
    /// valeur périmée à chaque upsert.
    @Test func lesQuatreColonnesReserveesNeSontJamaisEmises() {
        let activity = Activity(stravaID: 1, name: "", sportType: .run)
        activity.markEdited([.name])

        let row = activity.mirrorRow(userID: "u")

        #expect(!row.keys.contains("updated_at"))
        #expect(!row.keys.contains("edited_at"))
        #expect(!row.keys.contains("deleted_at"))
        #expect(!row.keys.contains("field_edited_at"))
    }

    /// `Athlete.updatedAt` est le rafraîchissement Strava du profil, sans
    /// rapport avec la colonne standard `updated_at` du miroir — le schéma le
    /// range donc sous `profile_updated_at`.
    @Test func laDateDuProfilAthleteEvitePptUpdatedAt() {
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
    /// celui de l'activité qui le porte.
    @Test func unFluxNEmportePasNonPlusSesOctets() {
        let streams = ActivityStreams()
        streams.latlng = Data(repeating: 0x01, count: 100)
        streams.pointCount = 42

        let row = streams.mirrorRow(userID: "u")

        #expect(row["storage_path"] == .string("u/\(streams.uuid)"))
        #expect(row["point_count"] == .int(42))
        #expect(!row.keys.contains("latlng"))
        #expect(!row.keys.contains("data"))
    }

    /// `Activity.gear_id` porte l'identifiant Strava du matériel, pas un uuid
    /// local — le schéma le commente explicitement.
    @Test func gearIdPorteLIdentifiantStravaPasUnUuid() {
        let activity = Activity(stravaID: 1, name: "", sportType: .run)
        activity.gearID = "b1234567890"

        let row = activity.mirrorRow(userID: "u")

        #expect(row["gear_id"] == .string("b1234567890"))
    }
}
