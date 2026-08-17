import Testing
import SwiftData
import Foundation
@testable import Cairn

@Suite("Photos Strava")
struct PhotoImportTests {
    private func photo(
        id: String, urls: [String: String], caption: String? = nil
    ) -> PhotoDTO {
        PhotoDTO(
            unique_id: id, urls: urls, caption: caption,
            created_at: nil, created_at_local: nil
        )
    }

    private func makeActivity(in context: ModelContext) -> Activity {
        let activity = Activity(stravaID: 42, name: "Sortie", sportType: .ride)
        context.insert(activity)
        return activity
    }

    /// Un domaine `UserDefaults` jetable, jamais `.standard` : `StoreMaintenance.run`
    /// déclenche désormais la reprise du journal, qui lirait et écrirait les
    /// vraies préférences de cette machine sans ce domaine à part — voir la
    /// même remarque dans `Tests/StoreMaintenanceTests.swift`.
    private static let suitePrefix = "photo-import-tests-"

    private func freshDefaults() -> (UserDefaults, String) {
        let name = "\(Self.suitePrefix)\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    private func discard(_ suiteName: String) {
        UserDefaults().removePersistentDomain(forName: suiteName)
        ThrowawayDefaults.sweep(prefix: Self.suitePrefix)
    }

    @Test("la plus grande taille est choisie, pas la première venue")
    func picksTheLargestSize() {
        // The keys are strings even though they are numbers: sorted as text,
        // "100" comes after "600" and the thumbnail wins.
        #expect(
            ActivityPhoto.largestURL(in: ["100": "petite", "600": "grande"]) == "grande"
        )
        #expect(
            ActivityPhoto.largestURL(in: ["1800": "énorme", "600": "grande"]) == "énorme"
        )
        #expect(ActivityPhoto.largestURL(in: [:]) == nil)
        #expect(ActivityPhoto.largestURL(in: nil) == nil)
    }

    @Test("une taille non numérique vaut mieux que rien")
    func fallsBackToANonNumericSize() {
        // Strava names one size with a word rather than a pixel count. Dropping
        // the photo because its only key will not parse would be absurd.
        #expect(ActivityPhoto.largestURL(in: ["original": "adresse"]) == "adresse")
    }

    @Test("les photos sont enregistrées dans l'ordre, avec leur légende")
    func recordsPhotosInOrder() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = makeActivity(in: context)
        let mapper = ImportMapper(context: context)

        let pending = mapper.upsert(
            photos: [
                photo(id: "a", urls: ["600": "url-a"], caption: "Au sommet"),
                photo(id: "b", urls: ["600": "url-b"]),
            ],
            on: activity
        )
        try context.save()

        #expect(pending.count == 2)
        #expect(activity.orderedPhotos.map(\.uniqueID) == ["a", "b"])
        #expect(activity.orderedPhotos[0].caption == "Au sommet")
        #expect(activity.orderedPhotos[0].sourceURL == "url-a")
    }

    @Test("une resynchro ne duplique ni ne retélécharge une photo déjà là")
    func doesNotDuplicateOrRefetch() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = makeActivity(in: context)
        let mapper = ImportMapper(context: context)

        _ = mapper.upsert(photos: [photo(id: "a", urls: ["600": "url-a"])], on: activity)
        activity.photos[0].data = Data("octets".utf8)
        try context.save()

        // Same photo, new signed address: Strava's URLs expire, so the address
        // changes at every sync while the photo does not.
        let pending = mapper.upsert(
            photos: [photo(id: "a", urls: ["600": "url-a-signée-à-nouveau"])],
            on: activity
        )

        #expect(activity.photos.count == 1)
        // Already downloaded, so nothing to fetch again — that is what the
        // deduplication on `unique_id` buys.
        #expect(pending.isEmpty)
        #expect(activity.photos[0].data == Data("octets".utf8))
        // The address is refreshed anyway: the old one is probably dead, and a
        // later retry would need the new one.
        #expect(activity.photos[0].sourceURL == "url-a-signée-à-nouveau")
    }

    @Test("chaque photo porte l'identité de son activité")
    func carriesItsActivityIdentity() throws {
        // The pane finds photos by this field rather than through the
        // relationship: the sync writes them from its own `ModelContext`, and a
        // to-many relationship on an activity the interface already holds does
        // not come back refreshed — the photos reached the disk and the pane
        // stayed empty until the next launch.
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = makeActivity(in: context)
        let mapper = ImportMapper(context: context)

        _ = mapper.upsert(photos: [photo(id: "a", urls: ["600": "url-a"])], on: activity)
        #expect(activity.photos[0].activityUUID == activity.uuid)
    }

    @Test("une photo enregistrée avant ce champ est rattachée par la maintenance")
    func maintenanceLinksOldPhotos() throws {
        // Those photos would be invisible for good otherwise: the sync will not
        // fetch them again, `photosFetchedAt` being already set on their activity.
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = makeActivity(in: context)
        let orphan = ActivityPhoto(uniqueID: "ancienne")
        orphan.activity = activity
        context.insert(orphan)
        activity.photos.append(orphan)
        try context.save()
        let (defaults, suiteName) = freshDefaults()
        defer { discard(suiteName) }

        #expect(try StoreMaintenance.run(context, defaults: defaults) > 0)
        #expect(orphan.activityUUID == activity.uuid)
        // Idempotent: a second pass has nothing left to repair.
        #expect(try StoreMaintenance.run(context, defaults: defaults) == 0)
    }

    @Test("une photo sans identifiant est reconnue par son adresse")
    func identifiesByURLWhenNoUniqueID() throws {
        // The undocumented endpoint owes us no field in particular. Without a
        // fallback identity, every sync would insert the same photo again.
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = makeActivity(in: context)
        let mapper = ImportMapper(context: context)
        let anonymous = PhotoDTO(
            unique_id: nil, urls: ["600": "url-a"], caption: nil,
            created_at: nil, created_at_local: nil
        )

        _ = mapper.upsert(photos: [anonymous], on: activity)
        _ = mapper.upsert(photos: [anonymous], on: activity)

        #expect(activity.photos.count == 1)
    }

    @Test("une photo sans adresse exploitable est ignorée")
    func skipsPhotosWithoutAURL() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = makeActivity(in: context)

        let pending = ImportMapper(context: context).upsert(
            photos: [PhotoDTO(
                unique_id: "a", urls: nil, caption: nil,
                created_at: nil, created_at_local: nil
            )],
            on: activity
        )

        #expect(pending.isEmpty)
        #expect(activity.photos.isEmpty)
    }

    @Test("une activité locale ne reçoit jamais les photos de Strava")
    func leavesLocalActivitiesAlone() throws {
        // Same guard as every other import path: a Strava identifier that
        // happens to collide must not staple someone else's photos onto an
        // activity typed in here or read from a file.
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = makeActivity(in: context)
        activity.source = .file

        let pending = ImportMapper(context: context).upsert(
            photos: [photo(id: "a", urls: ["600": "url-a"])], on: activity
        )

        #expect(pending.isEmpty)
        #expect(activity.photos.isEmpty)
    }
}
