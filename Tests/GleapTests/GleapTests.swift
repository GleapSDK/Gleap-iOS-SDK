import XCTest
@testable import Gleap
import Gleap_ObjC

final class iOS_SDK_crossTests: XCTestCase {
    func testExample() throws {
        Gleap.initialize(withToken: "")
        XCTAssertEqual(iOS_SDK_cross().text, "Hello, World!")
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
