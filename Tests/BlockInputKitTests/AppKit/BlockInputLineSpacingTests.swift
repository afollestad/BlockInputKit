import AppKit
import XCTest
@testable import BlockInputKit

/// Covers `BlockInputTextStyle.lineSpacing`: the height it adds, the kinds it skips, the
/// measurement paths that must mirror it, and the chrome that must not sink with it.
@MainActor
final class BlockInputLineSpacingTests: XCTestCase {
    private let lineSpacing: CGFloat = 3

    func testLineSpacingLeavesVisibleLineSizingUnchanged() {
        let plainView = configuredView(text: "Short", defaultLines: 3, style: .default)
        let spacedView = configuredView(text: "Short", defaultLines: 3, style: spacedStyle)

        // The visible-line minimum is built from a one-line reference row, and TextKit spaces
        // only the gaps between lines — so opting into spacing must not move the resting height.
        XCTAssertEqual(
            spacedView.preferredHeight(forWidth: 360),
            plainView.preferredHeight(forWidth: 360),
            accuracy: 0.5
        )
    }

    func testLineSpacingGrowsMultiLineBlocksByTheGapsBetweenLines() {
        let singleLine = BlockInputBlock(id: "single", text: "one")
        let threeLines = BlockInputBlock(id: "three", text: "one\ntwo\nthree")

        XCTAssertEqual(
            BlockInputBlockItem.height(for: singleLine, textWidth: 320, style: spacedStyle),
            BlockInputBlockItem.height(for: singleLine, textWidth: 320, style: .default),
            accuracy: 0.001
        )

        let plainHeight = BlockInputBlockItem.height(for: threeLines, textWidth: 320, style: .default)
        let spacedHeight = BlockInputBlockItem.height(for: threeLines, textWidth: 320, style: spacedStyle)
        XCTAssertGreaterThan(spacedHeight, plainHeight)
        // Two gaps for three lines, and TextKit spends slightly less than the raw value per gap.
        XCTAssertLessThanOrEqual(spacedHeight, plainHeight + (lineSpacing * 2) + 1)
    }

    func testLineSpacingKeepsRenderedLinesFittingTheVisibleLineCount() {
        let twoLineView = configuredView(text: "One\nTwo", defaultLines: 3, style: spacedStyle)
        let threeLineView = configuredView(text: "One\nTwo\nThree", defaultLines: 3, style: spacedStyle)
        let fourLineView = configuredView(text: "One\nTwo\nThree\nFour", defaultLines: 3, style: spacedStyle)

        XCTAssertEqual(
            threeLineView.preferredHeight(forWidth: 360),
            twoLineView.preferredHeight(forWidth: 360),
            accuracy: 0.5
        )
        XCTAssertGreaterThan(
            fourLineView.preferredHeight(forWidth: 360),
            threeLineView.preferredHeight(forWidth: 360)
        )
    }

    func testMeasuredHeightStillFitsRenderedTextWithLineSpacing() throws {
        let wrappingText = String(repeating: "wrapping paragraph text ", count: 6)
        for text in [wrappingText, "One line", ""] {
            let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
                document: BlockInputDocument(blocks: [BlockInputBlock(id: "first", text: text)]),
                blockVerticalInsetMultiplier: 0.7,
                style: spacedStyle
            ), size: NSSize(width: 360, height: 400))
            let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
            let textView = try XCTUnwrap(item.testingTextView)
            let textScrollView: NSScrollView = try XCTUnwrap(textView.enclosingScrollView)
            let textClipHeight = textScrollView.contentView.bounds.height

