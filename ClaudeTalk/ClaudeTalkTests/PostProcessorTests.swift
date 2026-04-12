import XCTest
@testable import ClaudeTalk

final class PostProcessorTests: XCTestCase {

    let processor = PostProcessor()

    // MARK: - English filler removal

    func testRemoveEnglishFillers() {
        let input = "um I think um we should"
        let expected = "I think we should"
        XCTAssertEqual(processor.removeFillers(input), expected)
    }

    // MARK: - Chinese filler removal

    func testRemoveChineseFillers() {
        let input = "嗯我覺得啊這個就是可以"
        let expected = "我覺得這個可以"
        XCTAssertEqual(processor.removeFillers(input), expected)
    }

    // MARK: - Preserve valid words

    func testPreserveValidWords() {
        // "like" inside "likelihood" — \blike\b should NOT match "likelihood"
        let likelihoodInput = "the likelihood is high"
        XCTAssertEqual(processor.removeFillers(likelihoodInput), likelihoodInput,
                       "Should not alter 'likelihood'")

        // "right" in "right answer" — we do not remove "right" in adjective position
        let rightAnswerInput = "the right answer"
        XCTAssertEqual(processor.removeFillers(rightAnswerInput), rightAnswerInput,
                       "Should not alter 'right answer'")
    }

    // MARK: - Edge cases

    func testEmptyAndNoFillers() {
        XCTAssertEqual(processor.removeFillers(""), "")
        XCTAssertEqual(processor.removeFillers("hello world"), "hello world")
    }

    func testCleanupExtraSpaces() {
        let input = "um  um  hello"
        let expected = "hello"
        XCTAssertEqual(processor.removeFillers(input), expected)
    }

    // MARK: - process() enabled flag

    func testDisabledReturnsOriginal() {
        let input = "um I think uh we should"
        let result = processor.process(input, enabled: false)
        XCTAssertEqual(result, input, "Disabled mode must return original text unchanged")
    }

    // MARK: - Custom dictionary

    func testCustomDictionary() {
        let dictionary = ["克劳德": "Claude", "吉特": "Git"]
        let input = "克劳德 is great and 吉特 is version control"
        let result = processor.applyDictionary(input, dictionary: dictionary)
        XCTAssertTrue(result.contains("Claude"), "Should replace 克劳德 with Claude")
        XCTAssertTrue(result.contains("Git"), "Should replace 吉特 with Git")
        XCTAssertFalse(result.contains("克劳德"), "克劳德 should be replaced")
        XCTAssertFalse(result.contains("吉特"), "吉特 should be replaced")
    }

    // MARK: - process() with dictionary

    func testProcessWithDictionary() {
        let dictionary = ["克劳德": "Claude"]
        let input = "嗯克劳德 is great"
        let result = processor.process(input, enabled: true, dictionary: dictionary)
        XCTAssertEqual(result, "Claude is great")
    }

    // MARK: - removeWhisperLoops regression (2026-04-13)

    /// 2026-04-13 incident: user said "Hello, Hello, 我们再测试一下..." and the
    /// loop detector collapsed the entire utterance to just "Hello", losing
    /// the trailing sentence. Threshold tightened to count≥3 AND ratio>0.8.
    func testIntentionalDoubledWordPreservesRest() {
        let input = "Hello,Hello,我们再测试一下看这个功能会不会崩掉。"
        let result = processor.removeWhisperLoops(input)
        XCTAssertEqual(result, input, "intentionally doubled word should not collapse the surrounding sentence")
    }

    /// True Whisper hallucination loops should still be collapsed.
    func testTrueLoopStillCollapses() {
        let input = "Claude Talk。Claude Talk。Claude Talk。Claude Talk。Claude Talk。"
        let result = processor.removeWhisperLoops(input)
        XCTAssertEqual(result, "Claude Talk", "5x identical segments must be collapsed")
    }

    /// Edge case: 2x repetition is below the count≥3 threshold and must pass through.
    func testTwoRepetitionsAreNotALoop() {
        let input = "謝謝。謝謝。"
        let result = processor.removeWhisperLoops(input)
        XCTAssertEqual(result, input, "2x repetition is not enough to count as a loop")
    }
}
