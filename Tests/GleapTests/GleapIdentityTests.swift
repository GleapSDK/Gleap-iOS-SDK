import XCTest
@testable import Gleap

/// Session identity: which credentials go to the server, and what is kept on the device.
final class GleapIdentityTests: GleapNetworkTestCase {
    private func startSession() -> Bool? {
        let result = GleapBox<Bool>()
        GleapSessionHelper.sharedInstance().startSession { success in
            result.value = success
        }
        waitUntil { result.value != nil }
        return result.value
    }

    private func user(name: String = "Ada Lovelace", email: String = "ada@example.com", customData: [String: Any]? = nil) -> GleapUserProperty {
        let user = GleapUserProperty()
        user.name = name
        user.email = email
        if let customData = customData {
            user.customData = customData
        }
        return user
    }

    func testFirstSessionIsAGuestSessionAndIsStored() throws {
        GleapStubURLProtocol.stub("POST", "/sessions", Self.sessionReply(gleapId: "gid-new", gleapHash: "ghash-new"))

        XCTAssertEqual(startSession(), true)

        let request = try XCTUnwrap(GleapStubURLProtocol.requests(path: "/sessions").first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url.host, "api.gleap.test")
        XCTAssertEqual(request.header("Api-Token"), Self.sdkKey)
        XCTAssertNil(request.header("Gleap-Id"))
        XCTAssertNil(request.header("Gleap-Hash"))
        let body = try XCTUnwrap(request.json)
        XCTAssertEqual(body["platform"] as? String, "iOS")
        XCTAssertEqual(body["deviceType"] as? String, "mobile")
        XCTAssertEqual(body["lang"] as? String, GleapTranslationHelper.sharedInstance().language)

        XCTAssertEqual(UserDefaults.standard.string(forKey: "gleapId"), "gid-new")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "gleapHash"), "ghash-new")
        XCTAssertEqual(GleapSessionHelper.sharedInstance().currentSession?.gleapId, "gid-new")
        XCTAssertEqual(GleapSessionHelper.sharedInstance().currentSession?.gleapHash, "ghash-new")
    }

    func testStoredGuestIdentityIsSentWhenTheSessionRestarts() throws {
        UserDefaults.standard.set("gid-stored", forKey: "gleapId")
        UserDefaults.standard.set("ghash-stored", forKey: "gleapHash")
        GleapStubURLProtocol.stub("POST", "/sessions", Self.sessionReply(gleapId: "gid-stored", gleapHash: "ghash-stored"))

        XCTAssertEqual(startSession(), true)

        let request = try XCTUnwrap(GleapStubURLProtocol.requests(path: "/sessions").first)
        XCTAssertEqual(request.header("Gleap-Id"), "gid-stored")
        XCTAssertEqual(request.header("Gleap-Hash"), "ghash-stored")
    }

    func testAnIncompleteStoredIdentityIsNotSent() throws {
        UserDefaults.standard.set("gid-stored", forKey: "gleapId")
        GleapStubURLProtocol.stub("POST", "/sessions", Self.sessionReply(gleapId: "gid-new", gleapHash: "ghash-new"))

        XCTAssertEqual(startSession(), true)

        let request = try XCTUnwrap(GleapStubURLProtocol.requests(path: "/sessions").first)
        XCTAssertNil(request.header("Gleap-Id"))
        XCTAssertNil(request.header("Gleap-Hash"))
    }

    func testIdentifySendsTheUserHashAndSwitchesThePushGroup() throws {
        installSession(gleapId: "gid-guest", gleapHash: "ghash-guest")
        GleapStubURLProtocol.stub("POST", "/sessions/identify",
                                  Self.sessionReply(gleapId: "gid-user", gleapHash: "ghash-user", extra: ["userId": "user-1", "name": "Ada Lovelace"]))

        Gleap.identifyContact("user-1", andData: user(customData: ["plan_level": "gold"]), andUserHash: "user-hash-1")

        let request = try XCTUnwrap(waitForRequest("/sessions/identify"))
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.header("Api-Token"), Self.sdkKey)
        XCTAssertEqual(request.header("Gleap-Id"), "gid-guest")
        XCTAssertEqual(request.header("Gleap-Hash"), "ghash-guest")
        let body = try XCTUnwrap(request.json)
        XCTAssertEqual(body["userId"] as? String, "user-1")
        XCTAssertEqual(body["userHash"] as? String, "user-hash-1")
        XCTAssertEqual(body["name"] as? String, "Ada Lovelace")
        XCTAssertEqual(body["email"] as? String, "ada@example.com")
        XCTAssertEqual(body["plan_level"] as? String, "gold")
        XCTAssertEqual(body["platform"] as? String, "iOS")
        XCTAssertEqual(body["deviceType"] as? String, "mobile")
        XCTAssertEqual(body["lang"] as? String, GleapTranslationHelper.sharedInstance().language)

        XCTAssertTrue(waitUntil { UserDefaults.standard.string(forKey: "gleapHash") == "ghash-user" })
        XCTAssertEqual(UserDefaults.standard.string(forKey: "gleapId"), "gid-user")
        XCTAssertEqual(GleapSessionHelper.sharedInstance().currentSession?.userId, "user-1")
        XCTAssertTrue(Gleap.isUserIdentified())
        XCTAssertTrue(waitUntil { !self.spy.calls("registerPushMessageGroup").isEmpty })
        XCTAssertEqual(spy.calls("unregisterPushMessageGroup").map { $0.payload as? String }, ["gleapuser-ghash-guest"])
        XCTAssertEqual(spy.calls("registerPushMessageGroup").map { $0.payload as? String }, ["gleapuser-ghash-user"])
    }

    func testIdentifyWithoutAUserHashSendsNoHash() throws {
        installSession()
        GleapStubURLProtocol.stub("POST", "/sessions/identify", Self.sessionReply(gleapId: "gid-user", gleapHash: "ghash-user"))

        Gleap.identifyContact("user-1", andData: user())

        let body = try XCTUnwrap(waitForRequest("/sessions/identify")?.json)
        XCTAssertEqual(body["userId"] as? String, "user-1")
        XCTAssertTrue(body["userHash"] is NSNull, "an unsecured identify sends the hash as null")
    }

    func testIdentifyWithoutUserDataSendsTheUserId() throws {
        installSession(gleapId: "gid-guest", gleapHash: "ghash-guest")
        GleapStubURLProtocol.stub("POST", "/sessions/identify",
                                  Self.sessionReply(gleapId: "gid-user", gleapHash: "ghash-user", extra: ["userId": "user-1"]))

        Gleap.identifyContact("user-1", andData: nil)

        let body = try XCTUnwrap(waitForRequest("/sessions/identify")?.json)
        XCTAssertEqual(body["userId"] as? String, "user-1")
        XCTAssertTrue(waitUntil { GleapSessionHelper.sharedInstance().currentSession?.userId == "user-1" })
    }

    func testUpdateContactWithoutDataSendsOnlyThePlatform() throws {
        installSession(gleapId: "gid-user", gleapHash: "ghash-user", userId: "user-1")
        GleapStubURLProtocol.stub("POST", "/sessions/partialupdate",
                                  Self.sessionReply(gleapId: "gid-user", gleapHash: "ghash-user", extra: ["userId": "user-1"]))

        Gleap.updateContact(nil)

        let data = try XCTUnwrap(waitForRequest("/sessions/partialupdate")?.json?["data"] as? [String: Any])
        XCTAssertEqual(data["platform"] as? String, "iOS")
        XCTAssertEqual(data["deviceType"] as? String, "mobile")
    }

    func testIdentifyingWithUnchangedDataSendsNothing() {
        installSession(userId: "user-1", name: "Ada Lovelace", email: "ada@example.com")

        Gleap.identifyContact("user-1", andData: user())

        assertNoRequest("/sessions/identify")
    }

    func testRejectedIdentifyClearsTheIdentity() throws {
        installSession(gleapId: "gid-guest", gleapHash: "ghash-guest")
        GleapStubURLProtocol.stub("POST", "/sessions/identify",
                                  .json(["error": ["statusCode": 401, "title": "Not Authorized", "message": "Invalid user hash"]], status: 401))
        GleapStubURLProtocol.stub("POST", "/sessions", Self.sessionReply(gleapId: "gid-fresh", gleapHash: "ghash-fresh"))

        Gleap.identifyContact("user-1", andData: user(), andUserHash: "wrong-hash")

        // The identity is dropped and a fresh guest session is requested without it.
        let restart = try XCTUnwrap(waitForRequest("/sessions"))
        XCTAssertNil(restart.header("Gleap-Id"))
        XCTAssertNil(restart.header("Gleap-Hash"))
        XCTAssertEqual(spy.calls("unregisterPushMessageGroup").map { $0.payload as? String }, ["gleapuser-ghash-guest"])
        XCTAssertTrue(waitUntil { UserDefaults.standard.string(forKey: "gleapId") == "gid-fresh" })
    }

    func testClearIdentityForgetsTheStoredIdentity() throws {
        installSession(gleapId: "gid-user", gleapHash: "ghash-user", userId: "user-1")
        GleapStubURLProtocol.stub("POST", "/sessions", Self.sessionReply(gleapId: "gid-guest", gleapHash: "ghash-guest"))

        Gleap.clearIdentity()

        XCTAssertNil(UserDefaults.standard.string(forKey: "gleapId"))
        XCTAssertNil(UserDefaults.standard.string(forKey: "gleapHash"))
        XCTAssertFalse(Gleap.isUserIdentified())
        XCTAssertEqual(spy.calls("unregisterPushMessageGroup").map { $0.payload as? String }, ["gleapuser-ghash-user"])
        let restart = try XCTUnwrap(waitForRequest("/sessions"))
        XCTAssertNil(restart.header("Gleap-Id"))
        XCTAssertNil(restart.header("Gleap-Hash"))
    }

    func testUpdateContactSendsAPartialUpdateWithTheStoredIdentity() throws {
        installSession(gleapId: "gid-user", gleapHash: "ghash-user", userId: "user-1")
        GleapStubURLProtocol.stub("POST", "/sessions/partialupdate",
                                  Self.sessionReply(gleapId: "gid-user", gleapHash: "ghash-user", extra: ["userId": "user-1", "plan": "Pro"]))
        let update = GleapUserProperty()
        update.plan = "Pro"

        Gleap.updateContact(update)

        let request = try XCTUnwrap(waitForRequest("/sessions/partialupdate"))
        XCTAssertEqual(request.header("Api-Token"), Self.sdkKey)
        XCTAssertEqual(request.header("Gleap-Id"), "gid-user")
        XCTAssertEqual(request.header("Gleap-Hash"), "ghash-user")
        let body = try XCTUnwrap(request.json)
        XCTAssertEqual(body["ws"] as? Bool, true)
        XCTAssertEqual(body["type"] as? String, "ios")
        XCTAssertEqual(body["sdkVersion"] as? String, "18.2.0")
        let data = try XCTUnwrap(body["data"] as? [String: Any])
        XCTAssertEqual(data["plan"] as? String, "Pro")
        XCTAssertEqual(data["platform"] as? String, "iOS")
        XCTAssertEqual(data["deviceType"] as? String, "mobile")
        XCTAssertTrue(waitUntil { GleapSessionHelper.sharedInstance().currentSession?.plan == "Pro" })
    }

    func testUpdateContactWithoutAStoredIdentitySendsNothing() {
        installSession(stored: false)
        let update = GleapUserProperty()
        update.plan = "Pro"

        Gleap.updateContact(update)

        assertNoRequest("/sessions/partialupdate")
    }

    func testThePushGroupIsRegisteredOncePerSessionHash() {
        GleapStubURLProtocol.stub("POST", "/sessions", Self.sessionReply(gleapId: "gid-1", gleapHash: "ghash-1"))

        XCTAssertEqual(startSession(), true)
        XCTAssertEqual(startSession(), true)

        XCTAssertEqual(spy.calls("registerPushMessageGroup").map { $0.payload as? String }, ["gleapuser-ghash-1"])
    }
}
