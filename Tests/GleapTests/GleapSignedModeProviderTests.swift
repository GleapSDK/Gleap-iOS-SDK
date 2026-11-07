import XCTest
@testable import Gleap

/// Signed mode restored by the JWT provider alone: after a relaunch the SDK holds the session (and
/// maybe a grant the server no longer accepts) but not the token `setUserJwt` was given, which lives
/// in memory only. When the session answer says Signed mode without a grant for an identified
/// session, the provider is asked once per app launch and its token is sent like one from `setUserJwt`.
final class GleapSignedModeProviderTests: GleapNetworkTestCase {
    private var sessions: GleapSessionHelper { GleapSessionHelper.sharedInstance() }
    private let calls = GleapBox<Int>()

    override func setUp() {
        super.setUp()
        resetGate()
        calls.value = 0
        // The last launch identified user-1 on this session; the token was not stored.
        UserDefaults.standard.set("gid-user", forKey: "gleapId")
        UserDefaults.standard.set("ghash-gid-user", forKey: "gleapHash")
    }

    override func tearDown() {
        super.tearDown()
        resetGate()
    }

    private func resetGate() {
        let gateClass = NSClassFromString("GleapUserJwtProviderGate") as! NSObject.Type
        sessions.setValue(gateClass.init(), forKey: "userJwtGate")
        sessions.setValue(nil, forKey: "sentUserJwt")
        sessions.setValue(nil, forKey: "sentUserJwtGleapId")
    }

    private func token(_ userId: String = "user-1") -> String {
        GleapUserJwtTests.jwt(["userId": userId, "exp": Date().timeIntervalSince1970 + 3600])
    }

    private func grant(sid: String) -> String {
        GleapUserJwtTests.jwt(["sid": sid, "uid": "user-1", "kind": "jwt", "exp": Date().timeIntervalSince1970 + 3600])
    }

    private func signedWithoutGrant(userId: String? = "user-1") -> GleapStubReply {
        var extra: [String: Any] = [
            "lang": GleapTranslationHelper.sharedInstance().language as Any,
            "identity": ["signed": false, "grant": NSNull(), "mode": "signed"],
        ]
        if let userId = userId {
            extra["userId"] = userId
        }
        return Self.sessionReply(gleapId: "gid-user", gleapHash: "ghash-gid-user", extra: extra)
    }

    private func signedWithGrant() -> GleapStubReply {
        Self.sessionReply(gleapId: "gid-user", gleapHash: "ghash-gid-user", extra: [
            "userId": "user-1",
            "identity": ["signed": true, "grant": grant(sid: "gid-user")],
        ])
    }

    private func setProvider(answer: String?) {
        Gleap.setUserJwtProvider { completion in
            self.calls.value = (self.calls.value ?? 0) + 1
            completion(answer)
        }
    }

    private func hasGrant() -> Bool {
        let grants = (NSClassFromString("GleapGrant") as AnyObject).perform(NSSelectorFromString("sharedInstance")).takeUnretainedValue() as! NSObject
        return grants.perform(NSSelectorFromString("grantForGleapId:"), with: "gid-user")?.takeUnretainedValue() != nil
    }

    private func loadSession(count: Int) {
        sessions.startSession { _ in }
        XCTAssertTrue(waitUntil { GleapStubURLProtocol.requests(path: "/sessions").count == count })
        spin(0.4)
    }

    func testTheProviderIsAskedOnceAndTheIdentifyCarriesItsToken() throws {
        let fresh = token()
        GleapStubURLProtocol.stub("POST", "/sessions", signedWithoutGrant())
        GleapStubURLProtocol.stub("POST", "/sessions/identify", signedWithGrant())
        setProvider(answer: fresh)

        sessions.startSession { _ in }

        let identify = try XCTUnwrap(waitForRequest("/sessions/identify"))
        XCTAssertEqual(identify.json?["userHash"] as? String, fresh)
        XCTAssertTrue(waitUntil { self.hasGrant() })
        XCTAssertEqual(calls.value, 1)
    }

    func testRepeatedUnsignedAnswersNeverLoop() {
        GleapStubURLProtocol.stub("POST", "/sessions", signedWithoutGrant())
        // The server keeps answering without a grant.
        GleapStubURLProtocol.stub("POST", "/sessions/identify", signedWithoutGrant())
        setProvider(answer: token())

        loadSession(count: 1)
        loadSession(count: 2)
        loadSession(count: 3)

        XCTAssertEqual(calls.value, 1)
        XCTAssertEqual(GleapStubURLProtocol.requests(path: "/sessions/identify").count, 1)
    }

    func testANilTokenSendsNothingAndIsNotAskedAgain() {
        GleapStubURLProtocol.stub("POST", "/sessions", signedWithoutGrant())
        setProvider(answer: nil)
        sessions.setValue(0, forKeyPath: "userJwtGate.pauseAfterFailure")

        loadSession(count: 1)
        loadSession(count: 2)

        XCTAssertEqual(calls.value, 1)
        XCTAssertTrue(GleapStubURLProtocol.requests(path: "/sessions/identify").isEmpty)
        XCTAssertNil(sessions.openIdentityAction)
    }

