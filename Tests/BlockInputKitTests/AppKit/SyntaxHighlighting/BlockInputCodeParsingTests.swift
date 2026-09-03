import XCTest
@testable import BlockInputKit

final class BlockInputCodeParsingTests: XCTestCase {
    func testInlineCodeRangesSeparateContentFromSingleBacktickDelimiters() {
        let ranges = BlockInputCodeParsing.inlineCodeRanges(in: "Use `git status` here")

        XCTAssertEqual(ranges, [
            BlockInputInlineCodeRange(
                fullRange: NSRange(location: 4, length: 12),
                contentRange: NSRange(location: 5, length: 10),
                delimiterRanges: [
                    NSRange(location: 4, length: 1),
                    NSRange(location: 15, length: 1)
                ]
            )
        ])
    }

    func testInlineCodeRangesIgnoreUnmatchedAndEmptySpans() {
        XCTAssertEqual(BlockInputCodeParsing.inlineCodeRanges(in: "Use `git status"), [])
        XCTAssertEqual(BlockInputCodeParsing.inlineCodeRanges(in: "Use `` here"), [])
    }

    func testInlineCodeRangesPairAcrossLineBreaks() {
        let ranges = BlockInputCodeParsing.inlineCodeRanges(in: "Use `git\nstatus` here")

        XCTAssertEqual(ranges.map(\.fullRange), [NSRange(location: 4, length: 12)])
        XCTAssertEqual(ranges.map(\.contentRange), [NSRange(location: 5, length: 10)])
    }

    /// A closer stranded on the next line used to become an opener, which shifted every later
    /// pairing on that line: `" d "` was styled and `e` was not.
    func testInlineCodeRangesKeepLaterSpansPairedWhenAnOpenerClosesOnTheNextLine() {
        let ranges = BlockInputCodeParsing.inlineCodeRanges(in: "a `b\nc` d `e` f")

        XCTAssertEqual(ranges.map(\.contentRange), [
            NSRange(location: 3, length: 3),
            NSRange(location: 11, length: 1)
        ])
    }

    /// CommonMark's answer: an orphan backtick pairs with the next single backtick, so `bar`
    /// loses its closer. The scanner does not try to guess which backtick was the stray one.
    func testInlineCodeRangesPairAnOrphanBacktickWithTheNextOneAsCommonMarkDoes() {
        let ranges = BlockInputCodeParsing.inlineCodeRanges(in: "Use `foo` and ` then `bar` end")

        XCTAssertEqual(ranges.map(\.contentRange), [
            NSRange(location: 5, length: 3),
            NSRange(location: 15, length: 6)
        ])
    }

    func testInlineCodeRangesTreatADoubleBacktickRunInsideASpanAsContent() {
        XCTAssertEqual(
            BlockInputCodeParsing.inlineCodeRanges(in: "`x``y`").map(\.contentRange),
            [NSRange(location: 1, length: 4)]
        )
    }

    func testInlineCodeRangesIgnoreMultiBacktickDelimiters() {
        XCTAssertEqual(BlockInputCodeParsing.inlineCodeRanges(in: "Use ``git status`` here"), [])
    }

    func testInlineCodeRangesFindMultipleSpans() {
        let ranges = BlockInputCodeParsing.inlineCodeRanges(in: "`one` and `two`")

        XCTAssertEqual(ranges.map(\.contentRange), [
            NSRange(location: 1, length: 3),
            NSRange(location: 11, length: 3)
        ])
    }

    func testCodeFenceOpeningParsesOptionalLanguage() {
        XCTAssertEqual(BlockInputCodeParsing.codeFenceOpening(in: "```"), BlockInputCodeFenceOpening(language: nil))
        XCTAssertEqual(BlockInputCodeParsing.codeFenceOpening(in: "```swift"), BlockInputCodeFenceOpening(language: "swift"))
        XCTAssertEqual(BlockInputCodeParsing.codeFenceOpening(in: "``` swift "), BlockInputCodeFenceOpening(language: "swift"))
        XCTAssertEqual(BlockInputCodeParsing.codeFenceOpening(in: "  ```swift  "), BlockInputCodeFenceOpening(language: "swift"))
    }

    func testCodeFenceOpeningRejectsNonFenceTextAndLongerFences() {
        XCTAssertNil(BlockInputCodeParsing.codeFenceOpening(in: "before ```swift"))
        XCTAssertNil(BlockInputCodeParsing.codeFenceOpening(in: "`swift"))
        XCTAssertNil(BlockInputCodeParsing.codeFenceOpening(in: "````swift"))
        XCTAssertNil(BlockInputCodeParsing.codeFenceOpening(in: "``` `swift"))
        XCTAssertNil(BlockInputCodeParsing.codeFenceOpening(in: "```swift`"))
        XCTAssertNil(BlockInputCodeParsing.codeFenceOpening(in: "```\nswift"))
    }
}
