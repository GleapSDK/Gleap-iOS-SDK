import XCTest
import ObjectiveC
import UIKit
@testable import Gleap

/// The pure parts of capture requests that guard correctness: what goes into a request path, the wire
/// format of the logs upload, the multipart body of a recording, and the sizes of screenshots and videos.
/// The classes are internal to the SDK, so they are reached through the Objective-C runtime.
final class GleapCaptureTests: XCTestCase {
    private typealias SizeForCanvas = @convention(c) (AnyClass, Selector, CGSize, CGFloat, CGFloat) -> CGSize
    private typealias ScaleForCanvas = @convention(c) (AnyClass, Selector, CGSize, CGFloat, CGFloat) -> CGFloat
    private typealias Letterbox = @convention(c) (AnyClass, Selector, CGSize, CGSize) -> CGRect
    private typealias ObjectToBool = @convention(c) (AnyClass, Selector, AnyObject?) -> Bool
    private typealias DoubleToDouble = @convention(c) (AnyClass, Selector, Double) -> Double
    private typealias ObjectToObject = @convention(c) (AnyClass, Selector, AnyObject?) -> AnyObject?
    private typealias BundleToData = @convention(c) (AnyClass, Selector, NSDictionary, UInt) -> NSData?
    private typealias WriteMultipart = @convention(c) (AnyClass, Selector, NSURL, NSString, NSString, NSString, NSURL, UnsafeMutablePointer<NSError?>?) -> Bool
    private typealias MaskTargets = @convention(c) (AnyClass, Selector, UIWindow, NSArray) -> NSArray
    private typealias PresentationRects = @convention(c) (AnyClass, Selector, NSArray, UIWindow) -> NSArray

    private func implementation<T>(_ className: String, _ selectorName: String, as type: T.Type) throws -> (AnyClass, Selector, T) {
        let cls: AnyClass = try XCTUnwrap(NSClassFromString(className), "\(className) is missing")
        let selector = NSSelectorFromString(selectorName)
        let method = try XCTUnwrap(class_getClassMethod(cls, selector), "\(className) \(selectorName) is missing")
        return (cls, selector, unsafeBitCast(method_getImplementation(method), to: type))
    }

    // MARK: - Request ids (they go into the request path)

    func testOnlyPlainIdsMayGoIntoTheRequestPath() throws {
        let (cls, selector, isValid): (AnyClass, Selector, ObjectToBool) = try implementation("GleapCaptureAPI", "isValidRequestId:", as: ObjectToBool.self)
        XCTAssertTrue(isValid(cls, selector, "66fb0c3e9d1f2a0012345678" as NSString))
        XCTAssertTrue(isValid(cls, selector, "cr_logs-1" as NSString))
        for invalid in ["", "../../uploads", "a/b", "a?b=c", "a%2Fb", "a b", "id\n", String(repeating: "a", count: 65)] {
            XCTAssertFalse(isValid(cls, selector, invalid as NSString), "\(invalid.debugDescription) must be refused")
        }
        XCTAssertFalse(isValid(cls, selector, nil))
        XCTAssertFalse(isValid(cls, selector, NSNumber(value: 42)))
    }

    // MARK: - Logs upload (Content-Encoding: gzip)

    func testGzipIsAValidGzipStreamOfTheInput() throws {
        let (cls, selector, gzip): (AnyClass, Selector, ObjectToObject) = try implementation("GleapLogsBundle", "gzipData:", as: ObjectToObject.self)
        let input = Data((0..<20_000).map { "line \($0) of the console log\n" }.joined().utf8)
        let output = try XCTUnwrap(gzip(cls, selector, input as NSData) as? Data)

        XCTAssertLessThan(output.count, input.count / 4, "console logs compress well")
        XCTAssertEqual(Array(output.prefix(3)), [0x1f, 0x8b, 0x08], "gzip magic and deflate")
        // RFC 1952 trailer: CRC-32 and the input size (mod 2^32), little endian.
        let trailer = Array(output.suffix(8))
        let size = UInt32(trailer[4]) | UInt32(trailer[5]) << 8 | UInt32(trailer[6]) << 16 | UInt32(trailer[7]) << 24
        XCTAssertEqual(Int(size), input.count)
        // The body between the 10-byte header (no optional fields) and the trailer is raw deflate.
        let deflated = output.subdata(in: 10..<(output.count - 8)) as NSData
        let inflated = try deflated.decompressed(using: .zlib) as Data
        XCTAssertEqual(inflated, input)
    }

