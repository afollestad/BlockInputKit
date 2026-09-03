import AppKit
import XCTest
@testable import BlockInputKit

/// Hidden backtick delimiters are zero-width, so a caret parked beside one draws at the same x
/// as the caret on its other side. Movement has to hop them the way it hops hidden link source.
@MainActor
final class BlockInputInlineCodeNavigationTests: XCTestCase {
    private let text = "Use `git status` now"

    func testPlainRightBeforeOpeningBacktickSkipsTheHiddenDelimiter() throws {
        let textView = try mountedTextView(for: text)
        textView.setSelectedRange(NSRange(location: 4, length: 0))

        textView.keyDown(with: try plainRightEvent())

        XCTAssertEqual(textView.selectedRange(), NSRange(location: 6, length: 0))
    }

    func testPlainLeftAfterFirstCodeCharacterSkipsTheHiddenOpener() throws {
        let textView = try mountedTextView(for: text)
        textView.setSelectedRange(NSRange(location: 6, length: 0))

        textView.keyDown(with: try plainLeftEvent())
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 5, length: 0), "inside the span, native movement")
        textView.keyDown(with: try plainLeftEvent())

        XCTAssertEqual(textView.selectedRange(), NSRange(location: 3, length: 0), "the hidden opener is hopped")
    }

    func testPlainRightBeforeClosingBacktickSkipsTheHiddenDelimiter() throws {
        let textView = try mountedTextView(for: text)
        textView.setSelectedRange(NSRange(location: 15, length: 0))

        textView.keyDown(with: try plainRightEvent())

        XCTAssertEqual(textView.selectedRange(), NSRange(location: 17, length: 0))
    }

    func testPlainLeftAfterClosingBacktickSkipsTheHiddenDelimiter() throws {
        let textView = try mountedTextView(for: text)
        textView.setSelectedRange(NSRange(location: 16, length: 0))

        textView.keyDown(with: try plainLeftEvent())

        XCTAssertEqual(textView.selectedRange(), NSRange(location: 14, length: 0))
    }

    func testRepeatedPlainRightNeverParksOnAHiddenBacktick() throws {
        let textView = try mountedTextView(for: "Run `git status` then `git log` now")
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        var previousX = try caretRect(in: textView).minX

        while textView.selectedRange().location < (textView.string as NSString).length {
            textView.keyDown(with: try plainRightEvent())
            let currentX = try caretRect(in: textView).minX
            XCTAssertGreaterThan(currentX, previousX + 0.5, "dead press at offset \(textView.selectedRange().location)")
            previousX = currentX
        }
    }

    func testOptionRightSkipsHiddenBackticks() throws {
        let textView = try mountedTextView(for: text)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        var offsets: [Int] = []

        for _ in 0..<4 {
            textView.keyDown(with: try optionRightEvent())
            offsets.append(textView.selectedRange().location)
        }

        XCTAssertEqual(offsets, [3, 8, 15, 20])
    }

    func testDeleteBackwardAfterClosingBacktickRemovesTheDelimiterAndUnpairsTheSpan() throws {
        let textView = try mountedTextView(for: text)
        textView.setSelectedRange(NSRange(location: 16, length: 0))

        textView.deleteBackward(nil)

        XCTAssertEqual(textView.string, "Use `git status now")
        XCTAssertNil(textView.textStorage?.attribute(.backgroundColor, at: 5, effectiveRange: nil))
    }

    private func mountedTextView(for text: String) throws -> BlockInputTextView {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "paragraph", kind: .paragraph, text: text)
            ])
        ))
        resizeMountedBlockInputView(mounted, to: NSSize(width: 620, height: 140))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.layoutManager?.ensureLayout(for: try XCTUnwrap(textView.textContainer))
        return textView
    }

    private func caretRect(in textView: BlockInputTextView) throws -> NSRect {
        let screenRect = textView.firstRect(forCharacterRange: textView.selectedRange(), actualRange: nil)
        guard screenRect != .zero, !screenRect.isNull, !screenRect.isInfinite else {
            return try XCTUnwrap(Optional<NSRect>.none)
        }
        let window = try XCTUnwrap(textView.window)
        let windowPoint = window.convertPoint(fromScreen: screenRect.origin)
        return NSRect(origin: textView.convert(windowPoint, from: nil), size: screenRect.size)
    }
}