            // The row is measured offscreen; if that measurement under-predicted the spaced
            // layout, the text view would outgrow its clip view and scroll inside the row.
            XCTAssertLessThanOrEqual(textView.frame.height, textClipHeight + 0.5, "text \"\(text)\"")
        }
    }

    func testLineSpacingLeavesCodeAndTableHeightsUnchanged() {
        let code = BlockInputBlock(id: "code", kind: .code(language: nil), text: "let a = 1\nlet b = 2")
        let table = BlockInputBlock(id: "table", kind: .table, text: "| a | b |\n| --- | --- |\n| 1 | 2 |")

        for block in [code, table] {
            XCTAssertEqual(
                BlockInputBlockItem.height(for: block, textWidth: 320, style: spacedStyle),
                BlockInputBlockItem.height(for: block, textWidth: 320, style: .default),
                accuracy: 0.001
            )
        }
    }

    func testLineSpacingAppliesToWrappingKindsOnly() {
        XCTAssertEqual(BlockInputBlockItem.lineSpacing(for: .paragraph, style: spacedStyle), lineSpacing)
        XCTAssertEqual(BlockInputBlockItem.lineSpacing(for: .heading(level: 2), style: spacedStyle), lineSpacing)
        XCTAssertEqual(BlockInputBlockItem.lineSpacing(for: .quote, style: spacedStyle), lineSpacing)
        XCTAssertEqual(BlockInputBlockItem.lineSpacing(for: .code(language: nil), style: spacedStyle), 0)
        XCTAssertEqual(BlockInputBlockItem.lineSpacing(for: .table, style: spacedStyle), 0)
        XCTAssertEqual(BlockInputBlockItem.lineSpacing(for: .paragraph, style: .default), 0)
    }

    func testEmptyParagraphCarriesLineSpacingInDefaultParagraphStyle() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: ""),
            allowsReordering: true,
            style: spacedStyle,
            delegate: BlockInputView()
        )
        let textView = try XCTUnwrap(item.testingTextView)

        // The extra line fragment lays out with `defaultParagraphStyle`, so an empty block only
        // renders as tall as it measures when the spacing lives there too.
        XCTAssertEqual(textView.defaultParagraphStyle?.lineSpacing, lineSpacing)
        XCTAssertEqual((textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.lineSpacing, lineSpacing)
    }

    func testCodeBlockKeepsNoParagraphStyleWithLineSpacingConfigured() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "code", kind: .code(language: nil), text: "let a = 1"),
            allowsReordering: true,
            style: spacedStyle,
            delegate: BlockInputView()
        )
        let textView = try XCTUnwrap(item.testingTextView)

        XCTAssertNil(textView.defaultParagraphStyle)
        XCTAssertNil(textView.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil))
    }

    func testInlineChipFillDoesNotSinkWithLineSpacing() throws {
        let plainRect = try firstChipBackgroundRect(style: .default, text: chipText)
        let spacedRect = try firstChipBackgroundRect(style: spacedStyle, text: chipText)

        // Spacing is added below the glyphs, so a chip on the first line must not move at all.
        XCTAssertEqual(spacedRect.midY, plainRect.midY, accuracy: 0.5)
        XCTAssertEqual(spacedRect.height, plainRect.height, accuracy: 0.5)
    }

    func testInlineChipFillStaysCenteredOnASpacedWrappedLine() throws {
        // The chip now sits on a line that *has* a line after it, which is the only case where the
        // used rect carries trailing spacing.
        let wrappedText = "\(chipText) \(String(repeating: "trailing words ", count: 12))"
        let plainRect = try firstChipBackgroundRect(style: .default, text: wrappedText)
        let spacedRect = try firstChipBackgroundRect(style: spacedStyle, text: wrappedText)

        XCTAssertEqual(spacedRect.midY, plainRect.midY, accuracy: 0.5)
        XCTAssertEqual(spacedRect.height, plainRect.height, accuracy: 0.5)
    }

    func testInlineChipStartingASpacedLineKeepsItsPlainGeometry() throws {
        // The chip's own font is smaller than the base font, so a line it starts is the case where
        // an unspaced line height read from the first character alone comes out short.
        let wrappedText = "Intro line\n[../README.md](<file:///tmp/README.md>) "
            + String(repeating: "trailing words ", count: 8)
        let plain = try firstChipGeometry(style: .default, text: wrappedText)
        let spaced = try firstChipGeometry(style: spacedStyle, text: wrappedText)

        // Guards the fixture: the assertions below only exercise that case while the chip really
        // does begin its own line. The chip is on the second line, which spacing legitimately
        // pushes down, so the comparison is of its offset within its own line fragment. The
        // tolerance is tight because reading the line height from the chip's font alone is off by
        // only half a point.
        XCTAssertLessThan(spaced.rect.minX, 12)
        XCTAssertEqual(spaced.offsetFromLineTop, plain.offsetFromLineTop, accuracy: 0.1)
        XCTAssertEqual(spaced.rect.height, plain.rect.height, accuracy: 0.1)
    }

    func testInlineChipHitTestingFollowsTheSpacedFill() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "paragraph", text: chipText)]),
            style: spacedStyle
        ), size: NSSize(width: 360, height: 400))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let chipRect = try XCTUnwrap(textView.inlineChipBackgroundRectsForTesting().first)

        // Clicks are matched against the same rects the fill is drawn from, so a spacing-driven
        // shift in one without the other would leave the chip visible but unclickable.
        let chipCenter = textView.convert(NSPoint(x: chipRect.midX, y: chipRect.midY), to: nil)
        XCTAssertNotNil(textView.inlineChipRange(atWindowLocation: chipCenter))
    }

    func testListMarkerDoesNotSinkWithLineSpacing() throws {
        let plainFrame = try onlyMarkerLineFrame(style: .default)
        let spacedFrame = try onlyMarkerLineFrame(style: spacedStyle)

        XCTAssertEqual(spacedFrame.midY, plainFrame.midY, accuracy: 0.5)
        XCTAssertEqual(spacedFrame.height, plainFrame.height, accuracy: 0.5)
    }

    func testEmptyListMarkerDoesNotSinkWithLineSpacing() throws {
        // An empty row aligns its marker on the extra line fragment instead of a glyph line, and
        // that fragment lays out with `defaultParagraphStyle` — which now carries the spacing.
        let plainFrame = try onlyMarkerLineFrame(style: .default, text: "")
        let spacedFrame = try onlyMarkerLineFrame(style: spacedStyle, text: "")

        XCTAssertEqual(spacedFrame.midY, plainFrame.midY, accuracy: 0.5)
        XCTAssertEqual(spacedFrame.height, plainFrame.height, accuracy: 0.5)
    }

    private var spacedStyle: BlockInputStyle {
        BlockInputStyle(baseText: BlockInputTextStyle(lineSpacing: lineSpacing))
    }

    private func configuredView(text: String, defaultLines: Int, style: BlockInputStyle) -> BlockInputView {
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 360, height: 200))
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "first", text: text)]),
            blockVerticalInsetMultiplier: 0.7,
            style: style,
            heightSizing: BlockInputEditorHeightSizing(defaultVisibleLineCount: defaultLines, maximumVisibleLineCount: 9)
        ))
        view.layoutSubtreeIfNeeded()
        return view
    }

    private var chipText: String {
        "Open [../README.md](<file:///tmp/README.md>) today"
    }

    private func firstChipBackgroundRect(style: BlockInputStyle, text: String) throws -> NSRect {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "paragraph", kind: .paragraph, text: text)]),
            style: style
        ), size: NSSize(width: 360, height: 400))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        textView.layoutManager?.ensureLayout(for: try XCTUnwrap(textView.textContainer))

        return try XCTUnwrap(textView.inlineChipBackgroundRectsForTesting().first)
    }

    /// The first chip's fill plus how far its center sits below the top of the line fragment it
    /// renders on, which is the part of its geometry that spacing must leave alone even on a line
    /// the spacing above has already pushed down.
    private func firstChipGeometry(
        style: BlockInputStyle,
        text: String
    ) throws -> (rect: NSRect, offsetFromLineTop: CGFloat) {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "paragraph", kind: .paragraph, text: text)]),
            style: style
        ), size: NSSize(width: 360, height: 400))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        layoutManager.ensureLayout(for: textContainer)

        let rect = try XCTUnwrap(textView.inlineChipBackgroundRectsForTesting().first)
        let origin = textView.textContainerOrigin
        let containerPoint = NSPoint(x: rect.midX - origin.x, y: rect.midY - origin.y)
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let lineTop = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil).minY

        return (rect, rect.midY - origin.y - lineTop)
    }

    private func onlyMarkerLineFrame(style: BlockInputStyle, text: String = "Only line") throws -> NSRect {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "item", kind: .bulletedListItem, text: text)
            ]),
            style: style
        ), size: NSSize(width: 720, height: 240))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        item.view.layoutSubtreeIfNeeded()

        return try XCTUnwrap(item.kindLabel.markerLineFrame(at: 0))
    }
}
