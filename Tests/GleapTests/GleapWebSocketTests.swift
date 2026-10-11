import XCTest
import ObjectiveC
import UIKit
@testable import Gleap

/// The realtime socket: the reconnect backoff, when a connect request opens a socket and that the
/// app opens none in the background. The rules live in the internal GleapWebSocketPolicy, reached
/// through the Objective-C runtime.
final class GleapWebSocketTests: GleapNetworkTestCase {
    private typealias ReconnectDelay = @convention(c) (AnyClass, Selector, Int, Double) -> Double
    private typealias ShouldReset = @convention(c) (AnyClass, Selector, Double, Bool) -> Bool
    private typealias Action = @convention(c) (AnyClass, Selector, NSURL?, NSURL?, Bool, Bool, Bool) -> Int

    // GleapWebSocketAction
    private let none = 0, keep = 1, wait = 2, connect = 3

    private func policy() throws -> AnyClass {
        try XCTUnwrap(NSClassFromString("GleapWebSocketPolicy"))
    }

    private func classMethod<T>(_ name: String, as type: T.Type) throws -> (AnyClass, Selector, T) {
        let cls: AnyClass = try policy()
        let selector = NSSelectorFromString(name)
        let method = try XCTUnwrap(class_getClassMethod(cls, selector), name)
        return (cls, selector, unsafeBitCast(method_getImplementation(method), to: type))
    }

    private func channel(_ gleapId: String, _ gleapHash: String, apiKey: String = "key") -> NSURL {
        NSURL(string: "wss://ws.gleap.test?gleapId=\(gleapId)&gleapHash=\(gleapHash)&apiKey=\(apiKey)&sdkVersion=1")!
    }

    // MARK: - Backoff

    func testReconnectBackoffDoublesFromTwoToSixtySecondsWithJitter() throws {
        let (cls, selector, delay): (AnyClass, Selector, ReconnectDelay) = try classMethod("reconnectDelayAfterFailures:random:", as: ReconnectDelay.self)
        let bases: [Double] = [2, 4, 8, 16, 32, 60, 60, 60, 60]

        for (index, base) in bases.enumerated() {
            let failures = index + 1
            XCTAssertEqual(delay(cls, selector, failures, 0.5), base, accuracy: 0.001, "\(failures) failures")
            XCTAssertEqual(delay(cls, selector, failures, 0), base * 0.8, accuracy: 0.001, "-20 % after \(failures)")
            XCTAssertEqual(delay(cls, selector, failures, 0.999999), min(base * 1.2, 60), accuracy: 0.001, "+20 % after \(failures)")
        }
        XCTAssertEqual(delay(cls, selector, 0, 0.5), 2, accuracy: 0.001)
        XCTAssertEqual(delay(cls, selector, 1000, 0.5), 60, accuracy: 0.001)
        XCTAssertEqual(delay(cls, selector, 3, -1), 8 * 0.8, accuracy: 0.001, "random is clamped")
        XCTAssertEqual(delay(cls, selector, 3, 5), 8 * 1.2, accuracy: 0.001, "random is clamped")
    }

    func testBackoffStartsOverAfterAMessageOrThirtySecondsOpen() throws {
        let (cls, selector, shouldReset): (AnyClass, Selector, ShouldReset) = try classMethod("shouldResetBackoffAfterOpenFor:receivedMessage:", as: ShouldReset.self)
        XCTAssertFalse(shouldReset(cls, selector, 0.2, false), "a socket that closed right away")
        XCTAssertFalse(shouldReset(cls, selector, 29.9, false))
        XCTAssertTrue(shouldReset(cls, selector, 30, false))
        XCTAssertTrue(shouldReset(cls, selector, 0.2, true), "a socket that received a message")
    }

    // MARK: - Should (re)connect

    func testAnUnchangedChannelKeepsTheOpenSocket() throws {
        let (cls, selector, action): (AnyClass, Selector, Action) = try classMethod("actionForDesiredURL:currentURL:socketAlive:inBackground:online:", as: Action.self)
        let open = channel("gid", "hash")

        XCTAssertEqual(action(cls, selector, open, open, true, false, true), keep)
        // Same channel with the query in another order.
        let reordered = NSURL(string: "wss://ws.gleap.test?gleapHash=hash&apiKey=key&gleapId=gid&sdkVersion=1")!
        XCTAssertEqual(action(cls, selector, reordered, open, true, false, true), keep)
    }

    func testAChangedChannelOrADeadSocketConnects() throws {
        let (cls, selector, action): (AnyClass, Selector, Action) = try classMethod("actionForDesiredURL:currentURL:socketAlive:inBackground:online:", as: Action.self)
        let open = channel("gid", "hash")

        XCTAssertEqual(action(cls, selector, channel("gid2", "hash"), open, true, false, true), connect, "new gleapId")
        XCTAssertEqual(action(cls, selector, channel("gid", "hash2"), open, true, false, true), connect, "new gleapHash")
        XCTAssertEqual(action(cls, selector, channel("gid", "hash", apiKey: "other"), open, true, false, true), connect, "new apiKey")
        XCTAssertEqual(action(cls, selector, open, open, false, false, true), connect, "the socket is gone")
        XCTAssertEqual(action(cls, selector, open, nil, false, false, true), connect, "no socket yet")
    }

    func testNoConnectInTheBackgroundOfflineOrWithoutASession() throws {
        let (cls, selector, action): (AnyClass, Selector, Action) = try classMethod("actionForDesiredURL:currentURL:socketAlive:inBackground:online:", as: Action.self)
        let open = channel("gid", "hash")

        XCTAssertEqual(action(cls, selector, open, nil, false, true, true), wait, "background")
        XCTAssertEqual(action(cls, selector, channel("gid2", "hash"), open, true, true, true), wait, "background, new channel")
        XCTAssertEqual(action(cls, selector, open, nil, false, false, false), wait, "offline")
        XCTAssertEqual(action(cls, selector, nil, open, true, false, true), none, "no session")
    }

    // MARK: - The socket

    func testNoSocketOpensInTheBackgroundUntilTheAppReturns() {
        let socket = GleapWebSocketHelper.sharedInstance()
        let url = URL(string: "wss://ws.gleap.test?gleapId=gid-bg&gleapHash=ghash-bg&apiKey=\(Self.sdkKey)")!
        // ws.gleap.test does not resolve, so a socket fails a few milliseconds after it opens (the
        // lookup is cached after the first one) and is cleared right away. Polling webSocketTask
        // could miss that window, so record every socket the helper opens instead.
        var opened: [String] = []
        let observation = socket.observe(\.webSocketTask, options: [.new]) { _, change in
            if let task = change.newValue as? URLSessionWebSocketTask, let url = task.originalRequest?.url?.absoluteString {
                opened.append(url)
            }
        }
        defer { observation.invalidate() }
        func connectedToIt() -> Bool { opened.contains { $0.contains("gid-bg") } }
        // Whatever the simulator's path monitor last said: this test is about the app lifecycle.
        socket.setValue(true, forKey: "online")

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        socket.connect(to: url)
        spin(2.5)   // past the 1.5 s connect debounce
        XCTAssertFalse(connectedToIt(), "opened a socket in the background")

        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        XCTAssertTrue(waitUntil(timeout: 10) { connectedToIt() }, "did not connect after returning to the foreground")
    }
}
