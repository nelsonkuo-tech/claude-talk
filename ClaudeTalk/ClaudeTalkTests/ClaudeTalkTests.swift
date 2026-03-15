import XCTest
@testable import ClaudeTalk

final class ClaudeTalkTests: XCTestCase {

    func testAppDelegateExists() {
        let delegate = AppDelegate()
        XCTAssertNotNil(delegate)
    }
}
