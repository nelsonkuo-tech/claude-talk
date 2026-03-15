import XCTest
@testable import ClaudeTalk

final class TerminalDetectorTests: XCTestCase {

    func testDefaultWhitelist() {
        let detector = TerminalDetector()

        // Should be recognized as terminals
        XCTAssertTrue(detector.isTerminal("Terminal"))
        XCTAssertTrue(detector.isTerminal("iTerm2"))
        XCTAssertTrue(detector.isTerminal("ghostty"))
        XCTAssertTrue(detector.isTerminal("Ghostty"))
        XCTAssertTrue(detector.isTerminal("kitty"))
        XCTAssertTrue(detector.isTerminal("Warp"))

        // Should NOT be recognized as terminals
        XCTAssertFalse(detector.isTerminal("Safari"))
        XCTAssertFalse(detector.isTerminal("Finder"))
    }

    func testCustomWhitelist() {
        let detector = TerminalDetector(whitelist: ["myterm"])

        XCTAssertTrue(detector.isTerminal("MyTerm"))
        XCTAssertFalse(detector.isTerminal("Terminal"))
    }

    func testCaseInsensitive() {
        let detector = TerminalDetector()

        XCTAssertTrue(detector.isTerminal("ITERM2"))
        XCTAssertTrue(detector.isTerminal("terminal"))
    }
}
