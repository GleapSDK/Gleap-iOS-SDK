import XCTest
import ObjectiveC
@testable import Gleap

/// A report only counts as sent when the server accepted it.
final class GleapReportDeliveryTests: GleapNetworkTestCase {
    private let overloaded = GleapStubReply.json(["status": "overloaded", "reason": "request-budget"], status: 503, headers: ["Retry-After": "0.1"])

    override func setUp() {
        super.setUp()
        installSession(gleapId: "gid-1", gleapHash: "ghash-1")
        GleapStubURLProtocol.stub("POST", "/uploads/sdk", .json(["fileUrl": "https://files.gleap.test/screenshot.jpeg"]))
    }

    /// Answers the given replies in order, repeating the last one.
    private func stubSequence(_ path: String, _ replies: [GleapStubReply]) {
        let calls = GleapBox<Int>()
        GleapStubURLProtocol.stub("POST", path) { _ in
            let index = calls.value ?? 0
            calls.value = index + 1
            return replies[min(index, replies.count - 1)]
        }
    }

    private func report() -> GleapFeedback {
        let feedback = GleapFeedback()
        feedback.appendData(["formData": ["description": "Refund missing"]])
        return feedback
    }

    func testOverloadedServerIsAskedAgainOnce() throws {
        stubSequence("/bugs/v2", [overloaded, .json(["id": "ticket-1"])])

        let result = try XCTUnwrap(send(report()))

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.data["id"] as? String, "ticket-1")
        XCTAssertEqual(GleapStubURLProtocol.requests(path: "/bugs/v2").count, 2)
        XCTAssertEqual(spy.calls("feedbackSent").count, 1)
        XCTAssertTrue(spy.calls("feedbackSendingFailed").isEmpty)
    }

    func testReportFailsWhenTheServerStaysOverloaded() throws {
        stubSequence("/bugs/v2", [overloaded])

        let result = try XCTUnwrap(send(report()))

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.data["statusCode"] as? Int, 503)
        XCTAssertEqual(GleapStubURLProtocol.requests(path: "/bugs/v2").count, 2, "retried exactly once")
        XCTAssertEqual(spy.calls("feedbackSendingFailed").count, 1)
        XCTAssertTrue(spy.calls("feedbackSent").isEmpty)
    }

    func testRejectedReportIsNotReportedAsSent() throws {
        stubSequence("/bugs/v2", [.json(["error": ["statusCode": 413, "message": "Request body is too large"]], status: 413)])

        let result = try XCTUnwrap(send(report()))

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.data["statusCode"] as? Int, 413)
        XCTAssertEqual(GleapStubURLProtocol.requests(path: "/bugs/v2").count, 1, "only a 503 is retried")
        XCTAssertEqual(spy.calls("feedbackSendingFailed").count, 1)
        XCTAssertTrue(spy.calls("feedbackSent").isEmpty)
    }

    func testRejectedAttachmentUploadLeavesTheAttachmentsOut() throws {
        XCTAssertTrue(Gleap.addAttachment(with: Data("app log".utf8), andName: "log.txt"))
        stubSequence("/uploads/attachments", [.json(["error": ["statusCode": 413, "message": "Request body is too large"]], status: 413)])
        GleapStubURLProtocol.stub("POST", "/bugs/v2", .json(["id": "ticket-1"]))

        XCTAssertTrue(try XCTUnwrap(send(report())).success)

        let body = try XCTUnwrap(GleapStubURLProtocol.requests(path: "/bugs/v2").first?.json)
        XCTAssertNil(body["attachments"])
        XCTAssertNotNil(body["formData"])
    }

    func testUploadAnswerThatDoesNotListEveryFileLeavesTheAttachmentsOut() throws {
        XCTAssertTrue(Gleap.addAttachment(with: Data("app log".utf8), andName: "log.txt"))
        XCTAssertTrue(Gleap.addAttachment(with: Data("{}".utf8), andName: "trace.json"))
        let answers: [(String, GleapStubReply)] = [
            ("no fileUrls", .json(["status": "ok"])),
            ("one URL for two files", .json(["fileUrls": ["https://files.gleap.test/log.txt"]])),
            ("not a list", .json(["fileUrls": "https://files.gleap.test/log.txt"])),
            ("not URLs", .json(["fileUrls": [1, 2]])),
        ]
        for (name, reply) in answers {
            GleapStubURLProtocol.reset()
            GleapStubURLProtocol.stub("POST", "/uploads/attachments", reply)
            GleapStubURLProtocol.stub("POST", "/bugs/v2", .json(["id": "ticket-1"]))

            XCTAssertEqual(send(report())?.success, true, name)

            let body = try XCTUnwrap(GleapStubURLProtocol.requests(path: "/bugs/v2").first?.json, name)
            XCTAssertNil(body["attachments"], name)
        }
    }

    func testOverloadedUploadIsAskedAgainOnce() throws {
        stubSequence("/uploads/sdk", [overloaded, .json(["fileUrl": "https://files.gleap.test/retried.jpeg"])])
        GleapStubURLProtocol.stub("POST", "/bugs/v2", .json(["id": "ticket-1"]))
        let feedback = report()
        feedback.screenshot = Self.testImage()

        XCTAssertTrue(try XCTUnwrap(send(feedback)).success)

        XCTAssertEqual(GleapStubURLProtocol.requests(path: "/uploads/sdk").count, 2)
        let body = try XCTUnwrap(GleapStubURLProtocol.requests(path: "/bugs/v2").first?.json)
        XCTAssertEqual(body["screenshotUrl"] as? String, "https://files.gleap.test/retried.jpeg")
    }

    func testRetryWaitsForRetryAfterButNeverLongerThanFiveSeconds() throws {
        // The client is internal to the SDK, so its delay rule is reached through the runtime.
        let client: AnyClass = try XCTUnwrap(NSClassFromString("GleapAPIClient"))
        let selector = NSSelectorFromString("retryDelayForResponse:")
        let method = try XCTUnwrap(class_getClassMethod(client, selector))
        typealias RetryDelay = @convention(c) (AnyClass, Selector, HTTPURLResponse) -> Double
        let retryDelay = unsafeBitCast(method_getImplementation(method), to: RetryDelay.self)
        let url = try XCTUnwrap(URL(string: "https://api.gleap.test/bugs/v2"))

        let cases: [([String: String], Double)] = [
            (["Retry-After": "1"], 1),
            (["retry-after": "3"], 3),
            (["Retry-After": "120"], 5),
            (["Retry-After": "Wed, 21 Oct 2026 07:28:00 GMT"], 2),
            (["Retry-After": "-1"], 2),
            ([:], 2),
        ]
        for (headers, expected) in cases {
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 503, httpVersion: "HTTP/1.1", headerFields: headers))
            XCTAssertEqual(retryDelay(client, selector, response), expected, "\(headers)")
        }
    }
}