    func testAnOversizedBundleLeavesOutNetworkThenConsoleLogs() throws {
        let (cls, selector, encode): (AnyClass, Selector, BundleToData) = try implementation("GleapLogsBundle", "gzippedJSONForBundle:maxBytes:", as: BundleToData.self)
        // Random text barely compresses, so the size limit decides what stays.
        func noise(_ count: Int) -> [String] { (0..<count).map { _ in UUID().uuidString + UUID().uuidString } }
        let bundle: NSDictionary = [
            "networkLogs": noise(4000),
            "consoleLog": noise(400),
            "customData": ["plan": "pro"],
            "platform": "ios",
        ]
        let small = try XCTUnwrap(encode(cls, selector, bundle, 40_000) as Data?)
        XCTAssertLessThanOrEqual(small.count, 40_000)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: try (small.subdata(in: 10..<(small.count - 8)) as NSData).decompressed(using: .zlib) as Data) as? [String: Any])
        XCTAssertNil(json["networkLogs"], "network logs go first")
        XCTAssertNotNil(json["consoleLog"], "console logs stay while they fit")
        XCTAssertEqual(json["platform"] as? String, "ios")

        XCTAssertNil(encode(cls, selector, ["blob": noise(4000)] as NSDictionary, 1_000), "nothing that fits: no upload")
    }

    func testBundleValuesAreAlwaysValidJSON() throws {
        let (cls, selector, sanitize): (AnyClass, Selector, ObjectToObject) = try implementation("GleapLogsBundle", "JSONSafeObject:", as: ObjectToObject.self)
        let input: NSDictionary = [
            "nan": NSNumber(value: Double.nan),
            "date": Date(timeIntervalSince1970: 0),
            "nested": [12: "number key", "ok": [URL(string: "https://gleap.io")!, Data([1, 2, 3])]] as NSDictionary,
        ]
        let safe = try XCTUnwrap(sanitize(cls, selector, input) as? [String: Any])
        XCTAssertTrue(JSONSerialization.isValidJSONObject(safe))
        XCTAssertTrue(safe["nan"] is NSNull)
        XCTAssertEqual(safe["date"] as? String, "1970-01-01T00:00:00.000Z")
        let nested = try XCTUnwrap(safe["nested"] as? [String: Any])
        XCTAssertEqual(Array(nested.keys), ["ok"], "non-string keys are left out, as in reports")
        XCTAssertEqual(nested["ok"] as? [String], ["https://gleap.io", "<3 bytes>"])
    }

    // MARK: - Masks

    /// Frames show the screen mid-animation. Masked content stays covered where it is on screen, not only where its
    /// model says it ends: a masked view sliding, a masked view fading out (already invisible in its model) and a
    /// password field inside a container that moves.
    func testMasksCoverViewsWhereTheyAreOnScreenMidAnimation() throws {
        let (cls, targetsSelector, maskTargets): (AnyClass, Selector, MaskTargets) = try implementation("GleapCaptureRenderer", "maskTargetsInWindow:maskedViews:", as: MaskTargets.self)
        let (_, rectsSelector, presentationRects): (AnyClass, Selector, PresentationRects) = try implementation("GleapCaptureRenderer", "presentationRectsOfViews:inWindow:", as: PresentationRects.self)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        window.isHidden = false
        defer { window.isHidden = true }
        let sliding = UIView(frame: CGRect(x: 250, y: 100, width: 100, height: 50))
        let fading = UIView(frame: CGRect(x: 0, y: 300, width: 100, height: 50))
        fading.alpha = 0
        let gone = UIView(frame: CGRect(x: 0, y: 400, width: 100, height: 50))
        gone.alpha = 0
        let container = UIView(frame: window.bounds)
        let password = UITextField(frame: CGRect(x: 0, y: 500, width: 200, height: 40))
        password.isSecureTextEntry = true
        container.addSubview(password)
        [sliding, fading, gone, container].forEach { window.addSubview($0) }

        // Each animation stands still halfway through.
        func freezeHalfway(_ layer: CALayer, _ keyPath: String, from: Any, to: Any) {
            let animation = CABasicAnimation(keyPath: keyPath)
            animation.fromValue = from
            animation.toValue = to
            animation.duration = 1
            animation.beginTime = 1e-9
            animation.fillMode = .both
            animation.isRemovedOnCompletion = false
            layer.speed = 0
            layer.timeOffset = 0.5
            layer.add(animation, forKey: "test")
        }
        freezeHalfway(sliding.layer, "position.x", from: 50, to: 300)
        freezeHalfway(fading.layer, "opacity", from: 1, to: 0)
        freezeHalfway(container.layer, "transform.translation.y", from: 400, to: 0)
        CATransaction.flush()
        let onScreen = try XCTUnwrap(sliding.layer.presentation(), "the test needs a presentation tree")
        XCTAssertEqual(onScreen.position.x, 175, accuracy: 0.5)

        let targets = maskTargets(cls, targetsSelector, window, [sliding, fading, gone] as NSArray) as! [UIView]
        XCTAssertTrue(targets.contains(sliding))
        XCTAssertTrue(targets.contains(fading), "invisible in the model, but still on screen")
        XCTAssertTrue(targets.contains(password), "secure text fields are masked without being registered")
        XCTAssertFalse(targets.contains(gone), "nothing to mask for a view that is not on screen")

        let rects = (presentationRects(cls, rectsSelector, targets as NSArray, window) as! [NSValue]).map { $0.cgRectValue }
        func rect(of view: UIView) -> CGRect { rects[targets.firstIndex(of: view)!] }
        XCTAssertEqual(rect(of: sliding).minX, 125, accuracy: 0.5, "halfway, not where the slide ends (250)")
        XCTAssertEqual(rect(of: sliding).width, 100, accuracy: 0.5)
        XCTAssertEqual(rect(of: password).minY, 700, accuracy: 0.5, "moved with its container")
        XCTAssertEqual(rect(of: fading), CGRect(x: 0, y: 300, width: 100, height: 50))
    }

    // MARK: - Recording upload (multipart streamed from a file)

    func testMultipartBodyWrapsTheFileUnchanged() throws {
        let (cls, selector, write): (AnyClass, Selector, WriteMultipart) = try implementation("GleapCaptureAPI", "writeMultipartBodyForFileAtURL:fileName:contentType:boundary:toURL:error:", as: WriteMultipart.self)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("screen-recording.mp4")
        // Larger than one copy chunk (256 KB), with every byte value.
        let content = Data((0..<700_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        try content.write(to: file)
        let body = directory.appendingPathComponent("body")

        XCTAssertTrue(write(cls, selector, file as NSURL, "screen \"recording\".mp4" as NSString, "video/mp4" as NSString, "BOUNDARY42" as NSString, body as NSURL, nil))
        let written = try Data(contentsOf: body)
        let head = Data("--BOUNDARY42\r\nContent-Disposition: form-data; name=\"file\"; filename=\"screen _recording_.mp4\"\r\nContent-Type: video/mp4\r\n\r\n".utf8)
        let tail = Data("\r\n--BOUNDARY42--\r\n".utf8)
        XCTAssertEqual(written.prefix(head.count), head, "quotes in the name cannot break the header")
        XCTAssertEqual(written.suffix(tail.count), tail)
        XCTAssertEqual(written.subdata(in: head.count..<(written.count - tail.count)), content)

        let missing = directory.appendingPathComponent("missing.mp4")
        XCTAssertFalse(write(cls, selector, missing as NSURL, "a.mp4" as NSString, "video/mp4" as NSString, "B" as NSString, body as NSURL, nil))
        XCTAssertFalse(FileManager.default.fileExists(atPath: body.path), "a failed body is removed")
    }

    // MARK: - Sizes

    func testScreenshotsStayWithinTheLongEdgeAndTheScreenResolution() throws {
        let (cls, selector, scale): (AnyClass, Selector, ScaleForCanvas) = try implementation("GleapCaptureRenderer", "pixelScaleForCanvasSize:screenScale:maxLongEdge:", as: ScaleForCanvas.self)
        let iPhone = scale(cls, selector, CGSize(width: 402, height: 874), 3, 2560)
        XCTAssertLessThanOrEqual(ceil(874 * iPhone), 2560)
        XCTAssertGreaterThan(874 * iPhone, 2550)
        XCTAssertEqual(scale(cls, selector, CGSize(width: 375, height: 667), 2, 2560), 2, "never sharper than the screen")
        let iPadLandscape = scale(cls, selector, CGSize(width: 1376, height: 1032), 2, 2560)
        XCTAssertLessThanOrEqual(ceil(1376 * iPadLandscape), 2560)
    }

    func testVideoSizeIsEvenWithinTheLongEdgeAndKeepsTheAspectRatio() throws {
        let (cls, selector, videoSize): (AnyClass, Selector, SizeForCanvas) = try implementation("GleapCaptureRenderer", "videoSizeForCanvasSize:screenScale:maxLongEdge:", as: SizeForCanvas.self)
        let cases: [(CGSize, CGFloat)] = [
            (CGSize(width: 402, height: 874), 3),    // iPhone 17 Pro
            (CGSize(width: 874, height: 402), 3),    // landscape
            (CGSize(width: 1032, height: 1376), 2),  // iPad Pro 13"
            (CGSize(width: 507, height: 1376), 2),   // iPad split view
            (CGSize(width: 333, height: 333), 1),    // small, odd, below the limit
        ]
        for (canvas, screenScale) in cases {
            let size = videoSize(cls, selector, canvas, screenScale, 1280)
            XCTAssertEqual(size.width.truncatingRemainder(dividingBy: 2), 0, "\(canvas)")
            XCTAssertEqual(size.height.truncatingRemainder(dividingBy: 2), 0, "\(canvas)")
            XCTAssertLessThanOrEqual(max(size.width, size.height), 1280, "\(canvas)")
            XCTAssertLessThanOrEqual(size.width, canvas.width * screenScale, "never above the screen's pixels")
            XCTAssertEqual(size.width / size.height, canvas.width / canvas.height, accuracy: 0.01, "\(canvas)")
        }
        XCTAssertEqual(videoSize(cls, selector, CGSize(width: 402, height: 874), 3, 1280), CGSize(width: 588, height: 1280))
        XCTAssertEqual(videoSize(cls, selector, .zero, 3, 1280), CGSize(width: 2, height: 2), "never an empty video")
    }

    func testLetterboxFitsCentersAndFillsTheOriginalSize() throws {
        let (cls, selector, letterbox): (AnyClass, Selector, Letterbox) = try implementation("GleapCaptureRenderer", "letterboxRectForContentSize:inOutputSize:", as: Letterbox.self)
        let portraitVideo = CGSize(width: 588, height: 1280)
        // The size the video was made for fills it (only rounded to even pixels).
        XCTAssertEqual(letterbox(cls, selector, CGSize(width: 402, height: 874), portraitVideo), CGRect(origin: .zero, size: portraitVideo))
        // After a rotation the landscape screen fits into the portrait video, centered.
        let rotated = letterbox(cls, selector, CGSize(width: 874, height: 402), portraitVideo)
        XCTAssertEqual(rotated.width, 588)
        XCTAssertEqual(rotated.height, 270, accuracy: 1)
        XCTAssertEqual(rotated.midY, 640, accuracy: 1)
        XCTAssertTrue(CGRect(origin: .zero, size: portraitVideo).contains(rotated))
        // A narrower window (split view) is pillarboxed.
        let narrow = letterbox(cls, selector, CGSize(width: 507, height: 1376), CGSize(width: 960, height: 1280))
        XCTAssertEqual(narrow.height, 1280)
        XCTAssertEqual(narrow.midX, 480, accuracy: 1)
        XCTAssertEqual(letterbox(cls, selector, .zero, portraitVideo), .zero)
    }

    func testFrameRateKeepsDrawingWithinTheMainThreadBudget() throws {
        let (cls, selector, framesPerSecond): (AnyClass, Selector, DoubleToDouble) = try implementation("GleapFrameRecorder", "framesPerSecondForDrawTime:", as: DoubleToDouble.self)
        XCTAssertEqual(framesPerSecond(cls, selector, 0), 4, "the target before anything was measured")
        XCTAssertEqual(framesPerSecond(cls, selector, 0.005), 8, "cheap frames: at most 8 fps")
        XCTAssertEqual(framesPerSecond(cls, selector, 0.05), 4, "the target while a frame takes ≤ 30 % of 250 ms")
        XCTAssertEqual(framesPerSecond(cls, selector, 0.1), 3, accuracy: 0.001, "slower: 30 % of the interval")
        XCTAssertEqual(framesPerSecond(cls, selector, 0.5), 2, "never below 2 fps")
        for draw in stride(from: 0.001, through: 0.15, by: 0.001) {
            let fps = framesPerSecond(cls, selector, draw)
            XCTAssertTrue((2...8).contains(fps))
            if fps > 2 {
                XCTAssertLessThanOrEqual(draw * fps, 0.3 + 1e-9, "drawing stays within 30 % of the interval at \(draw) s")
            }
        }
    }
}
