import Testing
import Foundation
@testable import Cairn

private let start = Date(timeIntervalSince1970: 1_714_547_553) // 2024-05-01 07:12:33 UTC

private func source(
    name: String = "Tour du lac",
    description: String = "",
    sport: SportType = .run,
    isTrainer: Bool = false,
    distance: Double = 10_000,
    duration: Double = 3_000,
    gear: GarminSource.GearSnapshot? = nil
) -> GarminSource {
    GarminSource(
        name: name, description: description, sport: sport, isTrainer: isTrainer,
        start: start, distance: distance, duration: duration, gear: gear
    )
}

private func garmin(
    id: Int64 = 1, name: String = "Lyon Course à pied", description: String = "",
    typeKey: String? = "running", offset: TimeInterval = 0,
    distance: Double? = 10_000, duration: Double? = 3_000
) -> GarminActivity {
    GarminActivity(
        id: id, name: name, description: description, typeKey: typeKey,
        start: start.addingTimeInterval(offset), distance: distance, duration: duration
    )
}

@Suite("Garmin : rapprochement et écarts")
struct GarminSyncTests {
    @Test("les deux formats d'heure de Garmin se lisent en UTC")
    func parsesGMT() {
        #expect(GarminActivity.parseGMT("2024-05-01 07:12:33") == start)
        #expect(GarminActivity.parseGMT("2024-05-01T07:12:33.0") == start)
    }

    @Test("le détail d'une activité se lit comme un élément de la liste")
    func readsDetailShape() throws {
        let json: [String: Any] = [
            "activityId": NSNumber(value: 42), "activityName": "Sortie",
            "description": "texte",
            "activityTypeDTO": ["typeKey": "trail_running"],
            "summaryDTO": ["startTimeGMT": "2024-05-01T07:12:33.0", "distance": 12.5, "duration": 60],
        ]
        let activity = try #require(GarminActivity(json: json))
        #expect(activity.id == 42)
        #expect(activity.typeKey == "trail_running")
        #expect(activity.start == start)
        #expect(activity.distance == 12.5)
        #expect(activity.description == "texte")
    }

    @Test("au-delà de 20 minutes d'écart, ce n'est pas la même sortie")
    func rejectsDistantStart() {
        #expect(GarminMatching.score(source(), garmin(offset: 21 * 60)) == nil)
        #expect(GarminMatching.score(source(), garmin(offset: 0)) == 1)
    }

    @Test("la plus proche en heure, distance et durée l'emporte")
    func picksBestMatch() {
        let candidates = [
            garmin(id: 1, offset: 5 * 60, distance: 4_000),
            garmin(id: 2, offset: 30),
            garmin(id: 3, offset: 2 * 3600),
        ]
        #expect(GarminMatching.bestMatch(for: source(), among: candidates)?.id == 2)
        #expect(GarminMatching.bestMatch(for: source(), among: [garmin(offset: 3600)]) == nil)
    }

    @Test("un type déjà équivalent n'est pas corrigé")
    func keepsEquivalentType() {
        #expect(GarminMatching.proposedType(for: source(sport: .run), current: "street_running") == nil)
        #expect(GarminMatching.proposedType(for: source(sport: .trailRun), current: "running") == "trail_running")
        #expect(GarminMatching.proposedType(for: source(sport: .workout), current: "yoga") == nil)
        #expect(GarminMatching.proposedType(for: source(sport: .other), current: "running") == nil)
    }

