import XCTest
@testable import Gleap

final class GleapEnvDataTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Gleap.setEnvDataPropsToIgnore([])
        Gleap.setDisableEnvData(false)
    }

    override func tearDown() {
        Gleap.setEnvDataPropsToIgnore([])
        Gleap.setDisableEnvData(false)
        super.tearDown()
    }

    func testCollectsTheFullEnvDataByDefault() throws {
        let metaData = GleapMetaDataHelper.sharedInstance().getMetaData()

        XCTAssertNotNil(metaData["deviceModel"])
        XCTAssertNotNil(metaData["systemVersion"])
        XCTAssertNotNil(metaData["screenWidth"])
        XCTAssertNotNil(metaData["sdkVersion"])
    }

    func testIgnoredPropsAreRemovedAndEverythingElseIsKept() throws {
        Gleap.setEnvDataPropsToIgnore(["deviceName", "batteryLevel", "unknownKey"])

        let metaData = GleapMetaDataHelper.sharedInstance().getMetaData()

        XCTAssertNil(metaData["deviceName"])
        XCTAssertNil(metaData["batteryLevel"])
        XCTAssertNotNil(metaData["deviceModel"])
        XCTAssertNotNil(metaData["sdkVersion"])
    }

    func testEachCallReplacesThePreviousList() throws {
        Gleap.setEnvDataPropsToIgnore(["deviceName"])
        Gleap.setEnvDataPropsToIgnore(["systemVersion"])

        var metaData = GleapMetaDataHelper.sharedInstance().getMetaData()
        XCTAssertNotNil(metaData["deviceName"])
        XCTAssertNil(metaData["systemVersion"])

        Gleap.setEnvDataPropsToIgnore([])
        metaData = GleapMetaDataHelper.sharedInstance().getMetaData()
        XCTAssertNotNil(metaData["systemVersion"])
    }

    func testDisabledEnvDataIsEmpty() throws {
        Gleap.setDisableEnvData(true)

        XCTAssertTrue(GleapMetaDataHelper.sharedInstance().getMetaData().isEmpty)
    }

    func testEnvDataCanBeEnabledAgainKeepingTheIgnoredProps() throws {
        Gleap.setEnvDataPropsToIgnore(["deviceName"])
        Gleap.setDisableEnvData(true)
        Gleap.setDisableEnvData(false)

        let metaData = GleapMetaDataHelper.sharedInstance().getMetaData()
        XCTAssertNil(metaData["deviceName"])
        XCTAssertNotNil(metaData["deviceModel"])
    }

    func testTicketDataCarriesTheFilteredEnvData() throws {
        Gleap.setEnvDataPropsToIgnore(["deviceName"])

        let feedback = GleapFeedback()
        feedback.prepareMainThreadData()

        let metaData = feedback.data["metaData"] as? [AnyHashable: Any]
        XCTAssertNotNil(metaData)
        XCTAssertNil(metaData?["deviceName"])
        XCTAssertNotNil(metaData?["deviceModel"])
    }
}