    func testWithoutAProviderNothingIsSent() {
        GleapStubURLProtocol.stub("POST", "/sessions", signedWithoutGrant())

        loadSession(count: 1)

        assertNoRequest("/sessions/identify")
    }

    func testAProviderSetAfterTheSessionAnswerIsAsked() throws {
        let fresh = token()
        GleapStubURLProtocol.stub("POST", "/sessions", signedWithoutGrant())
        GleapStubURLProtocol.stub("POST", "/sessions/identify", signedWithGrant())
        loadSession(count: 1)
        XCTAssertTrue(GleapStubURLProtocol.requests(path: "/sessions/identify").isEmpty)

        setProvider(answer: fresh)

        let identify = try XCTUnwrap(waitForRequest("/sessions/identify"))
        XCTAssertEqual(identify.json?["userHash"] as? String, fresh)
        XCTAssertEqual(calls.value, 1)
    }

    func testAClassicAnswerAsksNothing() {
        GleapStubURLProtocol.stub("POST", "/sessions", Self.sessionReply(gleapId: "gid-user", gleapHash: "ghash-gid-user", extra: ["userId": "user-1"]))
        setProvider(answer: token())

        loadSession(count: 1)

        XCTAssertEqual(calls.value, 0)
        assertNoRequest("/sessions/identify")
    }

    func testAnAnonymousSessionAsksNothing() {
        GleapStubURLProtocol.stub("POST", "/sessions", signedWithoutGrant(userId: nil))
        setProvider(answer: token())

        loadSession(count: 1)

        XCTAssertEqual(calls.value, 0)
        assertNoRequest("/sessions/identify")
    }

    func testALiveGrantAsksNothing() {
        // A valid grant: the server answers without `identity` and the grant stays.
        let grants = (NSClassFromString("GleapGrant") as AnyObject).perform(NSSelectorFromString("sharedInstance")).takeUnretainedValue() as! NSObject
        _ = grants.perform(NSSelectorFromString("setGrant:forGleapId:"), with: grant(sid: "gid-user"), with: "gid-user")
        GleapStubURLProtocol.stub("POST", "/sessions", Self.sessionReply(gleapId: "gid-user", gleapHash: "ghash-gid-user", extra: ["userId": "user-1"]))
        setProvider(answer: token())

        loadSession(count: 1)

        XCTAssertEqual(calls.value, 0)
        XCTAssertTrue(hasGrant())
    }

    func testATokenFromTheAppIsSentInsteadOfAskingTheProvider() throws {
        let appToken = token()
        GleapStubURLProtocol.stub("POST", "/sessions", signedWithoutGrant())
        GleapStubURLProtocol.stub("POST", "/sessions/identify", signedWithGrant())
        setProvider(answer: token())

        Gleap.setUserJwt(appToken)
        sessions.startSession { _ in }

        let identify = try XCTUnwrap(waitForRequest("/sessions/identify"))
        XCTAssertEqual(identify.json?["userHash"] as? String, appToken)
        spin(0.4)
        XCTAssertEqual(calls.value, 0)
        XCTAssertEqual(GleapStubURLProtocol.requests(path: "/sessions/identify").count, 1)
    }

    func testALogoutWhileTheProviderRunsDropsItsToken() {
        let loads = GleapBox<Int>()
        loads.value = 0
        GleapStubURLProtocol.stub("POST", "/sessions") { _ in
            loads.value = (loads.value ?? 0) + 1
            // After the logout the server hands out a guest session.
            return loads.value == 1 ? self.signedWithoutGrant() : Self.sessionReply(gleapId: "gid-guest", gleapHash: "ghash-guest")
        }
        let pending = GleapBox<(String?) -> Void>()
        Gleap.setUserJwtProvider { completion in
            self.calls.value = (self.calls.value ?? 0) + 1
            pending.value = completion
        }

        sessions.startSession { _ in }
        XCTAssertTrue(waitUntil { pending.value != nil })

        sessions.clearSession()
        XCTAssertTrue(waitUntil { self.sessions.currentSession?.gleapId == "gid-guest" })
        pending.value?(token())

        assertNoRequest("/sessions/identify")
        XCTAssertEqual(calls.value, 1)
    }

    // MARK: - Project ID

    func testTheDeprecatedTokenPropertyIsAnAliasOfProjectId() {
        let gleap = Gleap.sharedInstance()
        gleap.projectId = "project-id-1"
        XCTAssertEqual(gleap.value(forKey: "token") as? String, "project-id-1")
        gleap.setValue("project-id-2", forKey: "token")
        XCTAssertEqual(gleap.projectId, "project-id-2")
        // The Swift names of the initializers (not called: initialize starts the SDK).
        let initialize: (String) -> Void = Gleap.initialize(withProjectId:)
        _ = initialize
    }
}
