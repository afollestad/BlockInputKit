import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputSlashCommandArgumentHintsTests: XCTestCase {
    func testRawSlashCommandUsesLeadingSpaceBeforeArgumentStart() {
        let hints = BlockInputSlashCommandArgumentHints(["review-github-pr": "[PR URL]"])
        let hint = hints.inlineHint(for: context(text: "/review-github-pr"))

        XCTAssertEqual(hint?.text, " [PR URL]")
        XCTAssertEqual(hint, BlockInputInlineHint(text: " [PR URL]"))
    }

    func testRawSlashCommandWithTrailingSpaceUsesBareHint() {
        let hints = BlockInputSlashCommandArgumentHints(["review-github-pr": "[PR URL]"])
        let hint = hints.inlineHint(for: context(text: "/review-github-pr "))

        XCTAssertEqual(hint?.text, "[PR URL]")
    }

    func testLinkBackedSlashCommandUsesHint() {
        let hints = BlockInputSlashCommandArgumentHints(["review-github-pr": "[PR URL]"])

        let hint = hints.inlineHint(for: context(text: "[/review-github-pr](demo://review) "))

        XCTAssertEqual(hint?.text, "[PR URL]")
    }

    func testLinkBackedSlashCommandWithoutTrailingSpaceUsesLeadingSpace() {
        let hints = BlockInputSlashCommandArgumentHints(["review-github-pr": "[PR URL]"])

        let hint = hints.inlineHint(for: context(text: "[/review-github-pr](demo://review)"))

        XCTAssertEqual(hint?.text, " [PR URL]")
    }

    func testLinkBackedSlashCommandAllowsEscapedClosingParenthesisInDestination() {
        let hints = BlockInputSlashCommandArgumentHints(["review-github-pr": "[PR URL]"])

        let hint = hints.inlineHint(for: context(text: #"[/review-github-pr](demo://review\)) "#))

        XCTAssertEqual(hint?.text, "[PR URL]")
    }

    func testCommandKeysAreNormalized() {
        let hints = BlockInputSlashCommandArgumentHints([" /Review-GitHub-PR ": " [PR URL] "])

        XCTAssertEqual(hints.inlineHint(for: context(text: "/review-github-pr"))?.text, " [PR URL]")
    }

    func testFirstDuplicateCommandHintWins() {
        let hints = BlockInputSlashCommandArgumentHints(commandHints: [
            (command: "review-github-pr", hint: "[FIRST]"),
            (command: "/Review-GitHub-PR", hint: "[SECOND]")
        ])

        XCTAssertEqual(hints.inlineHint(for: context(text: "/review-github-pr "))?.text, "[FIRST]")
    }

    func testRequiresDocumentStartByDefault() {
        let hints = BlockInputSlashCommandArgumentHints(["review-github-pr": "[PR URL]"])

        XCTAssertNil(hints.inlineHint(for: context(text: "/review-github-pr", blockIndex: 1)))
    }

    func testCanAllowNonDocumentStartBlocks() {
        let hints = BlockInputSlashCommandArgumentHints(
            ["review-github-pr": "[PR URL]"],
            requiresDocumentStart: false
        )

        XCTAssertEqual(hints.inlineHint(for: context(text: "/review-github-pr", blockIndex: 1))?.text, " [PR URL]")
    }

    func testHidesForRealArgumentsNewlineSelectionCaretBeforeEndAndMissingHint() {
        let hints = BlockInputSlashCommandArgumentHints(["review-github-pr": "[PR URL]"])

        XCTAssertNil(hints.inlineHint(for: context(text: "/review-github-pr https://example.com")))
        XCTAssertNil(hints.inlineHint(for: context(text: "/review-github-pr\n")))
        XCTAssertNil(hints.inlineHint(for: context(text: "/review-github-pr", selectedRange: NSRange(location: 0, length: 1))))
        XCTAssertNil(hints.inlineHint(for: context(text: "/review-github-pr", cursorOffset: 7)))
        XCTAssertNil(hints.inlineHint(for: context(text: "/unknown")))
    }

    func testEmptyCommandsAndHintsAreIgnored() {
        let hints = BlockInputSlashCommandArgumentHints(commandHints: [
            (command: "", hint: "[EMPTY COMMAND]"),
            (command: "review-github-pr", hint: " "),
            (command: "other", hint: "[OTHER]")
        ])

        XCTAssertNil(hints.inlineHint(for: context(text: "/review-github-pr")))
        XCTAssertEqual(hints.inlineHint(for: context(text: "/other"))?.text, " [OTHER]")
    }

    private func context(
        text: String,
        blockIndex: Int = 0,
        selectedRange: NSRange? = nil,
        cursorOffset: Int? = nil
    ) -> BlockInputInlineHintContext {
        let block = BlockInputBlock(id: "block", text: text)
        let offset = cursorOffset ?? (text as NSString).length
        return BlockInputInlineHintContext(
            editorView: BlockInputView(),
            block: block,
            blockIndex: blockIndex,
            cursor: BlockInputCursor(blockID: block.id, utf16Offset: offset),
            selectedRange: selectedRange ?? NSRange(location: offset, length: 0),
            isDocumentStartBlock: blockIndex == 0,
            isAtDocumentStart: blockIndex == 0 && offset == 0
        )
    }
}
