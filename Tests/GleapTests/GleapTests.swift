import XCTest
@testable import Gleap

final class iOS_SDK_crossTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Gleap.setRegion("eu")
    }

    override func tearDown() {
        Gleap.setRegion("eu")
        super.tearDown()
    }

    func testDefaultRegionIsEU() throws {
        let gleap = Gleap.sharedInstance()
        XCTAssertEqual(gleap.apiUrl, "https://api.gleap.io")
        XCTAssertEqual(gleap.wsApiUrl, "wss://ws.gleap.io")
        XCTAssertNil(gleap.realtimeHost)
    }

    func testSetRegionUSIsCaseInsensitiveAndKeepsStaticHosts() throws {
        let gleap = Gleap.sharedInstance()
        let frameUrl = gleap.frameUrl
        let bannerUrl = gleap.bannerUrl
        let modalUrl = gleap.modalUrl

        Gleap.setRegion("US")

        XCTAssertEqual(gleap.apiUrl, "https://api.us.gleap.ai")
        XCTAssertEqual(gleap.wsApiUrl, "wss://ws.us.gleap.ai")
        XCTAssertEqual(gleap.realtimeHost, "sockets.us.gleap.ai")
        XCTAssertEqual(gleap.frameUrl, frameUrl)
        XCTAssertEqual(gleap.bannerUrl, bannerUrl)
        XCTAssertEqual(gleap.modalUrl, modalUrl)
    }

    func testUnknownRegionChangesNothing() throws {
        let gleap = Gleap.sharedInstance()
        Gleap.setRegion("us")
        Gleap.setRegion("mars")

        XCTAssertEqual(gleap.apiUrl, "https://api.us.gleap.ai")
        XCTAssertEqual(gleap.wsApiUrl, "wss://ws.us.gleap.ai")
        XCTAssertEqual(gleap.realtimeHost, "sockets.us.gleap.ai")
    }

    func testManualSetterAfterSetRegionOverridesSingleHost() throws {
        let gleap = Gleap.sharedInstance()
        Gleap.setRegion("us")
        Gleap.setRealtimeHost("sockets.example.com")

        XCTAssertEqual(gleap.apiUrl, "https://api.us.gleap.ai")
        XCTAssertEqual(gleap.wsApiUrl, "wss://ws.us.gleap.ai")
        XCTAssertEqual(gleap.realtimeHost, "sockets.example.com")
    }

    func testLogEventWithDataRecoversImmutableBuffers() throws {
        let helper = GleapEventLogHelper()
        helper.setValue(NSArray(), forKey: "log")
        helper.setValue(NSArray(), forKey: "streamedLog")

        helper.logEvent("login", withData: ["source": "test"])

        XCTAssertTrue(helper.log.isKind(of: NSMutableArray.self))
        XCTAssertTrue(helper.streamedLog.isKind(of: NSMutableArray.self))
        XCTAssertEqual(helper.log.count, 1)
        XCTAssertEqual(helper.streamedLog.count, 1)
    }

    func testLogEventRecoversImmutableBuffers() throws {
        let helper = GleapEventLogHelper()
        helper.setValue(NSArray(), forKey: "log")
        helper.setValue(NSArray(), forKey: "streamedLog")

        helper.logEvent("login")

        XCTAssertTrue(helper.log.isKind(of: NSMutableArray.self))
        XCTAssertTrue(helper.streamedLog.isKind(of: NSMutableArray.self))
        XCTAssertEqual(helper.log.count, 1)
        XCTAssertEqual(helper.streamedLog.count, 1)
    }
}
