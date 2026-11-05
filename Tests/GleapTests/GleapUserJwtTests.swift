import XCTest
import ObjectiveC
@testable import Gleap

/// Customer identity: `setUserJwt`, the JWT provider and `setAuthTokens`. The token decoding and
/// the provider's timing rules are internal to the SDK and reached through the Objective-C runtime.
final class GleapUserJwtTests: GleapNetworkTestCase {
    private typealias IsUserJwt = @convention(c) (AnyClass, Selector, AnyObject?) -> Bool
    private typealias RefusalCode = @convention(c) (AnyClass, Selector, Int, NSData?) -> Unmanaged<NSString>?
    private typealias ExpiresWithin = @convention(c) (AnyClass, Selector, AnyObject?, Double, NSDate) -> Bool

    private var sessions: GleapSessionHelper { GleapSessionHelper.sharedInstance() }

    override func setUp() {
        super.setUp()
        resetIdentityState()
    }

    override func tearDown() {
        super.tearDown()
        resetIdentityState()
    }

    private func resetIdentityState() {
        let gateClass = NSClassFromString("GleapUserJwtProviderGate") as! NSObject.Type
        sessions.setValue(gateClass.init(), forKey: "userJwtGate")
        sessions.setValue(nil, forKey: "sentUserJwt")
        sessions.setValue(nil, forKey: "sentUserJwtGleapId")
        sessions.setValue(nil, forKey: "authTokensSentFor")
        (sessions.value(forKey: "authTokens") as? NSMutableDictionary)?.removeAllObjects()
        (sessions.value(forKey: "removedAuthTokens") as? NSMutableSet)?.removeAllObjects()
    }

    // MARK: - Tokens

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// An unsigned-looking JWT with `payload` (the SDK never checks the signature).
    static func jwt(_ payload: [String: Any], signature: String = "c2lnbmF0dXJl") -> String {
        let header = base64url(try! JSONSerialization.data(withJSONObject: ["alg": "HS256", "typ": "JWT"]))
        let body = base64url(try! JSONSerialization.data(withJSONObject: payload))
        return "\(header).\(body).\(signature)"
    }

    private func jwtClass() throws -> AnyClass {
        try XCTUnwrap(NSClassFromString("GleapUserJwt"))
    }

    private func userId(of token: String) throws -> String? {
        let cls: AnyObject = try jwtClass()
        return cls.perform(NSSelectorFromString("userIdOf:"), with: token)?.takeUnretainedValue() as? String
    }

    private func isUserJwt(_ token: String) throws -> Bool {
        let cls: AnyClass = try jwtClass()
        let selector = NSSelectorFromString("isUserJwt:")
        let method = try XCTUnwrap(class_getClassMethod(cls, selector))
        return unsafeBitCast(method_getImplementation(method), to: IsUserJwt.self)(cls, selector, token as NSString)
    }

    func testTheUserIdIsReadFromThePayload() throws {
        XCTAssertEqual(try userId(of: Self.jwt(["userId": "user-1", "email": "ada@example.com"])), "user-1")
        XCTAssertEqual(try userId(of: Self.jwt(["user_id": 42])), "42")
        XCTAssertEqual(try userId(of: Self.jwt(["userId": "Jürgen ✓"])), "Jürgen ✓")
        XCTAssertNil(try userId(of: Self.jwt(["email": "ada@example.com"])))
        XCTAssertNil(try userId(of: Self.jwt(["userId": ""])))
        XCTAssertNil(try userId(of: Self.jwt(["userId": true])))
        XCTAssertNil(try userId(of: Self.jwt(["userId": ["id": 1]])))
    }

    func testOnlyThreeBase64UrlSegmentsOfAtMost4096CharactersAreAJwt() throws {
        let token = Self.jwt(["userId": "user-1"])
        XCTAssertTrue(try isUserJwt(token))
        XCTAssertFalse(try isUserJwt("a3f1c9"))                         // a legacy hash
        XCTAssertFalse(try isUserJwt("aaa.bbb"))
        XCTAssertFalse(try isUserJwt("aaa..ccc"))
        XCTAssertFalse(try isUserJwt("aa+a.bbb.ccc"))
        XCTAssertFalse(try isUserJwt(Self.jwt(["userId": "user-1"], signature: String(repeating: "s", count: 4096))))
        XCTAssertNil(try userId(of: "not.a.jwt"))
    }

