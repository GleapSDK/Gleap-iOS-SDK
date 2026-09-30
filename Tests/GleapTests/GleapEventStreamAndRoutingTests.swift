import XCTest
@testable import Gleap

/// The event stream and which region's hosts requests go to.
final class GleapEventStreamAndRoutingTests: GleapNetworkTestCase {
    func testQueuedEventsAreStreamedWithTheSessionCredentials() throws {
        installSession(gleapId: "gid-1", gleapHash: "ghash-1")
        let events = GleapEventLogHelper.sharedInstance()
        events.clear()
        events.logEvent("checkout-started")
        events.logEvent("coupon-applied", withData: ["code": "SPRING"])

        events.sendEventStreamToServer()

        let ping = try XCTUnwrap(waitForRequest("/sessions/ping") { $0.bodyString.contains("checkout-started") })
        XCTAssertEqual(ping.method, "POST")
        XCTAssertEqual(ping.header("Api-Token"), Self.sdkKey)
        XCTAssertEqual(ping.header("Gleap-Id"), "gid-1")
        XCTAssertEqual(ping.header("Gleap-Hash"), "ghash-1")
        let body = try XCTUnwrap(ping.json)
        let sent = try XCTUnwrap(body["events"] as? [[String: Any]])
        XCTAssertEqual(sent.map { $0["name"] as? String }, ["checkout-started", "coupon-applied"])
        XCTAssertEqual((sent[1]["data"] as? [String: Any])?["code"] as? String, "SPRING")
        XCTAssertEqual(body["type"] as? String, "ios")
        XCTAssertEqual(body["sdkVersion"] as? String, "19.0.0")
        XCTAssertNotNil(body["time"] as? Double)
        XCTAssertEqual(body["opened"] as? Bool, false)
        XCTAssertNotNil(body["ws"] as? Bool)
        XCTAssertTrue(waitUntil { events.streamedLog.count == 0 }, "delivered events leave the queue")
    }

    func testRequestsFollowTheSelectedRegion() throws {
        Gleap.setRegion("us")
        installSession()
        GleapStubURLProtocol.stub("POST", "/sessions", .json([String: Any]()))

        GleapSessionHelper.sharedInstance().startSession { _ in }
        GleapConfigHelper.sharedInstance().run()
        GleapEventLogHelper.sharedInstance().logEvent("region-check")
        GleapEventLogHelper.sharedInstance().sendEventStreamToServer()
        let feedback = GleapFeedback()
        feedback.appendData(["formData": ["description": "US"]])
        _ = send(feedback)

        for path in ["/sessions", "/sessions/ping", "/bugs/v2"] {
            let request = try XCTUnwrap(waitForRequest(path), path)
            XCTAssertEqual(request.url.scheme, "https", path)
            XCTAssertEqual(request.url.host, "api.us.gleap.ai", path)
        }
        let config = try XCTUnwrap(waitForRequest("/config/\(Self.sdkKey)"))
        XCTAssertEqual(config.url.host, "api.us.gleap.ai")
    }

    func testTheWebSocketCarriesTheSessionCredentials() throws {
        installSession(gleapId: "gid-ws", gleapHash: "ghash-ws")
        let events = GleapEventLogHelper.sharedInstance()
        events.stop()

        events.start()

        let socket = GleapWebSocketHelper.sharedInstance()
        XCTAssertTrue(waitUntil { socket.webSocketTask?.originalRequest?.url?.absoluteString.contains("gid-ws") == true })
        let url = try XCTUnwrap(URLComponents(url: socket.reconnectURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(url.scheme, "wss")
        XCTAssertEqual(url.host, "ws.gleap.test")
        let query = Dictionary(uniqueKeysWithValues: (url.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["gleapId"], "gid-ws")
        XCTAssertEqual(query["gleapHash"], "ghash-ws")
        XCTAssertEqual(query["apiKey"], Self.sdkKey)
        XCTAssertEqual(query["sdkVersion"], "19.0.0")
        events.stop()
    }

    func testTheWidgetGetsTheRealtimeHostOnlyWhenItWasSelected() throws {
        installSession(gleapId: "gid-1", gleapHash: "ghash-1")
        let frame = GleapCapturingFrameManager(format: "survey")
        Gleap.sharedInstance().realtimeHost = nil

        frame.sendSessionUpdate()
        Gleap.setRealtimeHost("sockets.gleap.test")
        frame.sendSessionUpdate()
        Gleap.setRegion("us")
        frame.sendSessionUpdate()

        XCTAssertEqual(frame.messages.count, 3)
        let updates = try frame.messages.map { message -> [String: Any] in
            XCTAssertEqual(message["name"] as? String, "session-update")
            return try XCTUnwrap(message["data"] as? [String: Any])
        }
        XCTAssertEqual(updates[0]["apiUrl"] as? String, Self.apiUrl)
        XCTAssertEqual(updates[0]["sdkKey"] as? String, Self.sdkKey)
        XCTAssertEqual((updates[0]["sessionData"] as? [String: Any])?["gleapHash"] as? String, "ghash-1")
        XCTAssertNil(updates[0]["realtimeHost"])
        XCTAssertEqual(updates[1]["realtimeHost"] as? String, "sockets.gleap.test")
        XCTAssertEqual(updates[2]["realtimeHost"] as? String, "sockets.us.gleap.ai")
        XCTAssertEqual(updates[2]["apiUrl"] as? String, "https://api.us.gleap.ai")
    }
}
