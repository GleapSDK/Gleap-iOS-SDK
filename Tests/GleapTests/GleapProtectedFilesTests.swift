import QuickLook
import WebKit
import XCTest
@testable import Gleap

/// GleapProtectedFiles is internal to the SDK: its methods are reached through the runtime.
@objc private protocol GleapProtectedFilesTesting {
    func openFile(atURL url: String?, name: String?) -> Bool
    var presentFile: ((URL) -> Void)? { get set }
}

/// Records the links the SDK hands to the app.
private final class GleapLinkSpy: NSObject, GleapDelegate {
    var links: [URL] = []

    func openExternalLink(_ url: URL) {
        links.append(url)
    }
}

/// The frame manager with a test page in place of the Messenger, on the Messenger's origin: the
/// page posts what the Messenger would, through the real bridge.
private final class GleapTestPageFrameManager: GleapFrameManagerViewController {
    private typealias MakeConfiguration = @convention(c) (AnyClass, Selector, AnyObject, NSString, Bool) -> WKWebViewConfiguration
    var script = ""

    // Replaces the SDK's createWebView (called from viewDidLoad), which loads the live Messenger.
    @objc func createWebView() {
        let support: AnyClass = NSClassFromString("GleapWebViewSupport")!
        let selector = NSSelectorFromString("configurationWithMessageHandler:name:allowsInlineMediaPlayback:")
        let method = class_getClassMethod(support, selector)!
        let configuration = unsafeBitCast(method_getImplementation(method), to: MakeConfiguration.self)(support, selector, self, "gleapCallback", true)
        let webView = WKWebView(frame: view.bounds, configuration: configuration)
        view.addSubview(webView)
        setValue(webView, forKey: "webView")
        webView.loadHTMLString("<!doctype html><html><body><script>\(script)</script></body></html>",
                               baseURL: URL(string: Gleap.sharedInstance().frameUrl))
    }
}

/// Protected conversation files in the app: the widget asks the SDK to open one, the SDK
/// downloads it with the file session (and nothing else) and shows it.
final class GleapProtectedFilesTests: GleapNetworkTestCase {
    private static let token = String(repeating: "t", count: 43)
    private static let fileId = "0123456789abcdef01234567"
    private static let fileURL = "https://files.gleap.io/af/\(fileId)"
    private static let filePath = "/af/\(fileId)"
    private static let pdf = Data("%PDF-1.4 protected".utf8)

    private var frame: GleapCapturingFrameManager!
    private var files: GleapProtectedFilesTesting!
    private var shown: [URL] = []

    override func setUp() {
        super.setUp()
        Self.removeDownloadedFiles()
        frame = GleapCapturingFrameManager(format: "survey")
        files = unsafeBitCast(frame.value(forKey: "protectedFiles") as AnyObject, to: GleapProtectedFilesTesting.self)
        files.presentFile = { [weak self] url in self?.shown.append(url) }
    }

    override func tearDown() {
        files = nil
        frame = nil
        shown = []
        Self.removeDownloadedFiles()
        Gleap.sharedInstance().closeWidgetOnExternalLinkOpen = false
        super.tearDown()
    }

    private static func fileId(of url: String) -> String? {
        (NSClassFromString("GleapProtectedFiles") as AnyObject).perform(NSSelectorFromString("fileIdOfURL:"), with: url)?.takeUnretainedValue() as? String
    }

    private static func removeDownloadedFiles() {
        _ = (NSClassFromString("GleapProtectedFiles") as AnyObject).perform(NSSelectorFromString("removeDownloadedFiles"))
    }

