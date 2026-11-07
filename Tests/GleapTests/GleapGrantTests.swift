import XCTest
import ObjectiveC
@testable import Gleap

/// The grant a signed identify returns (`identity.grant`): sent as `Gleap-Grant` on the session's
/// requests, kept across restarts, dropped on logout; `identity_mismatch` restarts as a visitor.
final class GleapGrantTests: GleapNetworkTestCase {
    private var sessions: GleapSessionHelper { GleapSessionHelper.sharedInstance() }

    private func grant(sid: String, exp: TimeInterval = Date().timeIntervalSince1970 + 3600) -> String {
        GleapUserJwtTests.jwt(["sid": sid, "uid": "user-1", "kind": "jwt", "exp": exp])
    }

    private func signedReply(gleapId: String, grant: String?) -> GleapStubReply {
        Self.sessionReply(gleapId: gleapId, gleapHash: "ghash-\(gleapId)", extra: [
            "userId": "user-1",
            "identity": ["signed": grant != nil, "grant": (grant as Any?) ?? NSNull()],
        ])
    }

    func testTheGrantRidesOnTheSessionsRequestsAndLeavesWithClearIdentity() throws {
        installSession(gleapId: "gid-guest", gleapHash: "ghash-guest")
        let issued = grant(sid: "gid-user")
        GleapStubURLProtocol.stub("POST", "/sessions/identify", signedReply(gleapId: "gid-user", grant: issued))
        GleapStubURLProtocol.stub("POST", "/sessions/partialupdate", Self.sessionReply(gleapId: "gid-user", gleapHash: "ghash-gid-user", extra: ["userId": "user-1"]))
        GleapStubURLProtocol.stub("POST", "/sessions", Self.sessionReply(gleapId: "gid-next", gleapHash: "ghash-next"))

        Gleap.setUserJwt(GleapUserJwtTests.jwt(["userId": "user-1", "exp": Date().timeIntervalSince1970 + 3600]))
        XCTAssertTrue(waitUntil { self.sessions.currentSession?.gleapId == "gid-user" })
        XCTAssertNil(GleapStubURLProtocol.requests(path: "/sessions/identify").first?.header("Gleap-Grant"), "the guest had no grant")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "gleapGrant"), issued, "kept for the next app start")

        let data = GleapUserProperty()
        data.name = "Ada"
        Gleap.updateContact(data)
        let update = try XCTUnwrap(waitForRequest("/sessions/partialupdate"))
        XCTAssertEqual(update.header("Gleap-Grant"), issued)

        Gleap.clearIdentity()
        _ = try XCTUnwrap(waitForRequest("/sessions"))
        XCTAssertNil(UserDefaults.standard.string(forKey: "gleapGrant"))
        XCTAssertNil(GleapStubURLProtocol.requests(path: "/sessions").last?.header("Gleap-Grant"))
    }

    func testAnUnsignedIdentifyDropsTheGrant() throws {
        installSession(gleapId: "gid-user", gleapHash: "ghash-user", userId: "user-1")
        GleapStubURLProtocol.stub("POST", "/sessions/identify", signedReply(gleapId: "gid-user", grant: nil))
        let grants = (NSClassFromString("GleapGrant") as AnyObject).perform(NSSelectorFromString("sharedInstance")).takeUnretainedValue()
        _ = grants.perform(NSSelectorFromString("setGrant:forGleapId:"), with: grant(sid: "gid-user"), with: "gid-user")
        let data = GleapUserProperty()
        data.email = "ada@example.com"

        Gleap.identifyContact("user-1", andData: data)

        let identify = try XCTUnwrap(waitForRequest("/sessions/identify"))
        XCTAssertNotNil(identify.header("Gleap-Grant"))
        XCTAssertTrue(waitUntil { UserDefaults.standard.string(forKey: "gleapGrant") == nil })
    }

    func testIdentityMismatchRestartsAsAVisitorAndIdentifiesOnce() throws {
        installSession(gleapId: "gid-other", gleapHash: "ghash-other", userId: "someone-else")
        GleapStubURLProtocol.stub("POST", "/sessions", Self.sessionReply(gleapId: "gid-fresh", gleapHash: "ghash-fresh"))
        GleapStubURLProtocol.stub("POST", "/sessions/identify") { request in
            if request.header("Gleap-Id") == "gid-fresh" {
                return self.signedReply(gleapId: "gid-user", grant: self.grant(sid: "gid-user"))
            }
            return .json(["name": "BadRequest", "message": "identity_mismatch", "details": ["value": "identity_mismatch"]], status: 400)
        }
        let token = GleapUserJwtTests.jwt(["userId": "user-1", "exp": Date().timeIntervalSince1970 + 3600])

        Gleap.setUserJwt(token)

        XCTAssertTrue(waitUntil { self.sessions.currentSession?.gleapId == "gid-user" })
        let identifies = GleapStubURLProtocol.requests(path: "/sessions/identify")
        XCTAssertEqual(identifies.map { $0.header("Gleap-Id") }, ["gid-other", "gid-fresh"])
        XCTAssertEqual(identifies.last?.json?["userHash"] as? String, token)
        let start = try XCTUnwrap(GleapStubURLProtocol.requests(path: "/sessions").first)
        XCTAssertNil(start.header("Gleap-Id"), "the fresh visitor carries nothing of the old session")
    }

    func testSessionDurationIsSentWithTheIdentify() throws {
        installSession(gleapId: "gid-guest", gleapHash: "ghash-guest")
        GleapStubURLProtocol.stub("POST", "/sessions/identify", signedReply(gleapId: "gid-user", grant: grant(sid: "gid-user")))
        Gleap.setSessionDuration(3_600_000)
        defer { Gleap.setSessionDuration(0) }

        Gleap.setUserJwt(GleapUserJwtTests.jwt(["userId": "user-1"]))

        let identify = try XCTUnwrap(waitForRequest("/sessions/identify"))
        XCTAssertEqual(identify.json?["sessionDuration"] as? Int, 3_600_000)
    }

    private func signedWithoutGrant(gleapId: String) -> GleapStubReply {
        Self.sessionReply(gleapId: gleapId, gleapHash: "ghash-\(gleapId)", extra: [
            "userId": "user-1",
            "lang": GleapTranslationHelper.sharedInstance().language as Any,
            "identity": ["signed": false, "grant": NSNull(), "mode": "signed"],
        ])
    }

    func testAReturningUserOnASignedProjectSendsTheUnchangedIdentifyOnce() throws {
        GleapStubURLProtocol.stub("POST", "/sessions", signedWithoutGrant(gleapId: "gid-user"))
        // The server keeps answering without a grant: still only one identify.
        GleapStubURLProtocol.stub("POST", "/sessions/identify", signedWithoutGrant(gleapId: "gid-user"))
        UserDefaults.standard.set("gid-user", forKey: "gleapId")
        UserDefaults.standard.set("ghash-gid-user", forKey: "gleapHash")

        // The app identifies on launch exactly as last time, before the session is there.
        Gleap.identifyContact("user-1", andData: nil, andUserHash: "legacy-hash")
        sessions.startSession { _ in }

        let identify = try XCTUnwrap(waitForRequest("/sessions/identify"))
        XCTAssertEqual(identify.json?["userHash"] as? String, "legacy-hash")

        Gleap.identifyContact("user-1", andData: nil, andUserHash: "legacy-hash")
        sessions.startSession { _ in }
        XCTAssertTrue(waitUntil { GleapStubURLProtocol.requests(path: "/sessions").count == 2 })
        spin(0.5)
        XCTAssertEqual(GleapStubURLProtocol.requests(path: "/sessions/identify").count, 1)
    }

    func testAClassicProjectSkipsTheUnchangedIdentify() {
        installSession(gleapId: "gid-user", gleapHash: "ghash-user", userId: "user-1")
        GleapStubURLProtocol.stub("POST", "/sessions/identify", Self.sessionReply(gleapId: "gid-user", gleapHash: "ghash-user", extra: ["userId": "user-1"]))

        Gleap.identifyContact("user-1", andData: nil, andUserHash: "legacy-hash")

        spin(0.5)
        XCTAssertTrue(GleapStubURLProtocol.requests(path: "/sessions/identify").isEmpty)
    }

    func testAShortGrantIsRenewedAtHalfItsLifetime() throws {
        let grants = (NSClassFromString("GleapGrant") as AnyObject).perform(NSSelectorFromString("sharedInstance")).takeUnretainedValue() as! NSObject
        let now = Date().timeIntervalSince1970
        _ = grants.perform(NSSelectorFromString("setGrant:forGleapId:"),
                           with: GleapUserJwtTests.jwt(["sid": "gid-user", "iat": now, "exp": now + 120]),
                           with: "gid-user")
        typealias RenewBefore = @convention(c) (AnyObject, Selector, Double) -> Double
        let selector = NSSelectorFromString("renewBefore:")
        let method = try XCTUnwrap(class_getInstanceMethod(type(of: grants), selector))
        let renewBefore = unsafeBitCast(method_getImplementation(method), to: RenewBefore.self)(grants, selector, 300)
        XCTAssertEqual(renewBefore, 60, accuracy: 1)
    }
}