    @Test("un vélo sur home-trainer propose le vélo d'intérieur")
    func trainerRide() {
        #expect(
            GarminMatching.proposedType(for: source(sport: .ride, isTrainer: true), current: "road_biking")
                == "indoor_cycling"
        )
        #expect(GarminMatching.proposedType(for: source(sport: .ride), current: "road_biking") == nil)
    }

    @Test("une description déjà contenue sur Garmin n'est pas reproposée")
    func descriptionContained() {
        let s = source(description: "Belle sortie\n\nnote privée")
        #expect(
            GarminMatching.proposedDescription(
                for: s, current: "Belle sortie\n\nnote privée\n\najout Garmin"
            ) == nil
        )
        #expect(GarminMatching.proposedDescription(for: s, current: "") == "Belle sortie\n\nnote privée")
        #expect(GarminMatching.proposedDescription(for: source(description: "  "), current: "") == nil)
    }

    @Test("le matériel se retrouve par son nom, accents et casse ignorés")
    func matchesGearByName() {
        let catalog = [
            GarminGear(uuid: "a", name: "Pegasus 40", type: "shoes"),
            GarminGear(uuid: "b", name: "Vélo route", model: "Canyon Endurace", type: "bike"),
        ]
        let shoes = GarminSource.GearSnapshot(name: "pegasus 40", isBike: false)
        let bike = GarminSource.GearSnapshot(name: "Velo Route", isBike: true)
        let unknown = GarminSource.GearSnapshot(name: "Hoka Speedgoat", isBike: false)
        #expect(GarminMatching.matchingGear(for: shoes, in: catalog)?.uuid == "a")
        #expect(GarminMatching.matchingGear(for: bike, in: catalog)?.uuid == "b")
        #expect(GarminMatching.matchingGear(for: unknown, in: catalog) == nil)
    }

    @Test("le matériel remplace celui du même type et garde les autres")
    func replacesSameKindOfGear() {
        let catalog = [
            GarminGear(uuid: "old", name: "Vieilles chaussures", type: "shoes"),
            GarminGear(uuid: "new", name: "Pegasus 40", type: "shoes"),
            GarminGear(uuid: "hrm", name: "Ceinture", type: "other"),
        ]
        let proposal = GarminMatching.proposal(
            for: source(
                name: "Lyon Course à pied",
                gear: .init(name: "Pegasus 40", isBike: false)
            ),
            garmin: garmin(),
            currentGear: [catalog[0], catalog[2]],
            catalog: catalog
        )
        #expect(proposal.gearUUIDs == ["hrm", "new"])
        #expect(proposal.changes.map(\.field) == [.gear])
    }

    @Test("rien à changer quand Garmin dit déjà la même chose")
    func emptyProposal() {
        let proposal = GarminMatching.proposal(
            for: source(name: "Lyon Course à pied", description: "texte"),
            garmin: garmin(description: "texte"),
            currentGear: [], catalog: []
        )
        #expect(proposal.isEmpty)
    }

    @Test("un matériel sans équivalent est signalé, pas ignoré")
    func unmatchedGear() {
        let proposal = GarminMatching.proposal(
            for: source(gear: .init(name: "Hoka", isBike: false)),
            garmin: garmin(), currentGear: [], catalog: []
        )
        #expect(proposal.unmatchedGearName == "Hoka")
        #expect(proposal.changes.map(\.field) == [.name])
    }
}

// MARK: - Client

private final class GarminStubTransport: HTTPTransport, @unchecked Sendable {
    struct Response { let status: Int; let body: String }
    private let lock = NSLock()
    private var queue: [Response]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [Response]) { queue = responses }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock {
            requests.append(request)
            let response = queue.isEmpty ? Response(status: 500, body: "") : queue.removeFirst()
            let http = HTTPURLResponse(
                url: request.url!, statusCode: response.status, httpVersion: nil, headerFields: nil
            )!
            return (Data(response.body.utf8), http)
        }
    }
}

/// A token whose payload names its client and expires in an hour.
private func jwt(client: String = "GARMIN_CONNECT_MOBILE_ANDROID_DI_2025Q2", exp: TimeInterval = 3600) -> String {
    let payload = try! JSONSerialization.data(withJSONObject: [
        "client_id": client, "exp": Date().timeIntervalSince1970 + exp,
    ])
    let b64 = payload.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return "eyJhbGciOiJSUzI1NiJ9.\(b64).sig"
}

