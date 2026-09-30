import XCTest
import ObjectiveC
@testable import Gleap

/// The event pings (`POST /sessions/ping`): one at a time, only with a session, in batches, and
/// backing off while the server does not take them. The backoff is internal to the SDK, so its
/// rules and state are reached through the Objective-C runtime.
final class GleapEventPingTests: GleapNetworkTestCase {
    private typealias DelayAfterFailures = @convention(c) (AnyClass, Selector, Int, Double) -> Double
    private typealias RetryAfterFromValue = @convention(c) (AnyClass, Selector, NSString?, NSDate) -> Double

    private var events: GleapEventLogHelper { GleapEventLogHelper.sharedInstance() }

    private var pings: [GleapRecordedRequest] { GleapStubURLProtocol.requests(path: "/sessions/ping") }

    private var queuedNames: [String] {
        events.streamedLog.compactMap { ($0 as? [String: Any])?["name"] as? String }
    }

    private var pingIdle: Bool { (events.value(forKey: "pingInFlight") as? Int) == 0 }

    private var failures: Int { (events.value(forKeyPath: "pingBackoff.failures") as? Int) ?? -1 }

    /// Seconds until the next ping may go out.
    private var backoffRemaining: TimeInterval {
        let retryAt = (events.value(forKeyPath: "pingBackoff.retryAt") as? Double) ?? 0
        return max(0, retryAt - ProcessInfo.processInfo.systemUptime)
    }

