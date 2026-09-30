import XCTest
@testable import Gleap

/// Protected conversation files: the file access token from a verified identify, and who gets it.
final class GleapFileAccessTests: GleapNetworkTestCase {
    private static let token = String(repeating: "t", count: 43)
    private static let fileId = "0123456789abcdef01234567"

    private static func expiresAt(in seconds: TimeInterval = 15 * 60) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date().addingTimeInterval(seconds))
    }

    private static func verifiedReply(userId: String = "user-1", token: String = token) -> GleapStubReply {
        sessionReply(gleapId: "gid-user", gleapHash: "ghash-user", extra: [
            "userId": userId, "authenticatedFilesRequired": true,
            "fileAccessToken": token, "fileAccessExpiresAt": expiresAt(),
        ])
    }

    private func installFileAccess(userId: String = "user-1") {
        let session = installSession(gleapId: "gid-user", gleapHash: "ghash-user", userId: userId)
        session.authenticatedFilesRequired = true
        session.fileAccessToken = Self.token
        session.fileAccessExpiresAt = Date().addingTimeInterval(15 * 60)
    }

    func testVerifiedIdentifyGivesTheTokenToTheWidgetOnly() throws {
        installSession(gleapId: "gid-guest", gleapHash: "ghash-guest")
        GleapStubURLProtocol.stub("POST", "/sessions/identify", Self.verifiedReply())

        Gleap.identifyContact("user-1", andData: nil, andUserHash: "user-hash-1")

        XCTAssertTrue(waitUntil { GleapSessionHelper.sharedInstance().currentSession?.hasFileAccess() == true })
        let session = try XCTUnwrap(GleapSessionHelper.sharedInstance().currentSession)
        XCTAssertEqual(session.widgetDictionary()["fileAccessToken"] as? String, Self.token)
        XCTAssertNotNil(session.widgetDictionary()["fileAccessExpiresAt"] as? String)
        XCTAssertNil(Gleap.getIdentity()["fileAccessToken"], "the app's getIdentity never sees the token")
        let stored = UserDefaults.standard.dictionaryRepresentation().values.compactMap { $0 as? String }
        XCTAssertFalse(stored.contains(Self.token), "the token is never stored on the device")
    }

    func testUnchangedIdentifyIsSentWhenTheProjectRequiresFileAccess() throws {
        let session = installSession(userId: "user-1")
        session.authenticatedFilesRequired = true
        GleapStubURLProtocol.stub("POST", "/sessions/identify", Self.verifiedReply())

        Gleap.identifyContact("user-1", andData: nil, andUserHash: "user-hash-1")

        let body = try XCTUnwrap(waitForRequest("/sessions/identify")?.json)
        XCTAssertEqual(body["userHash"] as? String, "user-hash-1")
    }

    func testUnchangedIdentifyWithoutAHashStillSendsNothing() {
        let session = installSession(userId: "user-1")
        session.authenticatedFilesRequired = true

        Gleap.identifyContact("user-1", andData: nil)

        assertNoRequest("/sessions/identify")
    }

    func testAnAnswerWithoutTokenKeepsItOnlyForTheSameUser() throws {
        installFileAccess()
        GleapStubURLProtocol.stub("POST", "/sessions/partialupdate",
                                  Self.sessionReply(gleapId: "gid-user", gleapHash: "ghash-user", extra: ["userId": "user-1", "plan": "Pro"]))
        let update = GleapUserProperty()
        update.plan = "Pro"

        Gleap.updateContact(update)

        XCTAssertTrue(waitUntil { GleapSessionHelper.sharedInstance().currentSession?.plan == "Pro" })
        XCTAssertEqual(GleapSessionHelper.sharedInstance().currentSession?.fileAccessToken, Self.token)

        GleapStubURLProtocol.stub("POST", "/sessions/partialupdate",
                                  Self.sessionReply(gleapId: "gid-user", gleapHash: "ghash-user", extra: ["userId": "user-2"]))
        Gleap.updateContact(update)

        XCTAssertTrue(waitUntil { GleapSessionHelper.sharedInstance().currentSession?.userId == "user-2" })
        XCTAssertNil(GleapSessionHelper.sharedInstance().currentSession?.fileAccessToken)
    }

    func testClearIdentityRevokesTheToken() throws {
        installFileAccess()
        GleapStubURLProtocol.stub("POST", "/files/session/revoke", .json([:], status: 204))
        GleapStubURLProtocol.stub("POST", "/sessions", Self.sessionReply(gleapId: "gid-guest", gleapHash: "ghash-guest"))

        Gleap.clearIdentity()

        let revoke = try XCTUnwrap(waitForRequest("/files/session/revoke"))
        XCTAssertEqual(revoke.header("X-File-Session"), Self.token)
        XCTAssertNil(revoke.header("Api-Token"))
        XCTAssertNil(revoke.header("Gleap-Hash"))
        XCTAssertTrue(waitUntil { GleapSessionHelper.sharedInstance().currentSession?.gleapId == "gid-guest" })
        XCTAssertNil(GleapSessionHelper.sharedInstance().currentSession?.fileAccessToken)
    }

    func testAnIdentifyAnsweredAfterLogoutIsDropped() throws {
        installSession(gleapId: "gid-guest", gleapHash: "ghash-guest")
        GleapStubURLProtocol.stub("POST", "/sessions/identify") { _ in
            Thread.sleep(forTimeInterval: 0.5)
            return Self.verifiedReply()
        }
        GleapStubURLProtocol.stub("POST", "/sessions", Self.sessionReply(gleapId: "gid-fresh", gleapHash: "ghash-fresh"))

        Gleap.identifyContact("user-1", andData: nil, andUserHash: "user-hash-1")
        XCTAssertNotNil(waitForRequest("/sessions/identify"))
        Gleap.clearIdentity()

        spin(1.5)
        XCTAssertEqual(GleapSessionHelper.sharedInstance().currentSession?.gleapId, "gid-fresh")
        XCTAssertNil(GleapSessionHelper.sharedInstance().currentSession?.fileAccessToken)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "gleapId"), "gid-fresh")
    }

    func testFileLinkIsOpenedOnlyWithFileAccess() throws {
        XCTAssertFalse(Gleap.openProtectedFile(from: URL(string: "https://app.example.com/support?gleapFile=nothex")!))
        XCTAssertFalse(Gleap.openProtectedFile(from: URL(string: "https://app.example.com/support")!))

        installSession(gleapId: "gid-guest", gleapHash: "ghash-guest")
        GleapStubURLProtocol.stub("GET", "/files/\(Self.fileId)/location", .json(["shareToken": "share-1"]))
        XCTAssertTrue(Gleap.openProtectedFile(from: URL(string: "https://app.example.com/support?gleapFile=\(Self.fileId)")!))
        assertNoRequest("/files/\(Self.fileId)/location")

        GleapStubURLProtocol.stub("POST", "/sessions/identify", Self.verifiedReply())
        Gleap.identifyContact("user-1", andData: nil, andUserHash: "user-hash-1")

        let location = try XCTUnwrap(waitForRequest("/files/\(Self.fileId)/location"))
        XCTAssertEqual(location.header("X-File-Session"), Self.token)
        XCTAssertNil(location.header("Api-Token"))
        XCTAssertNil(GleapSessionHelper.sharedInstance().pendingProtectedFileId)
    }
}