@Suite("GarminClient")
struct GarminClientTests {
    @Test("connexion sans MFA : ticket échangé, profil lu, jetons rangés")
    func loginWithoutMFA() async throws {
        let sso = GarminStubTransport([
            .init(status: 200, body: #"{"responseStatus":{"type":"SUCCESSFUL"},"serviceTicketId":"ST-1"}"#),
        ])
        let token = jwt()
        let api = GarminStubTransport([
            .init(status: 200, body: #"{"access_token":"\#(token)","refresh_token":"r1"}"#),
            .init(status: 200, body: #"{"fullName":"Florian M"}"#),
        ])
        let store = InMemorySecretStore()
        let client = GarminClient(store: store, transport: api, makeLoginTransport: { sso })

        guard case let .connected(tokens) = try await client.login(email: "a@b.c", password: "pw")
        else { Issue.record("MFA inattendu"); return }

        #expect(tokens.displayName == "Florian M")
        #expect(store.garminTokens()?.refreshToken == "r1")
        let login = try #require(sso.requests.first)
        #expect(login.url?.path == "/mobile/api/login")
        #expect(login.url?.query?.contains("clientId=GCM_IOS_DARK") == true)
        let exchange = String(decoding: api.requests[0].httpBody ?? Data(), as: UTF8.self)
        #expect(exchange.contains("service_ticket=ST-1"))
        #expect(exchange.contains("service_url=https%3A%2F%2Fmobile.integration.garmin.com%2Fgcm%2Fios"))
        #expect(api.requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer \(token)")
    }

    @Test("le code MFA passe par la même session que le mot de passe")
    func loginWithMFA() async throws {
        let sso = GarminStubTransport([
            .init(status: 200, body: #"{"responseStatus":{"type":"MFA_REQUIRED"},"customerMfaInfo":{"mfaLastMethodUsed":"sms"}}"#),
            .init(status: 200, body: #"{"responseStatus":{"type":"SUCCESSFUL"},"serviceTicketId":"ST-2"}"#),
        ])
        let api = GarminStubTransport([
            .init(status: 200, body: #"{"access_token":"\#(jwt())","refresh_token":"r"}"#),
            .init(status: 200, body: "{}"),
        ])
        let store = InMemorySecretStore()
        let client = GarminClient(store: store, transport: api, makeLoginTransport: { sso })

        guard case let .needsMFA(pending) = try await client.login(email: "a", password: "b")
        else { Issue.record("MFA attendu"); return }
        #expect(store.garminTokens() == nil)

        _ = try await client.verifyMFA(code: " 123456 ", for: pending)
        #expect(sso.requests[1].url?.path == "/mobile/api/mfa/verifyCode")
        let body = try JSONSerialization.jsonObject(with: sso.requests[1].httpBody!) as! [String: Any]
        #expect(body["mfaVerificationCode"] as? String == "123456")
        #expect(body["mfaMethod"] as? String == "sms")
        #expect(store.garminTokens() != nil)
    }

    @Test("mauvais mot de passe : erreur claire, rien de rangé")
    func invalidCredentials() async {
        let sso = GarminStubTransport([
            .init(status: 200, body: #"{"responseStatus":{"type":"INVALID_USERNAME_PASSWORD"}}"#),
        ])
        let store = InMemorySecretStore()
        let client = GarminClient(store: store, transport: GarminStubTransport([]), makeLoginTransport: { sso })
        await #expect(throws: GarminError.invalidCredentials) {
            _ = try await client.login(email: "a", password: "b")
        }
        #expect(store.garminTokens() == nil)
    }

    @Test("une page HTML à la place du JSON se dit « bloqué »")
    func blockedByBotProtection() async {
        let sso = GarminStubTransport([.init(status: 200, body: "<html>challenge</html>")])
        let client = GarminClient(
            store: InMemorySecretStore(), transport: GarminStubTransport([]),
            makeLoginTransport: { sso }
        )
        await #expect(throws: GarminError.self) {
            _ = try await client.login(email: "a", password: "b")
        }
    }

    @Test("un 401 rafraîchit le jeton puis rejoue la requête")
    func refreshesOn401() async throws {
        let store = InMemorySecretStore()
        try store.save(GarminTokens(accessToken: jwt(), refreshToken: "old", clientID: "C", displayName: "F"))
        let fresh = jwt(client: "C")
        let api = GarminStubTransport([
            .init(status: 401, body: ""),
            .init(status: 200, body: #"{"access_token":"\#(fresh)","refresh_token":"new"}"#),
            .init(status: 200, body: "[]"),
        ])
        let client = GarminClient(store: store, transport: api)

        _ = try await client.gear(forActivity: 7)

        #expect(api.requests.count == 3)
        #expect(String(decoding: api.requests[1].httpBody!, as: UTF8.self).contains("refresh_token=old"))
        #expect(api.requests[2].value(forHTTPHeaderField: "Authorization") == "Bearer \(fresh)")
        #expect(store.garminTokens()?.refreshToken == "new")
        #expect(store.garminTokens()?.displayName == "F")
    }

    @Test("un rafraîchissement refusé déconnecte")
    func refreshRejectedSignsOut() async throws {
        let store = InMemorySecretStore()
        try store.save(GarminTokens(accessToken: jwt(exp: -60), refreshToken: "dead", clientID: "C"))
        let api = GarminStubTransport([.init(status: 400, body: #"{"error":"invalid_grant"}"#)])
        let client = GarminClient(store: store, transport: api)

        await #expect(throws: GarminError.refreshRejected) {
            _ = try await client.gear(forActivity: 7)
        }
        #expect(store.garminTokens() == nil)
    }

    @Test("la mise à jour n'envoie que les champs choisis")
    func updateSendsOnlyChosenFields() async throws {
        let store = InMemorySecretStore()
        try store.save(GarminTokens(accessToken: jwt(), refreshToken: "r", clientID: "C"))
        let api = GarminStubTransport([.init(status: 204, body: "")])
        let client = GarminClient(store: store, transport: api)

        try await client.updateActivity(id: 99, name: "Nouveau", description: nil, type: nil)

        let request = try #require(api.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.absoluteString == "https://connectapi.garmin.com/activity-service/activity/99")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        #expect(body["activityName"] as? String == "Nouveau")
        #expect(body["description"] == nil)
        #expect(body["activityTypeDTO"] == nil)
    }
}

@MainActor
@Suite("GarminSyncTracker")
struct GarminSyncTrackerTests {
    private static let suitePrefix = "garmin-sync-tracker-tests-"

    private func makeDefaults() -> UserDefaults {
        ThrowawayDefaults.sweep(prefix: Self.suitePrefix)
        let defaults = UserDefaults(suiteName: "\(Self.suitePrefix)\(UUID().uuidString)")!
        defaults.removePersistentDomain(forName: defaults.description)
        return defaults
    }

    private func signedInStore() throws -> InMemorySecretStore {
        let store = InMemorySecretStore()
        try store.save(GarminTokens(accessToken: jwt(), refreshToken: "r", clientID: "C"))
        return store
    }

    /// The three reads of a comparison without gear: the list, the
    /// activity, its gear.
    private func garminSays(name: String) -> [GarminStubTransport.Response] {
        let item = #"{"activityId":5,"activityName":"\#(name)","activityType":{"typeKey":"running"},"startTimeGMT":"2024-05-01 07:12:33","distance":10000,"duration":3000}"#
        return [
            .init(status: 200, body: "[\(item)]"),
            .init(status: 200, body: item),
            .init(status: 200, body: "[]"),
        ]
    }

    @Test("rien à changer : l'activité est notée synchronisée, et le reste")
    func inStepIsRemembered() async throws {
        let defaults = makeDefaults()
        let api = GarminStubTransport(garminSays(name: "Tour du lac"))
        let client = GarminClient(store: try signedInStore(), transport: api)
        let tracker = GarminSyncTracker(client: client, defaults: defaults)

        await tracker.checkIfNeeded(uuid: "u", source: source())
        #expect(tracker.state(uuid: "u", source: source()) == .synced)

        // Remembered across launches, and never checked again on its own.
        let later = GarminSyncTracker(client: client, defaults: defaults)
        #expect(later.state(uuid: "u", source: source()) == .synced)
        await later.checkIfNeeded(uuid: "u", source: source())
        #expect(api.requests.count == 3)
    }

    @Test("un écart sur Garmin demande la synchro")
    func differenceNeedsSync() async throws {
        let api = GarminStubTransport(garminSays(name: "Lyon Course à pied"))
        let tracker = GarminSyncTracker(
            client: GarminClient(store: try signedInStore(), transport: api),
            defaults: makeDefaults()
        )
        await tracker.checkIfNeeded(uuid: "u", source: source())
        #expect(tracker.state(uuid: "u", source: source()) == .needsSync)
    }

    @Test("modifier l'activité dans Cairn la fait revérifier")
    func editMakesItUnknown() throws {
        let tracker = GarminSyncTracker(
            client: GarminClient(store: try signedInStore(), transport: GarminStubTransport([])),
            defaults: makeDefaults()
        )
        tracker.markSynced(uuid: "u", source: source())
        #expect(tracker.state(uuid: "u", source: source(name: "Autre titre")) == .unknown)
        #expect(tracker.state(uuid: "u", source: source(description: "ajout")) == .unknown)
        #expect(tracker.state(uuid: "u", source: source()) == .synced)
    }

    @Test("sans sortie Garmin, ni erreur ni invitation")
    func noTwinStaysQuiet() async throws {
        let api = GarminStubTransport([.init(status: 200, body: "[]")])
        let tracker = GarminSyncTracker(
            client: GarminClient(store: try signedInStore(), transport: api),
            defaults: makeDefaults()
        )
        await tracker.checkIfNeeded(uuid: "u", source: source())
        #expect(tracker.state(uuid: "u", source: source()) == .unavailable)
    }
}

@MainActor
@Suite("TitlePropagator")
struct TitlePropagatorTests {
    private static let suitePrefix = "title-propagator-tests-"

    private func makeDefaults() -> UserDefaults {
        ThrowawayDefaults.sweep(prefix: Self.suitePrefix)
        let defaults = UserDefaults(suiteName: "\(Self.suitePrefix)\(UUID().uuidString)")!
        defaults.removePersistentDomain(forName: defaults.description)
        return defaults
    }

    private func store() throws -> InMemorySecretStore {
        let store = InMemorySecretStore(
            credentials: StravaCredentials(clientID: "1", clientSecret: "s"),
            tokens: StravaTokens(
                accessToken: "strava", refreshToken: "r", expiresAt: Date().addingTimeInterval(3600)
            )
        )
        try store.save(GarminTokens(accessToken: jwt(), refreshToken: "r", clientID: "C"))
        return store
    }

    private func garminSays(name: String) -> [GarminStubTransport.Response] {
        let item = #"{"activityId":5,"activityName":"\#(name)","activityType":{"typeKey":"running"},"startTimeGMT":"2024-05-01 07:12:33","distance":10000,"duration":3000}"#
        return [
            .init(status: 200, body: "[\(item)]"),
            .init(status: 200, body: item),
            .init(status: 200, body: "[]"),
        ]
    }

    @Test("le nouveau titre part sur Strava et sur Garmin, et Garmin est noté à jour")
    func renamesBoth() async throws {
        let store = try store()
        let stravaAPI = GarminStubTransport([.init(status: 200, body: "{}")])
        let garminAPI = GarminStubTransport(
            garminSays(name: "Lyon Course à pied") + [.init(status: 204, body: "")]
                + garminSays(name: "Tour du lac")
        )
        let garmin = GarminClient(store: store, transport: garminAPI)
        let tracker = GarminSyncTracker(client: garmin, defaults: makeDefaults())
        let propagator = TitlePropagator(
            strava: StravaClient(store: store, transport: stravaAPI),
            garmin: garmin, garminSync: tracker
        )

        await propagator.propagate(
            uuid: "u", stravaID: 77, source: source(), toStrava: true, toGarmin: true
        )

        #expect(propagator.failures["u"] == nil)
        let put = try #require(stravaAPI.requests.first)
        #expect(put.httpMethod == "PUT")
        #expect(put.url?.path.hasSuffix("/activities/77") == true)
        let body = try JSONSerialization.jsonObject(with: put.httpBody!) as! [String: Any]
        #expect(body["name"] as? String == "Tour du lac")

        let garminPut = garminAPI.requests[3]
        #expect(garminPut.httpMethod == "PUT")
        let garminBody = try JSONSerialization.jsonObject(with: garminPut.httpBody!) as! [String: Any]
        #expect(garminBody["activityName"] as? String == "Tour du lac")
        #expect(garminBody["description"] == nil)
        #expect(tracker.state(uuid: "u", source: source()) == .synced)
    }

    @Test("un jeton Strava sans droit d'écriture dit de se reconnecter")
    func stravaWithoutWriteScope() async throws {
        let store = try store()
        let stravaAPI = GarminStubTransport([
            .init(status: 401, body: #"{"message":"Authorization Error"}"#),
        ])
        let garmin = GarminClient(store: store, transport: GarminStubTransport([]))
        let propagator = TitlePropagator(
            strava: StravaClient(store: store, transport: stravaAPI),
            garmin: garmin,
            garminSync: GarminSyncTracker(client: garmin, defaults: makeDefaults())
        )

        await propagator.propagate(
            uuid: "u", stravaID: 77, source: source(), toStrava: true, toGarmin: false
        )

        let failure = try #require(propagator.failures["u"])
        #expect(failure.hasPrefix("Strava : "))
        #expect(failure.contains("reconnectez"))
    }

    @Test("une activité saisie à la main ne touche pas Strava")
    func manualActivitySkipsStrava() async throws {
        let store = try store()
        let stravaAPI = GarminStubTransport([])
        let garmin = GarminClient(store: store, transport: GarminStubTransport([.init(status: 200, body: "[]")]))
        let propagator = TitlePropagator(
            strava: StravaClient(store: store, transport: stravaAPI),
            garmin: garmin,
            garminSync: GarminSyncTracker(client: garmin, defaults: makeDefaults())
        )

        await propagator.propagate(
            uuid: "u", stravaID: nil, source: source(), toStrava: true, toGarmin: true
        )

        #expect(stravaAPI.requests.isEmpty)
        #expect(propagator.failures["u"] == nil)
    }
}
