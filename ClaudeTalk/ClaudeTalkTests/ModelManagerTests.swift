import XCTest
@testable import ClaudeTalk

final class ModelManagerTests: XCTestCase {

    var manager: ModelManager!

    override func setUp() {
        super.setUp()
        manager = ModelManager()
    }

    func testModelDirectory() {
        let path = manager.modelsDirectory.path
        XCTAssertTrue(path.contains("Application Support/Claude Talk/models"), "Expected path to contain 'Application Support/Claude Talk/models', got: \(path)")
    }

    func testModelFilenameBase() {
        XCTAssertEqual(manager.filename(for: "base"), "ggml-base.bin")
    }

    func testModelFilenameSmall() {
        XCTAssertEqual(manager.filename(for: "small"), "ggml-small.bin")
    }

    func testIsDownloadedReturnsFalseForMissing() {
        XCTAssertFalse(manager.isDownloaded("nonexistent-model-\(UUID().uuidString)"))
    }
}
