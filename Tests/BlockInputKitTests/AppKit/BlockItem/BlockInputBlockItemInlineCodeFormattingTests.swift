import AppKit
import XCTest
@testable import BlockInputKit

final class BlockInputInlineCodeFormattingTests: XCTestCase {
    @MainActor
    func testInlineCodeUsesMonospacedStylingInSupportedTextBlocks() throws {
        let supportedKinds: [BlockInputBlockKind] = [
            .paragraph,
            .heading(level: 2),
            .quote,
            .bulletedListItem,
            .numberedListItem(start: 1),
            .checklistItem(isChecked: false)
        ]

        for kind in supportedKinds {
            let item = BlockInputBlockItem.configuredForTesting(
                block: BlockInputBlock(id: BlockInputBlockID(rawValue: "\(kind)"), kind: kind, text: "Use `git status` now"),
                allowsReordering: true,
                delegate: BlockInputView()
            )
            let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)
            let codeFont = try XCTUnwrap(textStorage.attribute(.font, at: 5, effectiveRange: nil) as? NSFont)
            let baseFont = try XCTUnwrap(textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)

            XCTAssertTrue(codeFont.fontDescriptor.symbolicTraits.contains(.monoSpace), "Expected inline code font for \(kind).")
            XCTAssertFalse(baseFont.fontDescriptor.symbolicTraits.contains(.monoSpace), "Expected base text font for \(kind).")
            XCTAssertEqual(
                textStorage.attribute(.backgroundColor, at: 5, effectiveRange: nil) as? NSColor,
                BlockInputBlockItem.inlineCodeBackgroundColor,
                "Expected inline code background for \(kind)."
            )
            XCTAssertNil(textStorage.attribute(.backgroundColor, at: 0, effectiveRange: nil))
        }
    }

    @MainActor
    func testInlineCodeUsesCustomStyleOverrides() throws {
        let inlineFont = NSFont.monospacedSystemFont(ofSize: 18, weight: .medium)
        let style = BlockInputStyle(
            baseText: BlockInputTextStyle(font: .systemFont(ofSize: 16), foregroundColor: .systemGreen),
            inlineCode: BlockInputInlineCodeStyle(
                font: inlineFont,
                foregroundColor: .systemRed,
                backgroundColor: .systemYellow
            )
        )
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", text: "Use `git status` now"),
            allowsReordering: true,
            style: style,
            delegate: BlockInputView()
        )
        let textView = try XCTUnwrap(item.testingTextView)
        let textStorage = try XCTUnwrap(textView.textStorage)

        XCTAssertEqual(try XCTUnwrap(textStorage.attribute(.font, at: 5, effectiveRange: nil) as? NSFont).pointSize, inlineFont.pointSize)
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 5, effectiveRange: nil) as? NSColor, .systemRed)
        XCTAssertEqual(textStorage.attribute(.backgroundColor, at: 5, effectiveRange: nil) as? NSColor, .systemYellow)
        XCTAssertNil(textStorage.attribute(.backgroundColor, at: 4, effectiveRange: nil))
        XCTAssertNil(textStorage.attribute(.backgroundColor, at: 15, effectiveRange: nil))
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .systemGreen)

        item.setSelectedRange(NSRange(location: 7, length: 0))
        XCTAssertEqual(try XCTUnwrap(textView.typingAttributes[.font] as? NSFont).pointSize, inlineFont.pointSize)
        XCTAssertEqual(textView.typingAttributes[.foregroundColor] as? NSColor, .systemRed)
        XCTAssertEqual(textView.typingAttributes[.backgroundColor] as? NSColor, .systemYellow)
    }

    @MainActor
    func testInlineCodeDelimitersAreHiddenButStored() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: "Use `git status` now"),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let textView = try XCTUnwrap(item.testingTextView)
        let textStorage = try XCTUnwrap(textView.textStorage)

        XCTAssertEqual(textView.string, "Use `git status` now")
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor, .clear)
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 15, effectiveRange: nil) as? NSColor, .clear)
        XCTAssertEqual(textStorage.attribute(.blockInputHiddenDelimiter, at: 4, effectiveRange: nil) as? Bool, true)
        XCTAssertEqual(textStorage.attribute(.blockInputHiddenDelimiter, at: 15, effectiveRange: nil) as? Bool, true)
        XCTAssertNotEqual(textStorage.attribute(.foregroundColor, at: 5, effectiveRange: nil) as? NSColor, .clear)
        XCTAssertNil(textStorage.attribute(.backgroundColor, at: 4, effectiveRange: nil))
        XCTAssertNil(textStorage.attribute(.backgroundColor, at: 15, effectiveRange: nil))
    }

    @MainActor
    func testInlineCodeBackgroundOnlyCoversVisibleContent() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: "and `inline code.` now"),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)
        var effectiveRange = NSRange(location: NSNotFound, length: 0)

        XCTAssertNil(textStorage.attribute(.backgroundColor, at: 3, effectiveRange: nil))
        XCTAssertNil(textStorage.attribute(.backgroundColor, at: 4, effectiveRange: nil))
        XCTAssertEqual(
            textStorage.attribute(.backgroundColor, at: 5, effectiveRange: &effectiveRange) as? NSColor,
            BlockInputBlockItem.inlineCodeBackgroundColor
        )
        XCTAssertEqual(effectiveRange, NSRange(location: 5, length: 12))
        XCTAssertNil(textStorage.attribute(.backgroundColor, at: 17, effectiveRange: nil))
        XCTAssertNil(textStorage.attribute(.backgroundColor, at: 18, effectiveRange: nil))
    }

    @MainActor
    func testInlineCodeDelimitersDoNotReserveLayoutWidth() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: "Use `git status` now"),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let textView = try XCTUnwrap(item.testingTextView)
        let layoutManager = try preparedLayoutManager(for: textView)

        XCTAssertEqual(try glyphX(at: 5, layoutManager: layoutManager), try glyphX(at: 4, layoutManager: layoutManager), accuracy: 0.5)
        XCTAssertEqual(try glyphX(at: 16, layoutManager: layoutManager), try glyphX(at: 15, layoutManager: layoutManager), accuracy: 0.5)
        XCTAssertEqual(textView.string, "Use `git status` now")
    }

    @MainActor
    func testInlineCodeIgnoresUnmatchedBackticks() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: "Use `git status"),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)

        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor, .labelColor)
        XCTAssertNil(textStorage.attribute(.backgroundColor, at: 4, effectiveRange: nil))
        XCTAssertFalse(try XCTUnwrap(textStorage.attribute(.font, at: 5, effectiveRange: nil) as? NSFont)
            .fontDescriptor.symbolicTraits.contains(.monoSpace))
    }

    @MainActor
    func testInlineCodeStylesMultipleSpans() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: "`one` and `two`"),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)

        XCTAssertTrue(try XCTUnwrap(textStorage.attribute(.font, at: 1, effectiveRange: nil) as? NSFont)
            .fontDescriptor.symbolicTraits.contains(.monoSpace))
        XCTAssertTrue(try XCTUnwrap(textStorage.attribute(.font, at: 11, effectiveRange: nil) as? NSFont)
            .fontDescriptor.symbolicTraits.contains(.monoSpace))
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .clear)
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 14, effectiveRange: nil) as? NSColor, .clear)
        XCTAssertEqual(textStorage.attribute(.backgroundColor, at: 1, effectiveRange: nil) as? NSColor, BlockInputBlockItem.inlineCodeBackgroundColor)
        XCTAssertEqual(
            textStorage.attribute(.backgroundColor, at: 11, effectiveRange: nil) as? NSColor,
            BlockInputBlockItem.inlineCodeBackgroundColor
        )
    }

    @MainActor
    func testInlineCodeStylesEverySpanWhenAnOpenerClosesOnTheNextLine() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: "a `b\nc` d `e` f"),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)

        XCTAssertEqual(
            textStorage.attribute(.backgroundColor, at: 3, effectiveRange: nil) as? NSColor,
            BlockInputBlockItem.inlineCodeBackgroundColor
        )
        XCTAssertEqual(
            textStorage.attribute(.backgroundColor, at: 5, effectiveRange: nil) as? NSColor,
            BlockInputBlockItem.inlineCodeBackgroundColor
        )
        XCTAssertNil(textStorage.attribute(.backgroundColor, at: 8, effectiveRange: nil), "`d` sits between spans")
        XCTAssertEqual(
            textStorage.attribute(.backgroundColor, at: 11, effectiveRange: nil) as? NSColor,
            BlockInputBlockItem.inlineCodeBackgroundColor
        )
        XCTAssertEqual(textStorage.attribute(.blockInputHiddenDelimiter, at: 6, effectiveRange: nil) as? Bool, true)
        XCTAssertEqual(textStorage.attribute(.blockInputHiddenDelimiter, at: 12, effectiveRange: nil) as? Bool, true)
    }

    /// Sweeps container widths so that, without the no-wrap rule, some width splits the span
    /// across two line fragments. With it, the whole span moves to the next line instead.
    @MainActor
    func testInlineCodeSpanNeverWrapsMidSpan() throws {
        let text = "Run the release checklist and then `swift package resolve --force` afterwards"
        let contentRange = try XCTUnwrap(BlockInputCodeParsing.inlineCodeRanges(in: text).first?.contentRange)
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: text),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let textView = try XCTUnwrap(item.testingTextView)

        for width in stride(from: 240.0, through: 420.0, by: 4.0) {
            let layoutManager = try preparedLayoutManager(for: textView, width: width)
            let firstGlyph = layoutManager.glyphIndexForCharacter(at: contentRange.location)
            let lastGlyph = layoutManager.glyphIndexForCharacter(at: NSMaxRange(contentRange) - 1)
            let firstLine = layoutManager.lineFragmentRect(forGlyphAt: firstGlyph, effectiveRange: nil)
            let lastLine = layoutManager.lineFragmentRect(forGlyphAt: lastGlyph, effectiveRange: nil)

            XCTAssertEqual(firstLine.minY, lastLine.minY, accuracy: 0.5, "span split at width \(width)")
            XCTAssertLessThanOrEqual(layoutManager.usedRect(for: try XCTUnwrap(textView.textContainer)).width, width + 0.5)
        }
    }

    @MainActor
    func testInlineCodeSpanWiderThanTheLineStillWrapsInsideTheContainer() throws {
        let text = "`" + Array(repeating: "package-resolve-force", count: 6).joined(separator: " ") + "`"
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: text),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let textView = try XCTUnwrap(item.testingTextView)
        let width: CGFloat = 240
        let layoutManager = try preparedLayoutManager(for: textView, width: width)
        let textContainer = try XCTUnwrap(textView.textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let lineHeight = layoutManager.lineFragmentRect(forGlyphAt: 1, effectiveRange: nil).height

        XCTAssertLessThanOrEqual(usedRect.width, width + 0.5)
        XCTAssertGreaterThan(usedRect.height, lineHeight * 1.5, "an overlong span must still wrap")
    }

    @MainActor
    func testInlineCodeIsIgnoredInCodeBlocks() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "code", kind: .code(language: "swift"), text: "let value = `debug`"),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)

        XCTAssertNotEqual(textStorage.attribute(.foregroundColor, at: 12, effectiveRange: nil) as? NSColor, .clear)
        XCTAssertNil(textStorage.attribute(.backgroundColor, at: 12, effectiveRange: nil))
        XCTAssertTrue(try XCTUnwrap(textStorage.attribute(.font, at: 13, effectiveRange: nil) as? NSFont)
            .fontDescriptor.symbolicTraits.contains(.monoSpace))
    }

    @MainActor
    func testInlineCodeAttributesAreClearedWhenItemIsReused() throws {
        let view = BlockInputView()
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: "Use `git status` now"),
            allowsReordering: true,
            delegate: view
        )

        item.configure(
            block: BlockInputBlock(id: "plain", kind: .paragraph, text: "Use git status now"),
            allowsReordering: true,
            delegate: view
        )

        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor, .labelColor)
        XCTAssertNil(textStorage.attribute(.backgroundColor, at: 4, effectiveRange: nil))
        XCTAssertNil(textStorage.attribute(.blockInputHiddenDelimiter, at: 4, effectiveRange: nil))
        XCTAssertFalse(try XCTUnwrap(textStorage.attribute(.font, at: 4, effectiveRange: nil) as? NSFont)
            .fontDescriptor.symbolicTraits.contains(.monoSpace))
    }

    @MainActor
    func testInlineCodeTypingAttributesResetOutsideInlineCode() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: "Use `git status` now"),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let textView = try XCTUnwrap(item.testingTextView)

        item.setSelectedRange(NSRange(location: 7, length: 0))
        XCTAssertTrue(try XCTUnwrap(textView.typingAttributes[.font] as? NSFont)
            .fontDescriptor.symbolicTraits.contains(.monoSpace))
        XCTAssertEqual(textView.typingAttributes[.backgroundColor] as? NSColor, BlockInputBlockItem.inlineCodeBackgroundColor)

        item.setSelectedRange(NSRange(location: 18, length: 0))
        XCTAssertFalse(try XCTUnwrap(textView.typingAttributes[.font] as? NSFont)
            .fontDescriptor.symbolicTraits.contains(.monoSpace))
        XCTAssertNil(textView.typingAttributes[.foregroundColor] as? NSColor)
        XCTAssertNil(textView.typingAttributes[.backgroundColor] as? NSColor)
    }
}

@MainActor
private func preparedLayoutManager(for textView: NSTextView, width: CGFloat = 320) throws -> NSLayoutManager {
    textView.frame = NSRect(x: 0, y: 0, width: width, height: 60)
    let textContainer = try XCTUnwrap(textView.textContainer)
    textContainer.widthTracksTextView = false
    textContainer.lineFragmentPadding = 0
    textContainer.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
    let layoutManager = try XCTUnwrap(textView.layoutManager)
    layoutManager.invalidateLayout(
        forCharacterRange: NSRange(location: 0, length: (textView.string as NSString).length),
        actualCharacterRange: nil
    )
    layoutManager.ensureLayout(for: textContainer)
    return layoutManager
}

private func glyphX(at utf16Offset: Int, layoutManager: NSLayoutManager) throws -> CGFloat {
    let glyphIndex = layoutManager.glyphIndexForCharacter(at: utf16Offset)
    return layoutManager.location(forGlyphAt: glyphIndex).x
}
