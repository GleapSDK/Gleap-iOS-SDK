import XCTest
@testable import Gleap
import Gleap_ObjC

final class iOS_SDK_crossTests: XCTestCase {
    func testExample() throws {
        Gleap.initialize(withToken: "")
        XCTAssertEqual(iOS_SDK_cross().text, "Hello, World!")
    }
}
