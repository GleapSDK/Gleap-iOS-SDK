import XCTest
@testable import Gleap

final class iOS_SDK_crossTests: XCTestCase {
    func testGleapInitializes() throws {
        // Basic smoke test: Gleap singleton should be accessible
        let instance = Gleap.sharedInstance()
        XCTAssertNotNil(instance, "Gleap shared instance should not be nil")
    }
}