    func testOnlyA401NamingTheCodeIsATokenRefusal() throws {
        let cls: AnyClass = try jwtClass()
        let selector = NSSelectorFromString("refusalCodeForStatus:body:")
        let method = try XCTUnwrap(class_getClassMethod(cls, selector))
        let refusal = unsafeBitCast(method_getImplementation(method), to: RefusalCode.self)
        func code(_ status: Int, _ text: String) -> String? {
            refusal(cls, selector, status, text.data(using: .utf8)! as NSData)?.takeUnretainedValue() as String?
        }
        XCTAssertEqual(code(401, #"{"name":"Unauthorized","details":{"value":"token_expired"}}"#), "token_expired")
        XCTAssertEqual(code(401, #"{"message":"token_invalid: bad signature"}"#), "token_invalid")
        XCTAssertNil(code(401, #"{"details":{"value":"signature_required"}}"#))
        XCTAssertNil(code(400, #"{"details":{"value":"token_expired"}}"#))
    }

    func testExpiryWindow() throws {
        let cls: AnyClass = try jwtClass()
        let selector = NSSelectorFromString("token:expiresWithin:of:")
        let method = try XCTUnwrap(class_getClassMethod(cls, selector))
        let expiresWithin = unsafeBitCast(method_getImplementation(method), to: ExpiresWithin.self)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(expiresWithin(cls, selector, Self.jwt(["userId": "u", "exp": 1_800_000_000 + 60]) as NSString, 300, now as NSDate))
        XCTAssertFalse(expiresWithin(cls, selector, Self.jwt(["userId": "u", "exp": 1_800_000_000 + 3600]) as NSString, 300, now as NSDate))
        XCTAssertFalse(expiresWithin(cls, selector, Self.jwt(["userId": "u"]) as NSString, 300, now as NSDate), "no exp never expires")
    }

    // MARK: - setUserJwt

    func testSetUserJwtSendsTheTokenAsUserHashAndNoContactFields() throws {
        installSession(gleapId: "gid-guest", gleapHash: "ghash-guest")
        let token = Self.jwt(["userId": "user-1", "name": "Ada", "exp": Date().timeIntervalSince1970 + 3600])
        GleapStubURLProtocol.stub("POST", "/sessions/identify",
                                  Self.sessionReply(gleapId: "gid-user", gleapHash: "ghash-user", extra: ["userId": "user-1", "name": "Ada"]))

        Gleap.setUserJwt(token)

        let request = try XCTUnwrap(waitForRequest("/sessions/identify"))
        let body = try XCTUnwrap(request.json)
        XCTAssertEqual(body["userId"] as? String, "user-1")
        XCTAssertEqual(body["userHash"] as? String, token)
        XCTAssertEqual(Set(body.keys), ["userId", "userHash", "lang", "platform", "deviceType"])
        XCTAssertTrue(waitUntil { self.sessions.currentSession?.gleapId == "gid-user" })
        // Memory only: the token is never stored.
        XCTAssertFalse(UserDefaults.standard.dictionaryRepresentation().values.contains { ($0 as? String) == token })
    }

    func testAnInvalidTokenIsRefusedWithoutARequest() {
        installSession()

        Gleap.setUserJwt("not-a-jwt")
        Gleap.setUserJwt(Self.jwt(["email": "ada@example.com"]))

        assertNoRequest("/sessions/identify")
    }

    func testTheSameTokenIsSentOnceAndANewTokenAgain() throws {
        installSession(gleapId: "gid-guest", gleapHash: "ghash-guest")
        let lang = GleapTranslationHelper.sharedInstance().language
        GleapStubURLProtocol.stub("POST", "/sessions/identify",
                                  Self.sessionReply(gleapId: "gid-user", gleapHash: "ghash-user", extra: ["userId": "user-1", "lang": lang]))
        let first = Self.jwt(["userId": "user-1", "exp": Date().timeIntervalSince1970 + 3600])
        let second = Self.jwt(["userId": "user-1", "exp": Date().timeIntervalSince1970 + 7200])

        Gleap.setUserJwt(first)
        XCTAssertTrue(waitUntil { self.sessions.currentSession?.gleapId == "gid-user" })
        Gleap.setUserJwt(first)
        spin(0.5)
        XCTAssertEqual(GleapStubURLProtocol.requests(path: "/sessions/identify").count, 1, "an unchanged token is not sent again")

        Gleap.setUserJwt(second)
        XCTAssertTrue(waitUntil { GleapStubURLProtocol.requests(path: "/sessions/identify").count == 2 })
        XCTAssertEqual(GleapStubURLProtocol.requests(path: "/sessions/identify").last?.json?["userHash"] as? String, second)
    }

    func testAnInvalidTokenRefusalKeepsTheSession() throws {
        installSession(gleapId: "gid-guest", gleapHash: "ghash-guest")
        GleapStubURLProtocol.stub("POST", "/sessions/identify",
                                  .json(["name": "Unauthorized", "message": "token_invalid", "details": ["value": "token_invalid"]], status: 401))

        Gleap.setUserJwt(Self.jwt(["userId": "user-1"]))

        _ = try XCTUnwrap(waitForRequest("/sessions/identify"))
        assertNoRequest("/sessions")
        XCTAssertEqual(sessions.currentSession?.gleapId, "gid-guest")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "gleapId"), "gid-guest")
    }

    func testAnExpiredTokenAsksTheProviderAndRetriesOnce() throws {
        installSession(gleapId: "gid-guest", gleapHash: "ghash-guest")
        let expired = Self.jwt(["userId": "user-1", "exp": Date().timeIntervalSince1970 - 60])
        let fresh = Self.jwt(["userId": "user-1", "exp": Date().timeIntervalSince1970 + 3600])
        GleapStubURLProtocol.stub("POST", "/sessions/identify") { request in
            if request.json?["userHash"] as? String == fresh {
                return Self.sessionReply(gleapId: "gid-user", gleapHash: "ghash-user", extra: ["userId": "user-1"])
            }
            return .json(["message": "token_expired", "details": ["value": "token_expired"]], status: 401)
        }
        let calls = GleapBox<Int>()
        calls.value = 0
        Gleap.setUserJwtProvider { completion in
            calls.value = (calls.value ?? 0) + 1
            completion(fresh)
        }

        Gleap.setUserJwt(expired)

        XCTAssertTrue(waitUntil { self.sessions.currentSession?.gleapId == "gid-user" })
        let identifies = GleapStubURLProtocol.requests(path: "/sessions/identify")
        XCTAssertEqual(identifies.map { $0.json?["userHash"] as? String }, [expired, fresh])
        XCTAssertEqual(calls.value, 1)
        XCTAssertTrue(GleapStubURLProtocol.requests(path: "/sessions").isEmpty, "the session is never cleared")
    }

    // MARK: - Provider rules

    private func gate() -> NSObject {
        sessions.value(forKey: "userJwtGate") as! NSObject
    }

    private func requestToken(_ gate: NSObject, _ result: GleapBox<String>, _ done: GleapBox<Bool>) {
        let completion: @convention(block) (NSString?) -> Void = { token in
            result.value = token as String?
            done.value = true
        }
        gate.perform(NSSelectorFromString("requestToken:"), with: unsafeBitCast(completion, to: AnyObject.self))
    }

    func testOneProviderCallAtATime() {
        let calls = GleapBox<Int>()
        calls.value = 0
        let pending = GleapBox<(String?) -> Void>()
        Gleap.setUserJwtProvider { completion in
            calls.value = (calls.value ?? 0) + 1
            pending.value = completion
        }
        let gate = gate()
        let first = GleapBox<String>(), firstDone = GleapBox<Bool>()
        let second = GleapBox<String>(), secondDone = GleapBox<Bool>()
        requestToken(gate, first, firstDone)
        requestToken(gate, second, secondDone)
        XCTAssertTrue(waitUntil { pending.value != nil })

        let token = Self.jwt(["userId": "user-1"])
        pending.value?(token)

        XCTAssertTrue(waitUntil { firstDone.value == true && secondDone.value == true })
        XCTAssertEqual(calls.value, 1)
        XCTAssertEqual(first.value, token)
        XCTAssertEqual(second.value, token)
    }

    func testATimeoutCountsAsAFailureAndPausesTheProvider() {
        let calls = GleapBox<Int>()
        calls.value = 0
        Gleap.setUserJwtProvider { _ in
            calls.value = (calls.value ?? 0) + 1   // never answers
        }
        let gate = gate()
        gate.setValue(0.2, forKey: "timeout")
        gate.setValue(1.0, forKey: "pauseAfterFailure")

        let first = GleapBox<String>(), firstDone = GleapBox<Bool>()
        requestToken(gate, first, firstDone)
        XCTAssertTrue(waitUntil { firstDone.value == true })
        XCTAssertNil(first.value)

        // Within the pause the provider is not asked.
        let second = GleapBox<String>(), secondDone = GleapBox<Bool>()
        requestToken(gate, second, secondDone)
        XCTAssertTrue(waitUntil { secondDone.value == true })
        XCTAssertNil(second.value)
        XCTAssertEqual(calls.value, 1)

        // After it, it is.
        spin(1.1)
        let third = GleapBox<String>(), thirdDone = GleapBox<Bool>()
        requestToken(gate, third, thirdDone)
        XCTAssertTrue(waitUntil { calls.value == 2 })
    }

    func testAProviderReturningNoJwtFails() {
        Gleap.setUserJwtProvider { completion in completion("not-a-jwt") }
        let gate = gate()
        let result = GleapBox<String>(), done = GleapBox<Bool>()
        requestToken(gate, result, done)
        XCTAssertTrue(waitUntil { done.value == true })
        XCTAssertNil(result.value)
        XCTAssertGreaterThan((gate.value(forKey: "failedAt") as? Double) ?? 0, 0)
    }

    // MARK: - Auth tokens

    func testSetAuthTokensPostsTheTokensAndNullRemovesOne() throws {
        installSession(gleapId: "gid-user", gleapHash: "ghash-user", userId: "user-1")
        GleapStubURLProtocol.stub("POST", "/sessions/auth-tokens", .json(["names": ["backend"]]))

        Gleap.setAuthTokens(["backend": "secret-1", "bad name": "x", "crm": NSNull()])

        let request = try XCTUnwrap(waitForRequest("/sessions/auth-tokens"))
        XCTAssertEqual(request.header("Api-Token"), Self.sdkKey)
        XCTAssertEqual(request.header("Gleap-Id"), "gid-user")
        XCTAssertEqual(request.header("Gleap-Hash"), "ghash-user")
        let tokens = try XCTUnwrap(request.json?["tokens"] as? [String: Any])
        XCTAssertEqual(tokens["backend"] as? String, "secret-1")
        XCTAssertTrue(tokens["crm"] is NSNull)
        XCTAssertNil(tokens["bad name"])
    }

    func testAuthTokensAreResentAfterASignedIdentifyOnANewSession() throws {
        installSession(gleapId: "gid-guest", gleapHash: "ghash-guest")
        GleapStubURLProtocol.stub("POST", "/sessions/auth-tokens") { request in
            request.header("Gleap-Id") == "gid-user" ? .json(["names": ["backend"]]) : .json(["details": ["value": "signature_required"]], status: 401)
        }
        GleapStubURLProtocol.stub("POST", "/sessions/identify",
                                  Self.sessionReply(gleapId: "gid-user", gleapHash: "ghash-user", extra: ["userId": "user-1"]))

        Gleap.setAuthTokens(["backend": "secret-1"])
        XCTAssertTrue(waitUntil { GleapStubURLProtocol.requests(path: "/sessions/auth-tokens").count == 1 })
        // The 401 keeps the session and the tokens.
        XCTAssertEqual(sessions.currentSession?.gleapId, "gid-guest")

        Gleap.setUserJwt(Self.jwt(["userId": "user-1"]))

        let resent = try XCTUnwrap(waitForRequest("/sessions/auth-tokens") { $0.header("Gleap-Id") == "gid-user" })
        XCTAssertEqual((resent.json?["tokens"] as? [String: Any])?["backend"] as? String, "secret-1")
    }

    func testClearIdentityDropsTheAuthTokensButKeepsTheProvider() {
        installSession(gleapId: "gid-user", gleapHash: "ghash-user", userId: "user-1")
        GleapStubURLProtocol.stub("POST", "/sessions/auth-tokens", .json(["names": ["backend"]]))
        GleapStubURLProtocol.stub("POST", "/sessions", Self.sessionReply(gleapId: "gid-guest", gleapHash: "ghash-guest"))
        Gleap.setUserJwtProvider { completion in completion(nil) }
        Gleap.setAuthTokens(["backend": "secret-1"])
        XCTAssertTrue(waitUntil { GleapStubURLProtocol.requests(path: "/sessions/auth-tokens").count == 1 })

        Gleap.clearIdentity()

        XCTAssertEqual((sessions.value(forKey: "authTokens") as? NSDictionary)?.count, 0)
        XCTAssertNil(sessions.value(forKey: "sentUserJwt"))
        XCTAssertNotNil(gate().value(forKey: "provider"))
    }
}