    private func sentNames(_ ping: GleapRecordedRequest?) -> [String] {
        ((ping?.json?["events"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }
    }

    /// Lets the next ping go out now instead of after its backoff.
    private func endBackoff() {
        events.setValue(0, forKeyPath: "pingBackoff.retryAt")
    }

    /// Asks for a ping answered with `reply` and waits until the answer was handled. Nil when no
    /// ping went out.
    @discardableResult
    private func ping(_ reply: GleapStubReply, file: StaticString = #filePath, line: UInt = #line) -> GleapRecordedRequest? {
        GleapStubURLProtocol.stub("POST", "/sessions/ping", reply)
        let before = pings.count
        events.sendEventStreamToServer()
        XCTAssertTrue(waitUntil { self.pingIdle }, "the ping was not answered", file: file, line: line)
        return pings.dropFirst(before).first
    }

    private func backoffClass() throws -> AnyClass {
        try XCTUnwrap(NSClassFromString("GleapPingBackoff"))
    }

    func testNoPingWithoutASession() {
        // Without the websocket the SDK pings even without events, so only the session holds it back.
        events.webSocketEnabled = false
        events.logEvent("before-session")

        events.sendEventStreamToServer()
        let incomplete = GleapSession()
        incomplete.gleapId = "gid-1"
        GleapSessionHelper.sharedInstance().currentSession = incomplete
        events.sendEventStreamToServer()

        assertNoRequest("/sessions/ping")
        XCTAssertEqual(queuedNames, ["before-session"], "the events wait for the session")
    }

    func testOnlyOnePingIsInFlight() {
        installSession()
        events.webSocketEnabled = true
        GleapStubURLProtocol.stub("POST", "/sessions/ping", .json([String: Any]()))
        events.logEvent("first")

        // The answer arrives on the main queue, so the first ping is still unanswered here.
        events.sendEventStreamToServer()
        events.logEvent("second")
        events.sendEventStreamToServer()
        events.sendEventStreamToServer()

        XCTAssertTrue(waitUntil { self.pingIdle })
        spin(0.3)
        XCTAssertEqual(pings.map(sentNames), [["first"]])

        events.sendEventStreamToServer()
        XCTAssertTrue(waitUntil { self.pings.count == 2 && self.pingIdle })
        XCTAssertEqual(sentNames(pings.last), ["second"])
    }

    func testBackoffDoublesFromThreeToSixtySecondsWithJitter() throws {
        let backoff: AnyClass = try backoffClass()
        let selector = NSSelectorFromString("delayAfterFailures:random:")
        let method = try XCTUnwrap(class_getClassMethod(backoff, selector))
        let delay = unsafeBitCast(method_getImplementation(method), to: DelayAfterFailures.self)
        let bases: [Double] = [3, 6, 12, 24, 48, 60, 60, 60]

        for (index, base) in bases.enumerated() {
            let failures = index + 1
            XCTAssertEqual(delay(backoff, selector, failures, 0.5), base, accuracy: 0.001, "\(failures) failures")
            XCTAssertEqual(delay(backoff, selector, failures, 0), base * 0.8, accuracy: 0.001, "-20 %")
            XCTAssertEqual(delay(backoff, selector, failures, 0.999_999), min(base * 1.2, 60), accuracy: 0.001, "+20 %, capped at 60 s")
            for random in stride(from: 0.0, to: 1.0, by: 0.1) {
                let value = delay(backoff, selector, failures, random)
                XCTAssertTrue(value >= base * 0.8 - 0.001 && value <= min(base * 1.2, 60) + 0.001, "\(value) for \(failures) failures")
            }
        }
    }

    func testRetryAfterIsReadAsSecondsOrAnHTTPDate() throws {
        let backoff: AnyClass = try backoffClass()
        let selector = NSSelectorFromString("retryAfterFromValue:now:")
        let method = try XCTUnwrap(class_getClassMethod(backoff, selector))
        let retryAfter = unsafeBitCast(method_getImplementation(method), to: RetryAfterFromValue.self)
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-21T07:28:00Z"))
        let now = date.addingTimeInterval(-90) as NSDate

        let cases: [(String?, Double)] = [
            ("120", 120),
            (" 7 ", 7),
            ("Wed, 21 Oct 2026 07:28:00 GMT", 90),
            ("Wed Oct 21 07:28:00 2026", 90),
            ("Tue, 20 Oct 2026 07:28:00 GMT", 0),
            ("soon", -1),
            ("-5", -1),
            ("", -1),
            (nil, -1),
        ]
        for (value, expected) in cases {
            XCTAssertEqual(retryAfter(backoff, selector, value as NSString?, now), expected, accuracy: 0.001, "\(value ?? "nil")")
        }
    }

    func testFailedPingsBackOffUntilA2xxStartsOver() throws {
        installSession()
        events.webSocketEnabled = true
        events.logEvent("queued")

        // A Retry-After shorter than the backoff does not shorten it.
        XCTAssertNotNil(ping(.json([String: Any](), status: 429, headers: ["Retry-After": "1"])))
        XCTAssertEqual(failures, 1)
        XCTAssertTrue((2.3...3.6).contains(backoffRemaining), "\(backoffRemaining)")
        XCTAssertNil(ping(.json([String: Any]())), "no ping during the backoff")

        endBackoff()
        ping(.json([String: Any](), status: 429, headers: ["Retry-After": "120"]))
        XCTAssertEqual(backoffRemaining, 120, accuracy: 1)

        endBackoff()
        ping(.json([String: Any](), status: 429, headers: ["Retry-After": "3600"]))
        XCTAssertEqual(backoffRemaining, 300, accuracy: 1, "Retry-After is capped at 5 minutes")

        endBackoff()
        ping(.json([String: Any](), status: 503))
        XCTAssertEqual(failures, 4)
        XCTAssertTrue((19.1...28.8).contains(backoffRemaining), "\(backoffRemaining)")

        endBackoff()
        ping(.json([String: Any]()))
        XCTAssertEqual(failures, 0)
        XCTAssertEqual(backoffRemaining, 0)

        events.logEvent("next")
        ping(.failure())
        XCTAssertEqual(failures, 1)
        XCTAssertTrue((2.3...3.6).contains(backoffRemaining), "a delivered ping starts the backoff over: \(backoffRemaining)")
    }

    func testOnlyTheDeliveredEventsLeaveTheQueue() throws {
        installSession()
        events.webSocketEnabled = true
        GleapStubURLProtocol.stub("POST", "/sessions/ping", .json([String: Any]()))
        events.logEvent("sent-1")
        events.logEvent("sent-2")

        events.sendEventStreamToServer()
        events.logEvent("tracked-while-in-flight")
        XCTAssertEqual(queuedNames, ["sent-1", "sent-2", "tracked-while-in-flight"], "nothing leaves before the answer")

        XCTAssertTrue(waitUntil { self.pingIdle })
        XCTAssertEqual(sentNames(pings.first), ["sent-1", "sent-2"])
        XCTAssertEqual(queuedNames, ["tracked-while-in-flight"])
    }

    func testAFailedPingKeepsItsEvents() throws {
        installSession()
        events.webSocketEnabled = true
        events.logEvent("checkout")

        let failedReplies: [GleapStubReply] = [
            .json(["error": "Too many requests"], status: 429),
            .json(["error": "Internal"], status: 500),
            .json(["error": "Request timeout"], status: 408),
            .failure(.timedOut),
        ]
        for reply in failedReplies {
            endBackoff()
            XCTAssertEqual(sentNames(try XCTUnwrap(ping(reply))), ["checkout"], "status \(reply.status)")
            XCTAssertEqual(queuedNames, ["checkout"], "status \(reply.status)")
        }

        endBackoff()
        XCTAssertEqual(sentNames(ping(.json([String: Any]()))), ["checkout"])
        XCTAssertEqual(queuedNames, [])
    }

    func testARefusedPingDropsItsEvents() throws {
        installSession()
        events.webSocketEnabled = true
        events.logEvent("broken")

        XCTAssertEqual(sentNames(try XCTUnwrap(ping(.json(["error": "Bad request"], status: 400)))), ["broken"])
        XCTAssertEqual(queuedNames, [])
    }

    func testAPingCarriesAtMost100EventsAndTheRestFollowsRightAway() {
        installSession()
        events.webSocketEnabled = true
        GleapStubURLProtocol.stub("POST", "/sessions/ping", .json([String: Any]()))
        for index in 0..<250 {
            events.logEvent("event-\(index)")
        }

        events.sendEventStreamToServer()

        XCTAssertTrue(waitUntil { self.pings.count == 3 && self.queuedNames.isEmpty && self.pingIdle })
        let batches = pings.map(sentNames)
        XCTAssertEqual(batches.map(\.count), [100, 100, 50])
        XCTAssertEqual(batches.flatMap { $0 }, (0..<250).map { "event-\($0)" }, "oldest first")
    }

    func testAPingStaysUnder256KBAndSkipsEventsThatAreNotJSON() {
        installSession()
        events.webSocketEnabled = true
        GleapStubURLProtocol.stub("POST", "/sessions/ping", .json([String: Any]()))
        let blob = String(repeating: "x", count: 60_000)
        events.logEvent("not-json", withData: ["when": Date()])
        for index in 0..<6 {
            events.logEvent("large-\(index)", withData: ["blob": blob])
        }

        events.sendEventStreamToServer()

        XCTAssertTrue(waitUntil { self.pings.count == 2 && self.queuedNames.isEmpty && self.pingIdle })
        XCTAssertEqual(pings.map(sentNames), [["large-0", "large-1", "large-2", "large-3"], ["large-4", "large-5"]])
        XCTAssertLessThan(pings[0].body.count, 256 * 1024)
    }

    func testTheQueueKeepsAtMost500EventsAndTheSessionStart() {
        events.logEvent("sessionStarted")
        for index in 0..<600 {
            events.logEvent("event-\(index)")
        }

        let names = queuedNames
        XCTAssertEqual(names.count, 500)
        XCTAssertEqual(names.first, "sessionStarted")
        XCTAssertEqual(names.dropFirst().first, "event-101", "the oldest other events made room")
        XCTAssertEqual(names.last, "event-599")
    }

    func testOnlyADeliveredPingUpdatesTheUnreadCount() throws {
        installSession()
        events.webSocketEnabled = false
        // parseUpdate applies the actions and the unread count of an answer: record what reaches it.
        let method = try XCTUnwrap(class_getInstanceMethod(GleapEventLogHelper.self, #selector(GleapEventLogHelper.parseUpdate(_:))))
        let unreadCounts = GleapBox<[Int]>()
        let recorder: @convention(block) (AnyObject, NSDictionary) -> Void = { _, update in
            unreadCounts.value = (unreadCounts.value ?? []) + [(update["u"] as? Int) ?? -1]
        }
        let original = method_setImplementation(method, imp_implementationWithBlock(recorder))
        defer { method_setImplementation(method, original) }

        ping(.json(["u": 0, "error": "Too many requests"], status: 429))
        endBackoff()
        ping(.json(["u": 0], status: 503))
        endBackoff()
        ping(.failure())
        XCTAssertNil(unreadCounts.value, "error answers do not reach the badge")

        endBackoff()
        ping(.json(["u": 3, "a": [Any]()]))
        XCTAssertEqual(unreadCounts.value, [3])
    }
}
