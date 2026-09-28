import XCTest
@testable import Gleap

/// Only a session the server handed out replaces the stored identity; a request that failed
/// leaves it alone. Losing it turns an identified user into a new guest without their conversations.
final class GleapIdentityPreservationTests: GleapNetworkTestCase {
    private let overloaded = GleapStubReply.json(["status": "overloaded", "reason": "request-budget"], status: 503, headers: ["Retry-After": "2"])
    private let serverFailure = GleapStubReply.json(["error": ["statusCode": 500, "title": "Internal Server Error", "message": "Failed"]], status: 500)
    private let tooLarge = GleapStubReply.json(["error": ["statusCode": 413, "message": "Request body is too large"]], status: 413)
    private let notAuthorized = GleapStubReply.json(["error": ["statusCode": 401, "title": "Not Authorized", "message": ""]], status: 401)

    private func startSession() -> Bool? {
        let result = GleapBox<Bool>()
        GleapSessionHelper.sharedInstance().startSession { success in
            result.value = success
        }
        waitUntil { result.value != nil }
        return result.value
    }

    private func user() -> GleapUserProperty {
        let user = GleapUserProperty()
        user.name = "Ada Lovelace"
        user.email = "ada@example.com"
        return user
    }

    private func assertStoredIdentity(_ gleapId: String, _ gleapHash: String, _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(UserDefaults.standard.string(forKey: "gleapId"), gleapId, context, file: file, line: line)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "gleapHash"), gleapHash, context, file: file, line: line)
    }

    private func startOver() {
        resetSDKState()
        GleapStubURLProtocol.reset()
    }

    func testFailedSessionStartKeepsTheStoredIdentity() {
        let answers: [(String, GleapStubReply)] = [
            ("overloaded", overloaded),
            ("server failure", serverFailure),
            ("offline", .failure(.notConnectedToInternet)),
            ("answer without a session", .json(["status": "ok"], status: 201)),
        ]
        for (name, reply) in answers {
            startOver()
            UserDefaults.standard.set("gid-stored", forKey: "gleapId")
            UserDefaults.standard.set("ghash-stored", forKey: "gleapHash")
            GleapStubURLProtocol.stub("POST", "/sessions", reply)

            XCTAssertEqual(startSession(), false, name)

            assertStoredIdentity("gid-stored", "ghash-stored", name)
            XCTAssertNil(GleapSessionHelper.sharedInstance().currentSession, name)
            XCTAssertTrue(spy.calls("registerPushMessageGroup").isEmpty, name)
        }
    }

    func testFailedIdentifyKeepsTheIdentity() {
        let answers: [(String, GleapStubReply)] = [
            ("overloaded", overloaded),
            ("server failure", serverFailure),
            ("offline", .failure(.notConnectedToInternet)),
            ("answer without a session", .json([String: Any](), status: 201)),
        ]
        for (name, reply) in answers {
            startOver()
            installSession(gleapId: "gid-guest", gleapHash: "ghash-guest")
            GleapStubURLProtocol.stub("POST", "/sessions/identify", reply)

            Gleap.identifyContact("user-1", andData: user(), andUserHash: "user-hash-1")

            XCTAssertNotNil(waitForRequest("/sessions/identify"), name)
            spin(0.5)
            assertStoredIdentity("gid-guest", "ghash-guest", name)
            XCTAssertEqual(GleapSessionHelper.sharedInstance().currentSession?.gleapId, "gid-guest", name)
            XCTAssertEqual(GleapSessionHelper.sharedInstance().currentSession?.gleapHash, "ghash-guest", name)
            XCTAssertTrue(GleapStubURLProtocol.requests(path: "/sessions").isEmpty, "\(name): no new guest session")
            XCTAssertTrue(spy.calls("unregisterPushMessageGroup").isEmpty, name)
        }
    }

    func testIdentifyRefusedWithAnErrorListClearsTheIdentity() throws {
        // Like an `error` answer (GleapIdentityTests), an `errors` answer means the server refused
        // this identity; the SDK drops it and starts over as a guest. This is deliberate.
        installSession(gleapId: "gid-guest", gleapHash: "ghash-guest")
        GleapStubURLProtocol.stub("POST", "/sessions/identify", .json(["errors": [["message": "userId is required"]]], status: 400))
        GleapStubURLProtocol.stub("POST", "/sessions", Self.sessionReply(gleapId: "gid-fresh", gleapHash: "ghash-fresh"))

        Gleap.identifyContact("user-1", andData: user())

        let restart = try XCTUnwrap(waitForRequest("/sessions"))
        XCTAssertNil(restart.header("Gleap-Id"))
        XCTAssertTrue(waitUntil { UserDefaults.standard.string(forKey: "gleapId") == "gid-fresh" })
    }

    func testFailedContactUpdateKeepsTheIdentity() {
        let answers: [(String, GleapStubReply)] = [
            ("overloaded", overloaded),
            ("server failure", serverFailure),
            ("too large", tooLarge),
            ("not authorized", notAuthorized),
            ("offline", .failure(.notConnectedToInternet)),
        ]
        for (name, reply) in answers {
            startOver()
            installSession(gleapId: "gid-user", gleapHash: "ghash-user", userId: "user-1")
            GleapStubURLProtocol.stub("POST", "/sessions/partialupdate", reply)
            let update = GleapUserProperty()
            update.plan = "Pro"

            Gleap.updateContact(update)

            XCTAssertNotNil(waitForRequest("/sessions/partialupdate"), name)
            spin(0.5)
            assertStoredIdentity("gid-user", "ghash-user", name)
            XCTAssertEqual(GleapSessionHelper.sharedInstance().currentSession?.gleapId, "gid-user", name)
            XCTAssertEqual(GleapSessionHelper.sharedInstance().currentSession?.userId, "user-1", name)
            XCTAssertTrue(Gleap.isUserIdentified(), name)
        }
    }
}
