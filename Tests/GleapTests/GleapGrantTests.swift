import XCTest
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
}
