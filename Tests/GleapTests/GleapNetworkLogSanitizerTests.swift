import XCTest
@testable import Gleap

final class GleapNetworkLogSanitizerTests: XCTestCase {
    private func sanitize(_ logs: [Any], props: [String] = [], blacklist: [String] = []) -> [[String: Any]] {
        return GleapNetworkLogSanitizer.sanitizeNetworkLogs(logs, propsToIgnore: props, blacklist: blacklist) as! [[String: Any]]
    }

    private func entry(url: String = "https://api.example.com/v1/items",
                       requestHeaders: [String: Any] = [:],
                       payload: Any = "",
                       responseHeaders: [String: Any] = [:],
                       responseText: Any = "") -> [String: Any] {
        return [
            "date": "2026-09-27T10:00:00.000Z",
            "type": "POST",
            "url": url,
            "request": ["headers": requestHeaders, "payload": payload],
            "response": ["status": 200, "headers": responseHeaders, "responseText": responseText]
        ]
    }

    private func json(_ text: Any?) -> Any? {
        guard let string = text as? String, let data = string.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    func testCredentialHeadersAreMaskedWithoutAnyConfiguration() {
        let result = sanitize([entry(requestHeaders: ["Authorization": "Bearer secret", "cookie": "a=b", "Accept": "application/json"],
                                     responseHeaders: ["Set-Cookie": "session=1", "X-Request-Id": "r1"])])
        let request = result[0]["request"] as! [String: Any]
        let requestHeaders = request["headers"] as! [String: Any]
        XCTAssertEqual(requestHeaders["Authorization"] as? String, "[REDACTED]")
        XCTAssertEqual(requestHeaders["cookie"] as? String, "[REDACTED]")
        XCTAssertEqual(requestHeaders["Accept"] as? String, "application/json")
        let responseHeaders = (result[0]["response"] as! [String: Any])["headers"] as! [String: Any]
        XCTAssertEqual(responseHeaders["Set-Cookie"] as? String, "[REDACTED]")
        XCTAssertEqual(responseHeaders["X-Request-Id"] as? String, "r1")
    }

    func testIgnoredHeadersAreRemovedCaseInsensitively() {
        let result = sanitize([entry(requestHeaders: ["X-API-KEY": "k", "Accept": "*/*"], responseHeaders: ["x-api-key": "k2"])], props: ["x-api-key"])
        let requestHeaders = (result[0]["request"] as! [String: Any])["headers"] as! [String: Any]
        let responseHeaders = (result[0]["response"] as! [String: Any])["headers"] as! [String: Any]
        XCTAssertNil(requestHeaders["X-API-KEY"])
        XCTAssertNotNil(requestHeaders["Accept"])
        XCTAssertNil(responseHeaders["x-api-key"])
    }

    func testIgnoredKeysAreRemovedFromJSONBodiesAtAnyDepth() {
        let payload = #"{"password":"p","user":{"Password":"p2","name":"n"},"items":[{"token":"t"},{"id":1}]}"#
        let response = #"[{"token":"a","nested":{"token":"b","keep":true}}]"#
        let result = sanitize([entry(payload: payload, responseText: response)], props: ["password", "TOKEN"])
        let requestBody = json((result[0]["request"] as! [String: Any])["payload"]) as! [String: Any]
        XCTAssertNil(requestBody["password"])
        XCTAssertNil((requestBody["user"] as! [String: Any])["Password"])
        XCTAssertEqual((requestBody["user"] as! [String: Any])["name"] as? String, "n")
        XCTAssertNil(((requestBody["items"] as! [[String: Any]])[0])["token"])
        XCTAssertEqual(((requestBody["items"] as! [[String: Any]])[1])["id"] as? Int, 1)
        let responseBody = json((result[0]["response"] as! [String: Any])["responseText"]) as! [[String: Any]]
        XCTAssertNil(responseBody[0]["token"])
        XCTAssertNil((responseBody[0]["nested"] as! [String: Any])["token"])
        XCTAssertEqual((responseBody[0]["nested"] as! [String: Any])["keep"] as? Bool, true)
    }

    func testDottedPropsRemoveOnlyThatPath() {
        let payload = #"{"user":{"password":"p","name":"n"},"password":"root","list":[{"user":{"password":"x"}}]}"#
        let result = sanitize([entry(payload: payload)], props: ["user.password"])
        let body = json((result[0]["request"] as! [String: Any])["payload"]) as! [String: Any]
        XCTAssertNil((body["user"] as! [String: Any])["password"])
        XCTAssertEqual((body["user"] as! [String: Any])["name"] as? String, "n")
        XCTAssertEqual(body["password"] as? String, "root")
        // Arrays at the root level of the path are not traversed from a nested key.
        XCTAssertNotNil(((body["list"] as! [[String: Any]])[0]["user"] as! [String: Any])["password"])
    }

    func testUnchangedAndNonJSONBodiesStayByteIdentical() {
        let untouchedJSON = #"{ "b": 1,  "a": 2 }"#
        let truncatedJSON = #"{"name":"n","items":[1,2"#
        let text = "plain text with password inside"
        let result = sanitize([entry(payload: untouchedJSON, responseText: truncatedJSON),
                               entry(payload: text, responseText: "")], props: ["password"])
        XCTAssertEqual((result[0]["request"] as! [String: Any])["payload"] as? String, untouchedJSON)
        XCTAssertEqual((result[0]["response"] as! [String: Any])["responseText"] as? String, truncatedJSON)
        XCTAssertEqual((result[1]["request"] as! [String: Any])["payload"] as? String, text)
    }

    func testIgnoredKeysAreMaskedInJSONCutAtTheSizeLimit() {
        let truncated = "{\"user\":{\"password\":\"pw-0\",\"name\":\"n\"},\"token\":\"abc\",\"items\":[{\"Token\":\"x\"" + "\n… [truncated, 200000 bytes]"
        let result = sanitize([entry(responseText: truncated)], props: ["password", "token"])
        let text = (result[0]["response"] as! [String: Any])["responseText"] as! String
        XCTAssertEqual(text, "{\"user\":{\"password\":\"[REDACTED]\",\"name\":\"n\"},\"token\":\"[REDACTED]\",\"items\":[{\"Token\":\"[REDACTED]\"" + "\n… [truncated, 200000 bytes]")

        let cutInsideValue = "{\"session\":{\"secret\":\"abcdef" + "\n… [truncated, 200000 bytes]"
        let dotted = sanitize([entry(responseText: cutInsideValue)], props: ["session.secret"])
        XCTAssertEqual((dotted[0]["response"] as! [String: Any])["responseText"] as? String, "{\"session\":{\"secret\":\"[REDACTED]\"" + "\n… [truncated, 200000 bytes]")
    }

    func testFormBodiesAndQueryParametersAreRedacted() {
        let result = sanitize([entry(url: "https://api.example.com/login?Token=abc&page=2#top",
                                     requestHeaders: ["Content-Type": "application/x-www-form-urlencoded"],
                                     payload: "username=u&password=secret&remember=1")],
                              props: ["password", "token"])
        XCTAssertEqual(result[0]["url"] as? String, "https://api.example.com/login?page=2#top")
        XCTAssertEqual((result[0]["request"] as! [String: Any])["payload"] as? String, "username=u&remember=1")

        let onlySecret = sanitize([entry(url: "https://api.example.com/cb?token=abc")], props: ["token"])
        XCTAssertEqual(onlySecret[0]["url"] as? String, "https://api.example.com/cb")
    }

    func testBlacklistDropsGleapHostsAndConfiguredEntries() {
        let result = sanitize([entry(url: "https://api.gleap.io/sdk/events"),
                               entry(url: "https://api.eu.gleap.ai/v3/session"),
                               entry(url: "https://tracking.example.com/pixel"),
                               entry(url: "https://api.example.com/keep")],
                              blacklist: ["tracking.example.com"])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0]["url"] as? String, "https://api.example.com/keep")
        XCTAssertTrue(GleapNetworkLogSanitizer.isURLBlacklisted("https://API.GLEAP.IO/x", blacklist: nil))
    }

    func testParsedBodiesFromWrapperSDKsAreRedactedAndInvalidEntriesDropped() {
        let parsed: [String: Any] = ["user": ["password": "p", "id": 1]]
        let result = sanitize([entry(payload: parsed), "not an entry", 42], props: ["password"])
        XCTAssertEqual(result.count, 1)
        let payload = (result[0]["request"] as! [String: Any])["payload"] as! [String: Any]
        XCTAssertNil((payload["user"] as! [String: Any])["password"])
        XCTAssertEqual((payload["user"] as! [String: Any])["id"] as? Int, 1)
    }
}
