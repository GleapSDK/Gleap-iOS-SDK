import XCTest
@testable import Gleap

/// Feature switches the dashboard controls through the remote config.
final class GleapRemoteConfigTests: GleapNetworkTestCase {
    override func tearDown() {
        Gleap.stopNetworkRecording()
        GleapReplayHelper.sharedInstance().stop()
        GleapUIOverlayHelper.sharedInstance().showButtonExternalOverwrite = false
        super.tearDown()
    }

    private func stubConfig(_ flowConfig: [String: Any]) {
        GleapStubURLProtocol.stub("GET", "/config/\(Self.sdkKey)", .json(["flowConfig": flowConfig, "projectActions": ["bug": ["title": "Report a bug"]]]))
    }

    /// Loads the config and waits until it has been applied.
    private func load(_ flowConfig: [String: Any], reload: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        let marker = UUID().uuidString
        var config = flowConfig
        config["testMarker"] = marker
        stubConfig(config)
        if reload {
            GleapConfigHelper.sharedInstance().reload()
        } else {
            GleapConfigHelper.sharedInstance().run()
        }
        let applied = waitUntil {
            (GleapConfigHelper.sharedInstance().config as NSDictionary?)?["testMarker"] as? String == marker
        }
        XCTAssertTrue(applied, "config was not applied", file: file, line: line)
        // The rest of the config is applied on the same pass; give it a moment to finish.
        spin(0.2)
    }

    func testConfigIsRequestedForTheProjectAndLanguage() throws {
        load([:])

        let request = try XCTUnwrap(GleapStubURLProtocol.requests(path: "/config/\(Self.sdkKey)").first)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.url.host, "api.gleap.test")
        let query = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(query.first { $0.name == "lang" }?.value, GleapTranslationHelper.sharedInstance().language)
    }

    func testNetworkLogSwitchesReachTheRecorder() {
        let recorder = GleapHttpTrafficRecorder.shared()!
        load(["enableNetworkLogs": false])
        XCTAssertFalse(recorder.isRecording)

        load(["enableNetworkLogs": true, "networkLogPropsToIgnore": ["secret"], "networkLogBlacklist": ["blocked.example"]])

        XCTAssertTrue(recorder.isRecording)
        XCTAssertEqual(recorder.networkLogPropsToIgnore as? [String], ["secret"])
        XCTAssertEqual(recorder.blacklist as? [String], ["blocked.example"])
    }

    func testReplaySwitch() {
        let replays = GleapReplayHelper.sharedInstance()

        load(["enableReplays": true, "replaysInterval": 7])
        XCTAssertTrue(replays.running)
        XCTAssertEqual(replays.timerInterval, 7)

        load(["enableReplays": false])
        XCTAssertFalse(replays.running)
    }

    func testReplaysKeepRecordingWhenStartedAgain() {
        let replays = GleapReplayHelper.sharedInstance()
        let recording = { (replays.replayTimer as Timer?)?.isValid == true }

        replays.start()
        XCTAssertTrue(waitUntil(recording))

        // Going to the background stops the timer; coming back (or a new config) starts again.
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        XCTAssertFalse(recording())
        replays.start()

        XCTAssertTrue(waitUntil(recording), "the replays record again")
        XCTAssertTrue(replays.running)
    }

    func testActivationMethodsComeFromTheConfigUnlessTheAppSetsThem() {
        load(["activationMethodShake": true, "activationMethodScreenshotGesture": false])
        XCTAssertTrue(Gleap.isActivationMethodActive(SHAKE))
        XCTAssertFalse(Gleap.isActivationMethodActive(SCREENSHOT))

        Gleap.setActivationMethods([NSNumber(value: SCREENSHOT.rawValue)])
        load(["activationMethodShake": true, "activationMethodScreenshotGesture": false])
        XCTAssertFalse(Gleap.isActivationMethodActive(SHAKE), "methods set by the app are kept")
        XCTAssertTrue(Gleap.isActivationMethodActive(SCREENSHOT))

        Gleap.setActivationMethods([])
        Gleap.setAutoActivationMethodsDisabled()
        load(["activationMethodShake": true])
        XCTAssertFalse(Gleap.isActivationMethodActive(SHAKE), "disabled auto activation ignores the config")
    }

    func testButtonVisibilityFollowsTheConfigUnlessTheAppOverridesIt() {
        let overlay = GleapUIOverlayHelper.sharedInstance()
        overlay.showButtonExternalOverwrite = false

        load(["feedbackButtonPosition": "BUTTON_NONE"])
        XCTAssertFalse(overlay.showButton)

        load(["feedbackButtonPosition": "BOTTOM_RIGHT"])
        XCTAssertTrue(overlay.showButton)

        Gleap.showFeedbackButton(true)
        load(["feedbackButtonPosition": "BUTTON_NONE"])
        XCTAssertTrue(overlay.showButton, "showFeedbackButton wins over the config")
    }

    func testTheAppIsToldOnceThatTheConfigLoaded() {
        load(["enableReplays": false])
        XCTAssertTrue(waitUntil { self.spy.calls("initialized").count == 1 })
        XCTAssertEqual(spy.calls("configLoaded").count, 1)
        XCTAssertEqual((spy.calls("configLoaded").first?.payload as? [String: Any])?["enableReplays"] as? Bool, false)

        load(["enableReplays": false], reload: true)

        spin(0.3)
        XCTAssertEqual(spy.calls("configLoaded").count, 1, "a reload does not report the config again")
        XCTAssertEqual(spy.calls("initialized").count, 1)
    }
}
