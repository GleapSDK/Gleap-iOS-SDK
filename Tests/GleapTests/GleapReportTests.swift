import XCTest
@testable import Gleap

/// Report submission: what is uploaded, what reaches `/bugs/v2`, what is left out.
final class GleapReportTests: GleapNetworkTestCase {
    override func setUp() {
        super.setUp()
        installSession(gleapId: "gid-1", gleapHash: "ghash-1")
        GleapStubURLProtocol.stub("POST", "/uploads/sdk", .json(["fileUrl": "https://files.gleap.test/screenshot.jpeg"]))
        GleapStubURLProtocol.stub("POST", "/uploads/attachments") { request in
            let names = ["log.txt", "trace.json"].filter { request.bodyString.contains("filename=\($0)") }
            return .json(["fileUrls": names.map { "https://files.gleap.test/\($0)" }])
        }
        GleapStubURLProtocol.stub("POST", "/bugs/v2", .json(["id": "ticket-1"]))
    }

    private func report(description: String = "Checkout button does nothing") -> GleapFeedback {
        let feedback = GleapFeedback()
        feedback.appendData(["formData": ["description": description]])
        return feedback
    }

    private func assertSessionHeaders(_ request: GleapRecordedRequest, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(request.header("Api-Token"), Self.sdkKey, file: file, line: line)
        XCTAssertEqual(request.header("Gleap-Id"), "gid-1", file: file, line: line)
        XCTAssertEqual(request.header("Gleap-Hash"), "ghash-1", file: file, line: line)
    }

    func testReportWithScreenshotUploadsItThenSendsTheTicket() throws {
        let feedback = report()
        feedback.screenshot = Self.testImage()

        let result = try XCTUnwrap(send(feedback))

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.data["id"] as? String, "ticket-1")
        let paths = GleapStubURLProtocol.requests.map(\.path).filter { $0.hasPrefix("/uploads") || $0 == "/bugs/v2" }
        XCTAssertEqual(paths, ["/uploads/sdk", "/bugs/v2"])

        let upload = try XCTUnwrap(GleapStubURLProtocol.requests(path: "/uploads/sdk").first)
        assertSessionHeaders(upload)
        XCTAssertEqual(upload.header("Content-Type"), "multipart/form-data; boundary=BBBOUNDARY")
        XCTAssertTrue(upload.bodyString.contains("Content-Disposition: form-data; name=file; filename=screenshot.jpeg"))
        XCTAssertTrue(upload.bodyString.contains("Content-Type: image/jpeg"))

        let ticket = try XCTUnwrap(GleapStubURLProtocol.requests(path: "/bugs/v2").first)
        assertSessionHeaders(ticket)
        XCTAssertEqual(ticket.header("Content-Type"), "application/json")
        let body = try XCTUnwrap(ticket.json)
        XCTAssertEqual(body["screenshotUrl"] as? String, "https://files.gleap.test/screenshot.jpeg")
        XCTAssertEqual(body["type"] as? String, "BUG")
        XCTAssertEqual((body["formData"] as? [String: Any])?["description"] as? String, "Checkout button does nothing")
        XCTAssertFalse((body["metaData"] as? [String: Any] ?? [:]).isEmpty)

