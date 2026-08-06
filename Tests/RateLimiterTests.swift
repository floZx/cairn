import Testing
import Foundation
@testable import StravaLocal

@Suite("RateLimiter")
struct RateLimiterTests {
    private func headers(short: String, daily: String) -> [String: String] {
        ["X-RateLimit-Limit": "200,2000", "X-RateLimit-Usage": "\(short),\(daily)"]
    }

    @Test("parse les en-têtes de quota")
    func parsesHeaders() {
        let snapshot = RateLimitSnapshot(
            headers: ["X-RateLimit-Limit": "200,2000", "X-RateLimit-Usage": "42,1337"]
        )
        #expect(snapshot?.shortTermUsage == 42)
        #expect(snapshot?.shortTermLimit == 200)
        #expect(snapshot?.dailyUsage == 1337)
        #expect(snapshot?.dailyLimit == 2000)
    }

    @Test("des en-têtes absents ou malformés ne donnent pas de snapshot")
    func rejectsBadHeaders() {
        #expect(RateLimitSnapshot(headers: [:]) == nil)
        #expect(RateLimitSnapshot(headers: ["X-RateLimit-Limit": "200"]) == nil)
        #expect(
            RateLimitSnapshot(
                headers: ["X-RateLimit-Limit": "a,b", "X-RateLimit-Usage": "1,2"]
            ) == nil
        )
    }

    @Test("les en-têtes sont reconnus quelle que soit la casse")
    func headerLookupIsCaseInsensitive() {
        let snapshot = RateLimitSnapshot(
            headers: ["x-ratelimit-limit": "200,2000", "x-ratelimit-usage": "1,2"]
        )
        #expect(snapshot?.shortTermUsage == 1)
    }

    @Test("aucune attente quand il reste de la marge")
    func noDelayWithHeadroom() async {
        let limiter = RateLimiter(clock: { Date(timeIntervalSince1970: 0) })
        await limiter.observeSuccess(headers: headers(short: "10", daily: "100"))
        #expect(await limiter.delayBeforeNextRequest() == 0)
    }

    @Test("attend la prochaine fenêtre de 15 minutes quand le quota court terme est saturé")
    func waitsForNextShortWindow() async {
        // 1970-01-01T00:03:00Z → current window ends at 00:15:00Z, that is 720 s.
        let limiter = RateLimiter(clock: { Date(timeIntervalSince1970: 180) })
        await limiter.observeSuccess(headers: headers(short: "199", daily: "100"))
        #expect(await limiter.delayBeforeNextRequest() == 720)
    }

    @Test("la réserve empêche de consommer les toutes dernières requêtes")
    func reserveTriggersWait() async {
        let limiter = RateLimiter(clock: { Date(timeIntervalSince1970: 0) }, reserve: 5)
        await limiter.observeSuccess(headers: headers(short: "196", daily: "100"))
        #expect(await limiter.delayBeforeNextRequest() > 0)
        await limiter.observeSuccess(headers: headers(short: "194", daily: "100"))
        #expect(await limiter.delayBeforeNextRequest() == 0)
    }

    @Test("attend minuit UTC quand le quota journalier est saturé")
    func waitsForNextDay() async {
        // 1970-01-01T00:03:00Z → next midnight at 86400 s, that is 86220 s to wait.
        let limiter = RateLimiter(clock: { Date(timeIntervalSince1970: 180) })
        await limiter.observeSuccess(headers: headers(short: "10", daily: "1999"))
        #expect(await limiter.delayBeforeNextRequest() == 86_220)
    }

    @Test("un 429 déclenche un backoff qui double")
    func backsOffOnTooManyRequests() async {
        let limiter = RateLimiter(clock: { Date(timeIntervalSince1970: 0) })
        await limiter.observeTooManyRequests()
        let first = await limiter.delayBeforeNextRequest()
        await limiter.observeTooManyRequests()
        let second = await limiter.delayBeforeNextRequest()
        #expect(first > 0)
        #expect(second >= first * 2)
    }

    @Test("une réponse réussie remet le backoff à zéro")
    func successResetsBackoff() async {
        let limiter = RateLimiter(clock: { Date(timeIntervalSince1970: 0) })
        await limiter.observeTooManyRequests()
        #expect(await limiter.delayBeforeNextRequest() > 0)
        await limiter.observeSuccess(headers: headers(short: "10", daily: "100"))
        #expect(await limiter.delayBeforeNextRequest() == 0)
    }

    @Test("un succès aux en-têtes illisibles efface tout de même le backoff")
    func successWithUnparseableHeadersStillClearsBackoff() async {
        let limiter = RateLimiter(clock: { Date(timeIntervalSince1970: 0) })
        await limiter.observeTooManyRequests()
        #expect(await limiter.delayBeforeNextRequest() > 0)
        // A 2xx proves the throttling is over, whatever the headers looked like.
        await limiter.observeSuccess(headers: ["X-RateLimit-Limit": "garbage"])
        #expect(await limiter.delayBeforeNextRequest() == 0)
        #expect(await limiter.snapshot == nil)
    }

    @Test("les deux quotas saturés font attendre le plus long des deux")
    func bothQuotasExhaustedWaitsForTheLonger() async {
        // 1970-01-01T00:03:00Z: next 15-min window at 720 s, next day at 86220 s.
        let limiter = RateLimiter(clock: { Date(timeIntervalSince1970: 180) })
        await limiter.observeSuccess(
            headers: ["X-RateLimit-Limit": "200,2000", "X-RateLimit-Usage": "199,1999"]
        )
        #expect(await limiter.delayBeforeNextRequest() == 86_220)
    }
}
