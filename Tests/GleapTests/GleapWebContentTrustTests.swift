import XCTest
import ObjectiveC
import WebKit
@testable import Gleap

/// Which web content may use the native bridge, the camera and the microphone. The rules live in
/// an internal class, so they are reached through the Objective-C runtime.
final class GleapWebContentTrustTests: XCTestCase {
    private typealias AcceptsMessage = @convention(c) (AnyClass, Selector, Bool, NSString?, NSString?) -> Bool
    private typealias MediaCaptureDecision = @convention(c) (AnyClass, Selector, NSString?, NSString?) -> Int
    private typealias MakeConfiguration = @convention(c) (AnyClass, Selector, AnyObject, NSString, Bool) -> WKWebViewConfiguration

    private func webViewSupport() throws -> AnyClass {
        try XCTUnwrap(NSClassFromString("GleapWebViewSupport"))
    }

    private func acceptsMessage() throws -> (Bool, String?, String?) -> Bool {
        let support: AnyClass = try webViewSupport()
        let selector = NSSelectorFromString("acceptsMessageFromMainFrame:host:forPageURL:")
        let method = try XCTUnwrap(class_getClassMethod(support, selector))
        let function = unsafeBitCast(method_getImplementation(method), to: AcceptsMessage.self)
        return { isMainFrame, host, pageURL in function(support, selector, isMainFrame, host as NSString?, pageURL as NSString?) }
    }

    func testOnlyTheMainFrameOfTheConfiguredHostMayUseTheBridge() throws {
        let accepts = try acceptsMessage()
        let frameUrl = "https://messenger-app.gleap.io/appnew"

        XCTAssertTrue(accepts(true, "messenger-app.gleap.io", frameUrl))
        XCTAssertTrue(accepts(true, "Messenger-App.Gleap.io", frameUrl), "hosts compare case-insensitively")
        XCTAssertFalse(accepts(false, "messenger-app.gleap.io", frameUrl), "a subframe, even on the same host")
        XCTAssertFalse(accepts(true, "www.youtube.com", frameUrl), "embedded third-party content")
        XCTAssertFalse(accepts(true, "messenger-app.gleap.io.example.com", frameUrl))
        XCTAssertFalse(accepts(true, "gleap.io", frameUrl))
        XCTAssertFalse(accepts(true, nil, frameUrl), "no origin (about:blank, data:)")
        XCTAssertFalse(accepts(true, "", frameUrl))
        XCTAssertFalse(accepts(true, "messenger-app.gleap.io", nil))
        XCTAssertFalse(accepts(true, "messenger-app.gleap.io", "not a url"))
        XCTAssertTrue(accepts(true, "outboundmedia.gleap.io", "https://outboundmedia.gleap.io/modal"))
        XCTAssertTrue(accepts(true, "localhost", "http://localhost:8765/frame"), "custom URLs work the same way")
    }

    func testOnlyTheBannersOwnPageGetsCameraAndMicrophoneWithoutAsking() throws {
        let support: AnyClass = try webViewSupport()
        let selector = NSSelectorFromString("mediaCaptureDecisionForHost:pageURL:")
        let method = try XCTUnwrap(class_getClassMethod(support, selector))
        let function = unsafeBitCast(method_getImplementation(method), to: MediaCaptureDecision.self)
        let decision = { (host: String?) in WKPermissionDecision(rawValue: function(support, selector, host as NSString?, "https://outboundmedia.gleap.io" as NSString)) }

        XCTAssertEqual(decision("outboundmedia.gleap.io"), .grant)
        XCTAssertEqual(decision("OutboundMedia.gleap.io"), .grant)
        XCTAssertEqual(decision("www.youtube.com"), .prompt)
        XCTAssertEqual(decision("outboundmedia.gleap.io.example.com"), .prompt)
        XCTAssertEqual(decision(nil), .prompt)
    }

    /// The web views share one private store while the app runs (a survey reopened in the same
    /// session keeps its answers), but never across Gleap users.
    func testWebViewsShareTheirStoreUntilTheGleapUserChanges() throws {
        let support: AnyClass = try webViewSupport()
        let selector = NSSelectorFromString("configurationWithMessageHandler:name:allowsInlineMediaPlayback:")
        let method = try XCTUnwrap(class_getClassMethod(support, selector))
        let function = unsafeBitCast(method_getImplementation(method), to: MakeConfiguration.self)
        final class Handler: NSObject, WKScriptMessageHandler {
            func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {}
        }
        let handler = Handler()
        let store = { function(support, selector, handler, "gleapCallback", false).websiteDataStore }

        let sessions = GleapSessionHelper.sharedInstance()
        let previous = sessions.currentSession
        defer { sessions.currentSession = previous }
        let session = { (gleapId: String) -> GleapSession in
            let session = GleapSession()
            session.gleapId = gleapId
            session.gleapHash = "hash-" + gleapId
            return session
        }

        sessions.currentSession = session("user-a")
        let first = store()
        XCTAssertFalse(first.isPersistent)
        XCTAssertTrue(first === store(), "one store for every web view")

        sessions.currentSession = session("user-a")
        XCTAssertTrue(first === store(), "the same user refreshed keeps it")

        sessions.currentSession = session("user-b")
        let second = store()
        XCTAssertFalse(first === second, "another user gets a new store")
        XCTAssertFalse(second.isPersistent)

        sessions.currentSession = nil
        XCTAssertFalse(second === store(), "a cleared identity gets a new store")
    }
}