        let sent = try XCTUnwrap(spy.calls("feedbackSent").first?.payload as? [AnyHashable: Any])
        XCTAssertEqual(sent["type"] as? String, "BUG")
        XCTAssertEqual((sent["formData"] as? [String: Any])?["description"] as? String, "Checkout button does nothing")
        XCTAssertTrue(spy.calls("feedbackSendingFailed").isEmpty)
    }

    func testReportThatCannotReachTheServerFails() throws {
        GleapStubURLProtocol.stub("POST", "/bugs/v2", .failure(.notConnectedToInternet))

        let result = try XCTUnwrap(send(report()))

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.data["error"] as? String, "Network error")
        XCTAssertEqual(spy.calls("feedbackSendingFailed").count, 1)
        XCTAssertTrue(spy.calls("feedbackSent").isEmpty)
    }

    func testFailedScreenshotUploadStillSendsTheReport() throws {
        GleapStubURLProtocol.stub("POST", "/uploads/sdk", .failure(.timedOut))
        let feedback = report()
        feedback.screenshot = Self.testImage()

        let result = try XCTUnwrap(send(feedback))

        XCTAssertTrue(result.success)
        let body = try XCTUnwrap(GleapStubURLProtocol.requests(path: "/bugs/v2").first?.json)
        XCTAssertNil(body["screenshotUrl"])
        XCTAssertNotNil(body["formData"])
    }

    func testExcludedDataIsNeitherUploadedNorSent() throws {
        XCTAssertTrue(Gleap.addAttachment(with: Data("app log".utf8), andName: "log.txt"))
        Gleap.attachCustomData(["plan": "pro"])
        let feedback = report()
        feedback.screenshot = Self.testImage()
        feedback.excludeData = [
            "screenshot": true, "attachments": true, "replays": true,
            "consoleLog": true, "networkLogs": true, "customData": true, "metaData": true, "customEventLog": true,
        ]

        XCTAssertTrue(try XCTUnwrap(send(feedback)).success)

        XCTAssertTrue(GleapStubURLProtocol.requests.filter { $0.path.hasPrefix("/uploads") }.isEmpty)
        let body = try XCTUnwrap(GleapStubURLProtocol.requests(path: "/bugs/v2").first?.json)
        for key in ["screenshotUrl", "attachments", "replay", "consoleLog", "networkLogs", "customData", "metaData", "customEventLog"] {
            XCTAssertNil(body[key], "\(key) should have been left out")
        }
        XCTAssertNotNil(body["formData"])
    }

    func testSilentCrashReportLeavesOutMediaByDefault() throws {
        XCTAssertTrue(Gleap.addAttachment(with: Data("app log".utf8), andName: "log.txt"))
        let result = GleapBox<Bool>()

        Gleap.sendSilentCrashReport(with: "Payment failed", andSeverity: HIGH, andDataExclusion: nil) { success in
            result.value = success
        }

        XCTAssertTrue(waitUntil(timeout: 20) { result.value != nil })
        XCTAssertEqual(result.value, true)
        XCTAssertTrue(GleapStubURLProtocol.requests.filter { $0.path.hasPrefix("/uploads") }.isEmpty)
        let body = try XCTUnwrap(GleapStubURLProtocol.requests(path: "/bugs/v2").first?.json)
        XCTAssertEqual(body["type"] as? String, "CRASH")
        XCTAssertEqual(body["isSilent"] as? Bool, true)
        XCTAssertEqual(body["priority"] as? String, "HIGH")
        XCTAssertEqual((body["formData"] as? [String: Any])?["description"] as? String, "Payment failed")
        XCTAssertNil(body["attachments"])
    }

    func testSilentCrashReportSeverityMapping() throws {
        for (severity, priority) in [(LOW, "LOW"), (MEDIUM, "MEDIUM")] {
            GleapStubURLProtocol.reset()
            GleapStubURLProtocol.stub("POST", "/bugs/v2", .json(["id": "ticket-1"]))
            let result = GleapBox<Bool>()
            Gleap.sendSilentCrashReport(with: "Crash", andSeverity: severity, andDataExclusion: nil) { success in
                result.value = success
            }
            XCTAssertTrue(waitUntil(timeout: 20) { result.value != nil })
            let body = try XCTUnwrap(GleapStubURLProtocol.requests(path: "/bugs/v2").first?.json)
            XCTAssertEqual(body["priority"] as? String, priority)
        }
    }

    func testAttachmentsAreUploadedAndReferencedWithoutTheirData() throws {
        XCTAssertTrue(Gleap.addAttachment(with: Data("app log".utf8), andName: "log.txt"))
        XCTAssertTrue(Gleap.addAttachment(with: Data("{\"a\":1}".utf8), andName: "trace.json"))
        XCTAssertFalse(Gleap.addAttachment(with: Data(count: 10 * 1024 * 1024 + 1), andName: "huge.bin"))

        XCTAssertTrue(try XCTUnwrap(send(report())).success)

        let upload = try XCTUnwrap(GleapStubURLProtocol.requests(path: "/uploads/attachments").first)
        assertSessionHeaders(upload)
        XCTAssertTrue(upload.bodyString.contains("filename=log.txt"))
        XCTAssertTrue(upload.bodyString.contains("Content-Type: text/plain"))
        XCTAssertTrue(upload.bodyString.contains("filename=trace.json"))
        XCTAssertTrue(upload.bodyString.contains("Content-Type: application/json"))
        XCTAssertFalse(upload.bodyString.contains("huge.bin"))

        let body = try XCTUnwrap(GleapStubURLProtocol.requests(path: "/bugs/v2").first?.json)
        let attachments = try XCTUnwrap(body["attachments"] as? [[String: Any]])
        XCTAssertEqual(attachments.map { $0["name"] as? String }, ["log.txt", "trace.json"])
        XCTAssertEqual(attachments.map { $0["type"] as? String }, ["text/plain", "application/json"])
        XCTAssertEqual(attachments.map { $0["url"] as? String }, ["https://files.gleap.test/log.txt", "https://files.gleap.test/trace.json"])
        XCTAssertTrue(attachments.allSatisfy { $0["data"] == nil })
    }

    func testTicketAttributesTagsAndCustomDataAreAttached() throws {
        Gleap.setTicketAttributeWithKey("priority", value: "low")
        Gleap.setTicketAttributeWithKey("plan", value: "pro")
        Gleap.setTags(["vip", "ios"])
        Gleap.attachCustomData(["cartSize": 3])
        let feedback = GleapFeedback()
        feedback.appendData(["formData": ["description": "Refund missing", "priority": "high"]])

        XCTAssertTrue(try XCTUnwrap(send(feedback)).success)

        let body = try XCTUnwrap(GleapStubURLProtocol.requests(path: "/bugs/v2").first?.json)
        let formData = try XCTUnwrap(body["formData"] as? [String: Any])
        XCTAssertEqual(formData["priority"] as? String, "high", "form values win over ticket attributes")
        XCTAssertEqual(formData["plan"] as? String, "pro")
        XCTAssertEqual(formData["description"] as? String, "Refund missing")
        XCTAssertEqual(body["tags"] as? [String], ["vip", "ios"])
        XCTAssertEqual((body["customData"] as? [String: Any])?["cartSize"] as? Int, 3)
    }

    func testNetworkLogsInTheReportAreFilteredAndMasked() throws {
        let date = GleapUIHelper.getJSString(for: Date())
        Gleap.setNetworkLogPropsToIgnore(["password"])
        GleapHttpTrafficRecorder.shared().networkLogPropsToIgnore = ["token"]   // as the remote config sets it
        Gleap.setNetworkLogsBlacklist(["tracking.example"])
        Gleap.attachExternalData(["networkLogs": [
            [
                "date": date, "type": "POST", "url": "https://app.example/login",
                "request": [
                    "headers": ["Authorization": "Bearer secret-token", "Content-Type": "application/json"],
                    "payload": "{\"user\":\"ada\",\"password\":\"hunter2\",\"token\":\"t-1\"}",
                ],
                "response": ["status": 200, "responseText": "{\"ok\":true}"],
            ],
            ["date": date, "type": "GET", "url": "https://tracking.example/pixel", "request": ["headers": [:], "payload": ""]],
        ]])

        XCTAssertTrue(try XCTUnwrap(send(report())).success)

        let body = try XCTUnwrap(GleapStubURLProtocol.requests(path: "/bugs/v2").first?.json)
        let logs = try XCTUnwrap(body["networkLogs"] as? [[String: Any]])
        XCTAssertEqual(logs.map { $0["url"] as? String }, ["https://app.example/login"])
        let request = try XCTUnwrap(logs.first?["request"] as? [String: Any])
        XCTAssertEqual((request["headers"] as? [String: Any])?["Authorization"] as? String, "[REDACTED]")
        let payload = try XCTUnwrap(request["payload"] as? String)
        XCTAssertTrue(payload.contains("ada"))
        XCTAssertFalse(payload.contains("hunter2"))
        XCTAssertFalse(payload.contains("t-1"))
    }

    func testTicketDataForTheWidgetIsReadyBeforeTheDeadline() throws {
        Gleap.setEnvDataPropsToIgnore(["deviceName"])
        Gleap.attachCustomData(["plan": "pro"])
        Gleap.setTags(["vip"])
        Gleap.setTicketAttributeWithKey("source", value: "app")
        Gleap.attachExternalData(["networkLogs": [[
            "date": GleapUIHelper.getJSString(for: Date()), "type": "GET", "url": "https://app.example/me",
            "request": ["headers": ["Cookie": "session=abc"], "payload": ""],
        ]]])
        GleapEventLogHelper.sharedInstance().logEvent("checkout")
        let feedback = GleapFeedback()
        let done = GleapBox<Bool>()
        let start = Date()

        feedback.prepareData(withDeadline: 0.4) {
            done.value = true
        }

        XCTAssertTrue(waitUntil(timeout: 5) { done.value == true })
        XCTAssertLessThan(Date().timeIntervalSince(start), 3.0)
        let data = feedback.data
        let metaData = try XCTUnwrap(data["metaData"] as? [String: Any])
        XCTAssertNil(metaData["deviceName"])
        XCTAssertNotNil(metaData["deviceModel"])
        XCTAssertEqual((data["customData"] as? [String: Any])?["plan"] as? String, "pro")
        XCTAssertEqual((data["formData"] as? [String: Any])?["source"] as? String, "app")
        XCTAssertEqual(data["tags"] as? [String], ["vip"])
        XCTAssertNotNil(data["consoleLog"] as? [Any])
        XCTAssertTrue((data["customEventLog"] as? [[String: Any]] ?? []).contains { $0["name"] as? String == "checkout" })
        let log = try XCTUnwrap((data["networkLogs"] as? [[String: Any]])?.first)
        XCTAssertEqual(((log["request"] as? [String: Any])?["headers"] as? [String: Any])?["Cookie"] as? String, "[REDACTED]")
    }
}
