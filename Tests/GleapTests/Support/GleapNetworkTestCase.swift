import Foundation
import UIKit
import XCTest
@testable import Gleap

/// A reference cell for values set from the SDK's `@Sendable` completion blocks.
final class GleapBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value?

    var value: Value? {
        get { lock.lock(); defer { lock.unlock() }; return storage }
        set { lock.lock(); storage = newValue; lock.unlock() }
    }
}

/// Records the delegate calls the SDK makes, with the thread they arrived on.
final class GleapDelegateSpy: NSObject, GleapDelegate {
    struct Call {
        let name: String
        let payload: Any?
        let onMainThread: Bool
    }

    private let lock = NSLock()
    private var recorded: [Call] = []

    var calls: [Call] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func calls(_ name: String) -> [Call] {
        calls.filter { $0.name == name }
    }

    private func record(_ name: String, _ payload: Any? = nil) {
        lock.lock()
        recorded.append(Call(name: name, payload: payload, onMainThread: Thread.isMainThread))
        lock.unlock()
    }

    func feedbackSent(_ data: [AnyHashable: Any]) { record("feedbackSent", data) }
    func feedbackSendingFailed(_ data: [AnyHashable: Any]) { record("feedbackSendingFailed", data) }
    func configLoaded(_ config: [AnyHashable: Any]) { record("configLoaded", config) }
    func initialized() { record("initialized") }
    func registerPushMessageGroup(_ pushMessageGroup: String) { record("registerPushMessageGroup", pushMessageGroup) }
    func unregisterPushMessageGroup(_ pushMessageGroup: String) { record("unregisterPushMessageGroup", pushMessageGroup) }
}

/// Captures the messages the native side sends to the widget instead of evaluating them in a web
/// view. The survey format keeps init from loading the widget page.
final class GleapCapturingFrameManager: GleapFrameManagerViewController {
    var messages: [[AnyHashable: Any]] = []

    override func sendMessage(withData data: [AnyHashable: Any]) {
        messages.append(data)
    }
}

/// Base class for tests that drive the SDK against stubbed Gleap endpoints.
class GleapNetworkTestCase: XCTestCase {
    static let apiUrl = "https://api.gleap.test"
    static let wsApiUrl = "wss://ws.gleap.test"
    static let sdkKey = "test-sdk-key"

    let spy = GleapDelegateSpy()

    override class func setUp() {
        super.setUp()
        _ = GleapStubInstaller.install
    }

    override func setUp() {
        super.setUp()
        resetSDKState()
        GleapStubURLProtocol.reset()
        Gleap.sharedInstance().delegate = spy
    }

    override func tearDown() {
        Gleap.sharedInstance().delegate = nil
        // Let replies that are still on their way land before the next test starts.
        spin(0.3)
        resetSDKState()
        GleapStubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - State

    func resetSDKState() {
        let gleap = Gleap.sharedInstance()
        Gleap.setRegion("eu")
        Gleap.setApiUrl(Self.apiUrl)
        Gleap.setWSApiUrl(Self.wsApiUrl)
        gleap.token = Self.sdkKey

        UserDefaults.standard.removeObject(forKey: "gleapId")
        UserDefaults.standard.removeObject(forKey: "gleapHash")
        let sessions = GleapSessionHelper.sharedInstance()
        sessions.currentSession = nil
        sessions.openIdentityAction = nil
        sessions.openUpdateAction = nil
        sessions.openPushAction = nil
        sessions.lastRegisterGleapHash = nil

        let events = GleapEventLogHelper.sharedInstance()
        events.stop()
        events.clear()

        Gleap.clearCustomData()
        Gleap.clearTicketAttributes()
        Gleap.setTags([])
        Gleap.removeAllAttachments()
        Gleap.setNetworkLogPropsToIgnore([])
        Gleap.setNetworkLogsBlacklist([])
        Gleap.setEnvDataPropsToIgnore([])
        Gleap.setDisableEnvData(false)
        GleapExternalDataHelper.sharedInstance().addEntries(["networkLogs": [Any](), "consoleLog": [Any]()])

        let recorder = GleapHttpTrafficRecorder.shared()!
        recorder.stopRecording()
        recorder.setValue(false, forKey: "stoppedByApp")   // forget an earlier Gleap.stopNetworkRecording()
        recorder.clearLogs()
        recorder.networkLogPropsToIgnore = []
        recorder.blacklist = []

        let replays = GleapReplayHelper.sharedInstance()
        replays.stop()
        replays.clear()
        replays.timerInterval = 5

        let activation = GleapActivationMethodHelper.sharedInstance()
        activation.activationMethods = []
        activation.disableAutoActivationMethods = false
    }

    /// Installs a guest session as if `POST /sessions` had answered, optionally also stored.
    @discardableResult
    func installSession(gleapId: String = "gid-1", gleapHash: String = "ghash-1", userId: String? = nil,
                        name: String? = nil, email: String? = nil, stored: Bool = true) -> GleapSession {
        let session = GleapSession()
        session.gleapId = gleapId
        session.gleapHash = gleapHash
        session.userId = userId
        session.name = name
        session.email = email
        session.lang = GleapTranslationHelper.sharedInstance().language
        GleapSessionHelper.sharedInstance().currentSession = session
        if stored {
            UserDefaults.standard.set(gleapId, forKey: "gleapId")
            UserDefaults.standard.set(gleapHash, forKey: "gleapHash")
        }
        return session
    }

    static func sessionReply(gleapId: String, gleapHash: String, extra: [String: Any] = [:]) -> GleapStubReply {
        var body: [String: Any] = ["gleapId": gleapId, "gleapHash": gleapHash]
        body.merge(extra) { _, new in new }
        return .json(body)
    }

    static func testImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    // MARK: - Waiting

    /// Runs the main run loop, so main-queue callbacks can arrive.
    func spin(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    @discardableResult
    func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return condition()
    }

    /// The first recorded request to `path` (matching `filter`), waiting for it if needed.
    func waitForRequest(_ path: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line,
                        where filter: (GleapRecordedRequest) -> Bool = { _ in true }) -> GleapRecordedRequest? {
        var match: GleapRecordedRequest?
        waitUntil(timeout: timeout) {
            match = GleapStubURLProtocol.requests(path: path).first(where: filter)
            return match != nil
        }
        if match == nil {
            XCTFail("No request to \(path); saw \(GleapStubURLProtocol.requests.map { "\($0.method) \($0.path)" })", file: file, line: line)
        }
        return match
    }

    func assertNoRequest(_ path: String, within seconds: TimeInterval = 0.8, file: StaticString = #filePath, line: UInt = #line) {
        spin(seconds)
        XCTAssertTrue(GleapStubURLProtocol.requests(path: path).isEmpty, "Unexpected request to \(path)", file: file, line: line)
    }

    /// Sends a report and waits for its completion.
    func send(_ feedback: GleapFeedback, timeout: TimeInterval = 20, file: StaticString = #filePath, line: UInt = #line) -> (success: Bool, data: [AnyHashable: Any])? {
        let result = GleapBox<(Bool, [AnyHashable: Any])>()
        feedback.send { success, data in
            result.value = (success, data)
        }
        waitUntil(timeout: timeout) { result.value != nil }
        guard let value = result.value else {
            XCTFail("The report did not complete", file: file, line: line)
            return nil
        }
        return value
    }
}