    private static var downloadsFolder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("gleap-files")
    }

    @discardableResult
    private func installFileAccess() -> GleapSession {
        let session = installSession(gleapId: "gid-user", gleapHash: "ghash-user", userId: "user-1")
        session.authenticatedFilesRequired = true
        session.fileAccessToken = Self.token
        session.fileAccessExpiresAt = Date().addingTimeInterval(15 * 60)
        return session
    }

    private static func fileReply(type: String = "application/pdf", headers: [String: String] = [:]) -> GleapStubReply {
        var allHeaders = ["Content-Type": type]
        allHeaders.merge(headers) { _, new in new }
        return GleapStubReply(status: 200, headers: allHeaders, body: pdf)
    }

    func testOnlyProtectedFilesOfTheConfiguredRegionAreRecognized() {
        let id = Self.fileId
        XCTAssertEqual(Self.fileId(of: "https://files.gleap.io/af/\(id)"), id)
        XCTAssertEqual(Self.fileId(of: "https://files.gleap.io/files/af/\(id)"), id)
        XCTAssertNil(Self.fileId(of: "http://files.gleap.io/af/\(id)"))
        XCTAssertNil(Self.fileId(of: "https://files.gleap.io:8443/af/\(id)"))
        XCTAssertNil(Self.fileId(of: "https://user:pass@files.gleap.io/af/\(id)"))
        XCTAssertNil(Self.fileId(of: "https://files.gleap.io.example.com/af/\(id)"))
        XCTAssertNil(Self.fileId(of: "https://files.us.gleap.ai/af/\(id)"), "a US file is not one of the EU API")
        XCTAssertNil(Self.fileId(of: "https://files.gleap.io/af/\(id)/name.pdf"))
        XCTAssertNil(Self.fileId(of: "https://files.gleap.io/af/0123456789ABCDEF01234567"))
        XCTAssertNil(Self.fileId(of: "https://files.gleap.io/pf/\(id)"))
        XCTAssertNil(Self.fileId(of: "blob:https://messenger-app.gleap.io/5f6c"))

        Gleap.setRegion("us")
        XCTAssertEqual(Self.fileId(of: "https://files.us.gleap.ai/af/\(id)"), id)
        XCTAssertNil(Self.fileId(of: "https://files.gleap.io/af/\(id)"))

        Gleap.setApiUrl("http://localhost:9000")
        XCTAssertEqual(Self.fileId(of: "http://localhost:9000/af/\(id)"), id, "a local API serves its own files")
        XCTAssertNil(Self.fileId(of: "http://localhost:9001/af/\(id)"))
        XCTAssertNil(Self.fileId(of: "https://files.gleap.io/af/\(id)"))
    }

    func testAFileIsDownloadedWithTheFileSessionOnlyAndShownUnderItsName() throws {
        installFileAccess()
        GleapStubURLProtocol.stub("GET", Self.filePath, Self.fileReply())

        XCTAssertTrue(files.openFile(atURL: Self.fileURL, name: "Quarterly report"))

        XCTAssertTrue(waitUntil { self.shown.count == 1 })
        let request = try XCTUnwrap(GleapStubURLProtocol.requests(path: Self.filePath).first)
        XCTAssertEqual(request.url.absoluteString, Self.fileURL)
        XCTAssertEqual(request.header("X-File-Session"), Self.token)
        for header in ["Api-Token", "Gleap-Id", "Gleap-Hash", "Gleap-Grant", "Authorization"] {
            XCTAssertNil(request.header(header), "the files host gets no \(header)")
        }
        XCTAssertEqual(shown[0].lastPathComponent, "Quarterly report.pdf", "named with its type's extension")
        XCTAssertEqual(try Data(contentsOf: shown[0]), Self.pdf)
        XCTAssertTrue(shown[0].path.hasPrefix(Self.downloadsFolder.path))
    }

    func testAFileKeepsItsOwnExtensionAndAPathIsNoName() throws {
        installFileAccess()
        GleapStubURLProtocol.stub("GET", Self.filePath, Self.fileReply(type: "application/octet-stream"))

        XCTAssertTrue(files.openFile(atURL: Self.fileURL, name: "../../invoices/invoice-42.PDF"))

        XCTAssertTrue(waitUntil { self.shown.count == 1 })
        XCTAssertEqual(shown[0].lastPathComponent, "invoice-42.PDF")
        XCTAssertEqual(shown[0].deletingLastPathComponent().deletingLastPathComponent().path, Self.downloadsFolder.path)
    }

    func testWithoutAFileSessionTheFileWaitsForTheRenewedOne() throws {
        // A verified identify whose file session has expired (the app was in the background).
        installSession(gleapId: "gid-guest", gleapHash: "ghash-guest")
        GleapStubURLProtocol.stub("POST", "/sessions/identify", Self.identifyReply(expiresIn: -60))
        Gleap.identifyContact("user-1", andData: nil, andUserHash: "user-hash-1")
        XCTAssertTrue(waitUntil { GleapSessionHelper.sharedInstance().currentSession?.gleapId == "gid-user" })
        XCTAssertFalse(GleapSessionHelper.sharedInstance().currentSession?.hasFileAccess() ?? true)
        GleapStubURLProtocol.stub("POST", "/sessions/identify", Self.identifyReply(expiresIn: 15 * 60))
        GleapStubURLProtocol.stub("GET", Self.filePath, Self.fileReply())

        XCTAssertTrue(files.openFile(atURL: Self.fileURL, name: "report.pdf"))

        XCTAssertTrue(waitUntil { GleapStubURLProtocol.requests(path: "/sessions/identify").count == 2 }, "the file session is renewed")
        XCTAssertTrue(waitUntil { GleapSessionHelper.sharedInstance().currentSession?.hasFileAccess() == true })
        XCTAssertTrue(GleapStubURLProtocol.requests(path: Self.filePath).isEmpty, "nothing is requested without a file session")
        // The widget gets the renewed session (GleapWidgetManager does this for the open widget).
        frame.sendSessionUpdate()

        XCTAssertTrue(waitUntil { self.shown.count == 1 })
        XCTAssertEqual(GleapStubURLProtocol.requests(path: Self.filePath).first?.header("X-File-Session"), Self.token)
    }

    private static func identifyReply(expiresIn seconds: TimeInterval) -> GleapStubReply {
        let formatter = ISO8601DateFormatter()
        return sessionReply(gleapId: "gid-user", gleapHash: "ghash-user", extra: [
            "userId": "user-1", "authenticatedFilesRequired": true,
            "fileAccessToken": token, "fileAccessExpiresAt": formatter.string(from: Date().addingTimeInterval(seconds)),
        ])
    }

    func testOtherURLsNeverGetTheFileSession() {
        installFileAccess()

        XCTAssertFalse(files.openFile(atURL: "https://files.example.com/af/\(Self.fileId)", name: "x.pdf"))
        XCTAssertFalse(files.openFile(atURL: "https://example.com/report.pdf", name: nil))
        XCTAssertFalse(files.openFile(atURL: nil, name: nil))

        spin(0.5)
        XCTAssertTrue(GleapStubURLProtocol.requests.filter { $0.url.path.contains("/af/") }.isEmpty)
    }

    func testAFailedDownloadShowsNothingAndKeepsNothing() {
        installFileAccess()
        GleapStubURLProtocol.stub("GET", Self.filePath, .text("forbidden", status: 403))

        XCTAssertTrue(files.openFile(atURL: Self.fileURL, name: "report.pdf"))

        XCTAssertNotNil(waitForRequest(Self.filePath))
        spin(0.5)
        XCTAssertTrue(shown.isEmpty)
        let kept = (try? FileManager.default.subpathsOfDirectory(atPath: Self.downloadsFolder.path)) ?? []
        XCTAssertTrue(kept.isEmpty, "kept \(kept)")
    }

    func testALogoutDropsAFileOnItsWayAndTheFilesOpenedBefore() throws {
        installFileAccess()
        GleapStubURLProtocol.stub("GET", Self.filePath, Self.fileReply())
        XCTAssertTrue(files.openFile(atURL: Self.fileURL, name: "first.pdf"))
        XCTAssertTrue(waitUntil { self.shown.count == 1 })

        GleapStubURLProtocol.stub("GET", Self.filePath) { _ in
            Thread.sleep(forTimeInterval: 0.5)
            return Self.fileReply()
        }
        GleapStubURLProtocol.stub("POST", "/files/session/revoke", .json([:], status: 204))
        GleapStubURLProtocol.stub("POST", "/sessions", Self.sessionReply(gleapId: "gid-guest", gleapHash: "ghash-guest"))
        XCTAssertTrue(files.openFile(atURL: Self.fileURL, name: "second.pdf"))
        XCTAssertTrue(waitUntil { GleapStubURLProtocol.requests(path: Self.filePath).count == 2 })
        GleapSessionHelper.sharedInstance().clearSession()

        spin(1.0)
        XCTAssertEqual(shown.count, 1, "the second file is not shown to the next user")
        XCTAssertFalse(FileManager.default.fileExists(atPath: shown[0].path))
        let kept = (try? FileManager.default.subpathsOfDirectory(atPath: Self.downloadsFolder.path)) ?? []
        XCTAssertTrue(kept.isEmpty, "kept \(kept)")
    }

    func testTheWidgetsLinksNeverOpenAProtectedFileOrABlobOutside() throws {
        let links = GleapLinkSpy()
        Gleap.sharedInstance().delegate = links
        Gleap.sharedInstance().closeWidgetOnExternalLinkOpen = false
        installFileAccess()
        GleapStubURLProtocol.stub("GET", Self.filePath, Self.fileReply(headers: ["Content-Disposition": "attachment; filename=\"invoice.pdf\""]))

        frame.perform(NSSelectorFromString("openURLFromWidget:"), with: "blob:https://messenger-app.gleap.io/5f6c")
        frame.perform(NSSelectorFromString("openURLFromWidget:"), with: Self.fileURL)
        frame.perform(NSSelectorFromString("openURLFromWidget:"), with: "https://example.com/help")

        XCTAssertTrue(waitUntil { self.shown.count == 1 })
        XCTAssertEqual(shown[0].lastPathComponent, "invoice.pdf", "a link has no name: the server's is used")
        XCTAssertEqual(GleapStubURLProtocol.requests(path: Self.filePath).first?.header("X-File-Session"), Self.token)
        XCTAssertEqual(links.links.map(\.absoluteString), ["https://example.com/help"], "only the web link goes to the app")
    }

    func testABlobLinkDoesNotCloseTheWidget() {
        let links = GleapLinkSpy()
        Gleap.sharedInstance().delegate = links
        Gleap.sharedInstance().closeWidgetOnExternalLinkOpen = true
        frame.connected = true

        frame.perform(NSSelectorFromString("openURLFromWidget:"), with: "  BLOB:https://messenger-app.gleap.io/5f6c")

        spin(0.3)
        XCTAssertTrue(frame.connected, "closing the widget marks it disconnected")
        XCTAssertTrue(links.links.isEmpty)
    }

    /// The whole way on the simulator: the page's message through WebKit's bridge, the download,
    /// QuickLook presented over the widget in a key window with the downloaded file, the file
    /// deleted when QuickLook closes. Each step waits for its own event, with its own deadline:
    /// - WebKit starts its processes for the first page of the run: 30 to 40 s on a freshly
    ///   erased iPhone 16e / iOS 26.2 simulator here (5 s warm), more on a slow CI runner. A
    ///   single 30 s deadline for everything made CI fail now and then.
    /// - The SwiftPM test host connects no window scene, so its windows are never on screen and
    ///   UIKit never finishes a presentation's transition (isBeingPresented stays true). What can
    ///   be checked, and is, is that UIKit takes the presentation: QuickLook is the widget's
    ///   presented view controller, with the downloaded file as its item.
    func testTheMessengersMessageOpensTheFileInQuickLook() throws {
        installFileAccess()
        GleapStubURLProtocol.stub("GET", Self.filePath, Self.fileReply())
        // The SwiftPM test host connects no window scene: its windows are scene-less, as in an app
        // without a scene manifest. A host that has one gets a window in it.
        let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            .map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        let page = GleapTestPageFrameManager(format: "survey")
        page.script = "window.webkit.messageHandlers.gleapCallback.postMessage({name: 'open-protected-file', "
            + "data: {url: '\(Self.fileURL)', name: 'Quarterly report'}});"
        window.rootViewController = page
        window.makeKeyAndVisible()
        defer {
            // Nothing stays presented for the next test, and a download still on its way finds no
            // window to present in (the SDK then drops the file).
            page.presentedViewController?.dismiss(animated: false)
            window.rootViewController = nil
            window.isHidden = true
        }

        XCTContext.runActivity(named: "The page's message reaches the SDK through WebKit, which downloads the file") { _ in
            XCTAssertNotNil(waitForRequest(Self.filePath, timeout: 180))
        }
        let preview = try XCTContext.runActivity(named: "QuickLook is presented over the widget") { _ -> QLPreviewController in
            XCTAssertTrue(waitUntil(timeout: 30) { page.presentedViewController is QLPreviewController },
                          "presented: \(String(describing: page.presentedViewController))")
            return try XCTUnwrap(page.presentedViewController as? QLPreviewController)
        }
        let file = try XCTUnwrap(preview.currentPreviewItem?.previewItemURL)
        XCTAssertEqual(file.lastPathComponent, "Quarterly report.pdf")
        XCTAssertEqual(try Data(contentsOf: file), Self.pdf)
        XCTAssertEqual(GleapStubURLProtocol.requests(path: Self.filePath).first?.header("X-File-Session"), Self.token)

        // Done: QuickLook goes and so does the file.
        XCTContext.runActivity(named: "Closing QuickLook deletes the file") { _ in
            let dismissed = expectation(description: "QuickLook dismissed")
            preview.dismiss(animated: false) { dismissed.fulfill() }
            wait(for: [dismissed], timeout: 10)
            preview.delegate?.previewControllerDidDismiss?(preview)
            XCTAssertNil(page.presentedViewController)
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        }
    }

    func testTheSessionUpdateAnnouncesThatTheAppOpensProtectedFiles() throws {
        installFileAccess()

        frame.sendSessionUpdate()

        let data = try XCTUnwrap(frame.messages.last?["data"] as? [String: Any])
        let capabilities = try XCTUnwrap(data["capabilities"] as? [String: Any])
        XCTAssertEqual(capabilities["openProtectedFile"] as? Bool, true)
        XCTAssertEqual(capabilities["adoptSession"] as? Bool, true)
    }
}
