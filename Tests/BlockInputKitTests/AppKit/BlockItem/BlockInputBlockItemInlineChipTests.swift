import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputBlockItemInlineChipTests: XCTestCase {
    func testInlineMarkdownRendersFileLinksAsChipsWhenSelectionIsOutsideSource() throws {
        let text = "Open [../README.md](<file:///tmp/README.md>) today"
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: text),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)
        let contentOffset = contentLocation("../README.md", in: text)

        XCTAssertEqual((textStorage.attribute(.link, at: contentOffset, effectiveRange: nil) as? URL)?.absoluteString, "file:///tmp/README.md")
        XCTAssertNil(textStorage.attribute(.underlineStyle, at: contentOffset, effectiveRange: nil))
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: contentOffset, effectiveRange: nil) as? NSColor, .labelColor)
        XCTAssertTrue(try font(at: contentOffset, in: textStorage).isFixedPitch)
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 5, effectiveRange: nil) as? NSColor, .clear)
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 19, effectiveRange: nil) as? NSColor, .clear)
    }

    func testFileLinkChipAddsSpacingToAdjacentWhitespaceOnly() throws {
        let text = "Open [../README.md](<file:///tmp/README.md>) today"
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: text),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)
        let openingBracketOffset = (text as NSString).range(of: "[").location
        let leadingSpaceOffset = openingBracketOffset - 1
        let destinationOffset = (text as NSString).range(of: "file:///tmp").location
        let closingParenthesisOffset = (text as NSString).range(of: ") today").location
        let trailingSpaceOffset = closingParenthesisOffset + 1

        XCTAssertEqual(textStorage.attribute(.kern, at: leadingSpaceOffset, effectiveRange: nil) as? CGFloat, 5)
        XCTAssertEqual(textStorage.attribute(.kern, at: trailingSpaceOffset, effectiveRange: nil) as? CGFloat, 5)
        XCTAssertNil(textStorage.attribute(.kern, at: openingBracketOffset, effectiveRange: nil))
        XCTAssertNil(textStorage.attribute(.kern, at: destinationOffset, effectiveRange: nil))
        XCTAssertNil(textStorage.attribute(.kern, at: closingParenthesisOffset, effectiveRange: nil))
    }

    func testFileLinkChipBackgroundHeightStaysStableWhenFollowingTextAppears() throws {
        let link = "[.agents/skills/watermark-portfolio-images/gingerink.ttf](<file:///tmp/gingerink.ttf>)"
        let chipOnlyRect = try onlyChipBackgroundRect(for: link)
        let trailingSpaceRect = try onlyChipBackgroundRect(for: "\(link) ")
        let trailingTextRect = try onlyChipBackgroundRect(for: "\(link) x")

        XCTAssertEqual(trailingSpaceRect.height, chipOnlyRect.height, accuracy: 0.001)
        XCTAssertEqual(trailingTextRect.height, chipOnlyRect.height, accuracy: 0.001)
        XCTAssertEqual(trailingSpaceRect.minY, chipOnlyRect.minY, accuracy: 0.001)
        XCTAssertEqual(trailingTextRect.minY, chipOnlyRect.minY, accuracy: 0.001)
    }

    func testFileLinkChipTextPositionStaysStableWhenFollowingTextAppears() throws {
        let link = "[.agents/skills/watermark-portfolio-images/gingerink.ttf](<file:///tmp/gingerink.ttf>)"
        let chipOnlyRect = try onlyChipRenderedTextBounds(for: link)
        let trailingSpaceRect = try onlyChipRenderedTextBounds(for: "\(link) ")
        let trailingTextRect = try onlyChipRenderedTextBounds(for: "\(link) x")

        XCTAssertEqual(trailingSpaceRect.minY, chipOnlyRect.minY, accuracy: 0.001)
        XCTAssertEqual(trailingTextRect.minY, chipOnlyRect.minY, accuracy: 0.001)
    }

    func testFileLinkChipTextPositionStaysStableWithCustomBaseFontWhenFollowingTextAppears() throws {
        let link = "[.agents/skills/watermark-portfolio-images/gingerink.ttf](<file:///tmp/gingerink.ttf>)"
        let style = BlockInputStyle(
            baseText: BlockInputTextStyle(font: .systemFont(ofSize: 18, weight: .medium)),
            fileChip: BlockInputInlineChipStyle(fillColor: nil, strokeColor: nil, foregroundColor: .black)
        )
        let chipOnlyRect = try onlyChipRenderedTextBounds(for: link, style: style)
        let trailingSpaceRect = try onlyChipRenderedTextBounds(for: "\(link) ", style: style)
        let trailingTextRect = try onlyChipRenderedTextBounds(for: "\(link) x", style: style)

        XCTAssertEqual(trailingSpaceRect.minY, chipOnlyRect.minY, accuracy: 0.001)
        XCTAssertEqual(trailingTextRect.minY, chipOnlyRect.minY, accuracy: 0.001)
    }

    func testSlashCommandLinkRendersAsReusableChip() throws {
        let text = "Run [/table](host-app://commands/table) today"
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: text),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)
        let contentOffset = contentLocation("/table", in: text)
        let finalContentOffset = NSMaxRange((text as NSString).range(of: "/table")) - 1
        let openingBracketOffset = (text as NSString).range(of: "[").location
        let trailingSpaceOffset = (text as NSString).range(of: ") today").location + 1

        XCTAssertEqual(
            (textStorage.attribute(.link, at: contentOffset, effectiveRange: nil) as? URL)?.absoluteString,
            "host-app://commands/table"
        )
        XCTAssertNil(textStorage.attribute(.underlineStyle, at: contentOffset, effectiveRange: nil))
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: contentOffset, effectiveRange: nil) as? NSColor, .labelColor)
        XCTAssertTrue(try font(at: contentOffset, in: textStorage).isFixedPitch)
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: openingBracketOffset, effectiveRange: nil) as? NSColor, .clear)
        XCTAssertNil(textStorage.attribute(.kern, at: finalContentOffset, effectiveRange: nil))
        XCTAssertNil(textStorage.attribute(.kern, at: trailingSpaceOffset, effectiveRange: nil))
    }

    func testRawSlashCommandRendersAsVisualOnlyChipWhenEnabled() throws {
        let text = "Run /table today"
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: text),
            allowsReordering: true,
            rawSlashCommandChips: true,
            slashCommandAvailability: .anywhere,
            delegate: BlockInputView()
        )
        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)
        let contentOffset = contentLocation("/table", in: text)

        XCTAssertNil(textStorage.attribute(.link, at: contentOffset, effectiveRange: nil))
        XCTAssertNil(textStorage.attribute(.underlineStyle, at: contentOffset, effectiveRange: nil))
        XCTAssertNil(textStorage.attribute(.blockInputHiddenDelimiter, at: contentOffset, effectiveRange: nil))
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: contentOffset, effectiveRange: nil) as? NSColor, .labelColor)
        XCTAssertTrue(try font(at: contentOffset, in: textStorage).isFixedPitch)
    }

    func testUnderlineClosingTagDoesNotRenderAsRawSlashChip() throws {
        let text = "Inline <u>underline</u>, then plain"
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "paragraph", kind: .paragraph, text: text)
            ]),
            rawSlashCommandChips: true,
            slashCommandAvailability: .anywhere
        ))
        resizeMountedBlockInputView(mounted, to: NSSize(width: 620, height: 140))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let textStorage = try XCTUnwrap(textView.textStorage)
        textView.layoutManager?.ensureLayout(for: try XCTUnwrap(textView.textContainer))
        let closingSlashOffset = (text as NSString).range(of: "</u>").location + 1

        XCTAssertTrue(textView.inlineChipBackgroundRectsForTesting().isEmpty)
        XCTAssertNil(textStorage.attribute(.blockInputInlineChip, at: closingSlashOffset, effectiveRange: nil))
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: closingSlashOffset, effectiveRange: nil) as? NSColor, .clear)
        XCTAssertEqual(
            textStorage.attribute(.underlineStyle, at: contentLocation("underline", in: text), effectiveRange: nil) as? Int,
            NSUnderlineStyle.single.rawValue
        )
    }

    func testRawSlashCommandDoesNotRenderAsChipByDefault() throws {
        let text = "Run /table today"
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: text),
            allowsReordering: true,
            rawSlashCommandChips: false,
            slashCommandAvailability: .anywhere,
            delegate: BlockInputView()
        )
        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)
        let contentOffset = contentLocation("/table", in: text)

        XCTAssertFalse(try font(at: contentOffset, in: textStorage).isFixedPitch)
    }

    func testRawAndLinkBackedSlashCommandChipsCoexist() throws {
        let text = "/review [/table](host-app://commands/table)"
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: text),
            allowsReordering: true,
            rawSlashCommandChips: true,
            slashCommandAvailability: .documentStart,
            isDocumentStartBlock: true,
            delegate: BlockInputView()
        )
        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)
        let rawOffset = contentLocation("/review", in: text)
        let linkOffset = contentLocation("/table", in: text)

        XCTAssertNil(textStorage.attribute(.link, at: rawOffset, effectiveRange: nil))
        XCTAssertTrue(try font(at: rawOffset, in: textStorage).isFixedPitch)
        XCTAssertEqual(
            (textStorage.attribute(.link, at: linkOffset, effectiveRange: nil) as? URL)?.absoluteString,
            "host-app://commands/table"
        )
        XCTAssertTrue(try font(at: linkOffset, in: textStorage).isFixedPitch)
    }

    func testRawSlashCommandChipPreservesAccessibilityText() throws {
        let text = "/table"
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: text),
            allowsReordering: true,
            rawSlashCommandChips: true,
            delegate: BlockInputView()
        )
        let textView = try XCTUnwrap(item.testingTextView)

        XCTAssertEqual(textView.accessibilityValue(), text)
        XCTAssertEqual(textView.string, text)
    }

    func testRawSlashCommandDoesNotRenderAsChipInsideTables() throws {
        let table = BlockInputBlock(id: "table", kind: .table, text: """
        | Command |
        | --- |
        | /table |
        """)
        let item = BlockInputBlockItem.configuredForTesting(
            block: table,
            allowsReordering: true,
            rawSlashCommandChips: true,
            slashCommandAvailability: .anywhere,
            delegate: BlockInputView()
        )
        item.view.frame = NSRect(x: 0, y: 0, width: 480, height: BlockInputBlockItem.height(for: table, textWidth: 420))
        item.view.layoutSubtreeIfNeeded()
        let cell = try XCTUnwrap(item.testingTableCellTextViews.first { $0.string == "/table" })
        let textStorage = try XCTUnwrap(cell.textStorage)

        XCTAssertFalse(try font(at: 0, in: textStorage).isFixedPitch)
    }

    func testRawSlashCommandDoesNotRenderAsChipInUnsupportedBlockKinds() throws {
        let cases: [(BlockInputBlockKind, String)] = [
            (.code(language: nil), "/table"),
            (.frontMatter, "command: /table"),
            (.rawMarkdown, "/table")
        ]
        for (kind, text) in cases {
            let item = BlockInputBlockItem.configuredForTesting(
                block: BlockInputBlock(id: BlockInputBlockID(rawValue: String(describing: kind)), kind: kind, text: text),
                allowsReordering: true,
                rawSlashCommandChips: true,
                slashCommandAvailability: .anywhere,
                delegate: BlockInputView()
            )
            let textView = try XCTUnwrap(item.testingTextView)
            let textStorage = try XCTUnwrap(textView.textStorage)
            let offset = contentLocation("/table", in: textView.string)

            XCTAssertNil(textStorage.attribute(.blockInputInlineChip, at: offset, effectiveRange: nil))
        }
    }

    func testFileLinkChipStaysVisibleWhenCaretIsInsideSource() throws {
        let text = "[README.md](file:///tmp/README.md) trailing"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "paragraph", kind: .paragraph, text: text)
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let contentOffset = contentLocation("README.md", in: text)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: contentOffset, length: 0))
        item.updateSelectionDependentAttributesForCurrentSelection()
        let textStorage = try XCTUnwrap(textView.textStorage)

        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: contentOffset, effectiveRange: nil) as? NSColor, .labelColor)
        XCTAssertNil(textStorage.attribute(.underlineStyle, at: contentOffset, effectiveRange: nil))
        XCTAssertTrue(try font(at: contentOffset, in: textStorage).isFixedPitch)
    }

    func testFileLinkChipStaysVisibleWhenSelectionOverlapsSource() throws {
        let text = "[README.md](file:///tmp/README.md) trailing"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "paragraph", kind: .paragraph, text: text)
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let contentOffset = contentLocation("README.md", in: text)

        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: contentOffset, length: 4))
        item.updateSelectionDependentAttributesForCurrentSelection()
        let textStorage = try XCTUnwrap(textView.textStorage)

        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: contentOffset, effectiveRange: nil) as? NSColor, .labelColor)
        XCTAssertNil(textStorage.attribute(.underlineStyle, at: contentOffset, effectiveRange: nil))
        XCTAssertTrue(try font(at: contentOffset, in: textStorage).isFixedPitch)
    }

    func testFileLinkChipStaysVisibleAtSourceBoundaries() throws {
        let text = "[README.md](file:///tmp/README.md) trailing"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "paragraph", kind: .paragraph, text: text)
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let contentOffset = contentLocation("README.md", in: text)
        let fullRange = (text as NSString).range(of: "[README.md](file:///tmp/README.md)")
        let textStorage = try XCTUnwrap(textView.textStorage)

        mounted.window.makeFirstResponder(textView)
        for caretOffset in [fullRange.location, NSMaxRange(fullRange)] {
            textView.setSelectedRange(NSRange(location: caretOffset, length: 0))
            item.updateSelectionDependentAttributesForCurrentSelection()

            XCTAssertEqual(textStorage.attribute(.foregroundColor, at: contentOffset, effectiveRange: nil) as? NSColor, .labelColor)
            XCTAssertNil(textStorage.attribute(.underlineStyle, at: contentOffset, effectiveRange: nil))
            XCTAssertTrue(try font(at: contentOffset, in: textStorage).isFixedPitch)
        }
    }

    func testRegularLinkKeepsNormalLinkStyle() throws {
        let text = "[README.md](https://example.com/README.md) trailing"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "paragraph", kind: .paragraph, text: text)
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let contentOffset = contentLocation("README.md", in: text)

        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: contentOffset, length: 0))
        item.updateSelectionDependentAttributesForCurrentSelection()
        let textStorage = try XCTUnwrap(textView.textStorage)

        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: contentOffset, effectiveRange: nil) as? NSColor, .linkColor)
        XCTAssertEqual(textStorage.attribute(.underlineStyle, at: contentOffset, effectiveRange: nil) as? Int, NSUnderlineStyle.single.rawValue)
        XCTAssertFalse(try font(at: contentOffset, in: textStorage).isFixedPitch)
    }

    func testFileSlashAndRawSlashChipsUseConfiguredForegroundStyles() throws {
        let text = "[file](file:///tmp/demo.md) [/table](host-app://commands/table) /review"
        let style = BlockInputStyle(
            fileChip: BlockInputInlineChipStyle(foregroundColor: .systemRed),
            slashCommandChip: BlockInputInlineChipStyle(foregroundColor: .systemGreen),
            rawSlashCommandChip: BlockInputInlineChipStyle(foregroundColor: .systemBlue)
        )
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: text),
            allowsReordering: true,
            style: style,
            rawSlashCommandChips: true,
            slashCommandAvailability: .anywhere,
            delegate: BlockInputView()
        )
        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)

        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: contentLocation("file", in: text), effectiveRange: nil) as? NSColor, .systemRed)
        XCTAssertEqual(
            textStorage.attribute(.foregroundColor, at: contentLocation("/table", in: text), effectiveRange: nil) as? NSColor,
            .systemGreen
        )
        XCTAssertEqual(
            textStorage.attribute(.foregroundColor, at: contentLocation("/review", in: text), effectiveRange: nil) as? NSColor,
            .systemBlue
        )
    }

    func testReconfiguringItemReplacesStaleChipForegroundStyle() throws {
        let text = "[file](file:///tmp/demo.md)"
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: text),
            allowsReordering: true,
            style: BlockInputStyle(fileChip: BlockInputInlineChipStyle(foregroundColor: .systemRed)),
            delegate: BlockInputView()
        )

        item.configure(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: text),
            allowsReordering: true,
            style: BlockInputStyle(fileChip: BlockInputInlineChipStyle(foregroundColor: .systemBlue)),
            delegate: BlockInputView()
        )

        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: contentLocation("file", in: text), effectiveRange: nil) as? NSColor, .systemBlue)
    }

    func testReconfiguringItemClearsStaleChipBaselineOffset() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: "[file](file:///tmp/demo.md)"),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        var textStorage = try XCTUnwrap(item.testingTextView?.textStorage)
        XCTAssertNotNil(textStorage.attribute(.baselineOffset, at: contentLocation("file", in: textStorage.string), effectiveRange: nil))

        item.configure(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: "plain file"),
            allowsReordering: true,
            delegate: BlockInputView()
        )

        textStorage = try XCTUnwrap(item.testingTextView?.textStorage)
        XCTAssertNil(textStorage.attribute(.baselineOffset, at: 0, effectiveRange: nil))
        XCTAssertNil(textStorage.attribute(.blockInputInlineChip, at: 0, effectiveRange: nil))
    }

    private func font(at location: Int, in textStorage: NSTextStorage) throws -> NSFont {
        try XCTUnwrap(textStorage.attribute(.font, at: location, effectiveRange: nil) as? NSFont)
    }

    private func contentLocation(_ content: String, in text: String) -> Int {
        (text as NSString).range(of: content).location
    }

    private func onlyChipBackgroundRect(for text: String) throws -> NSRect {
        let mounted = makeMountedBlockInputView(
            blocks: [BlockInputBlock(id: "paragraph", kind: .paragraph, text: text)]
        )
        resizeMountedBlockInputView(mounted, to: NSSize(width: 1_400, height: 240))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        textView.layoutManager?.ensureLayout(for: try XCTUnwrap(textView.textContainer))
        let rects = textView.inlineChipBackgroundRectsForTesting()

        return try XCTUnwrap(rects.only)
    }

    private func onlyChipRenderedTextBounds(
        for text: String,
        style: BlockInputStyle = BlockInputStyle(fileChip: BlockInputInlineChipStyle(fillColor: nil, strokeColor: nil, foregroundColor: .black))
    ) throws -> NSRect {
        let chipLabel = ".agents/skills/watermark-portfolio-images/gingerink.ttf"
        let link = "[\(chipLabel)](<file:///tmp/gingerink.ttf>)"
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "paragraph", kind: .paragraph, text: text)]),
            style: style
        ))
        resizeMountedBlockInputView(mounted, to: NSSize(width: 1_400, height: 240))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        if text.utf16.count > link.utf16.count {
            textView.textStorage?.addAttribute(
                .foregroundColor,
                value: NSColor.clear,
                range: NSRange(location: link.utf16.count, length: text.utf16.count - link.utf16.count)
            )
        }
        textView.layoutManager?.ensureLayout(for: try XCTUnwrap(textView.textContainer))
        return try renderedForegroundBounds(in: textView)
    }

}

@MainActor
private func renderedForegroundBounds(in textView: NSTextView) throws -> NSRect {
    let scale: CGFloat = 2
    let bounds = textView.bounds
    let pixelWidth = max(1, Int(ceil(bounds.width * scale)))
    let pixelHeight = max(1, Int(ceil(bounds.height * scale)))
    let bitmap = try XCTUnwrap(NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelWidth,
        pixelsHigh: pixelHeight,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ))
    bitmap.size = bounds.size
    let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSColor.white.setFill()
    bounds.fill()
    textView.displayIgnoringOpacity(bounds, in: context)
    NSGraphicsContext.restoreGraphicsState()

    var minX = pixelWidth
    var minY = pixelHeight
    var maxX = -1
    var maxY = -1
    for pixelY in 0..<pixelHeight {
        for pixelX in 0..<pixelWidth {
            guard let color = bitmap.colorAt(x: pixelX, y: pixelY)?.usingColorSpace(.deviceRGB),
                  color.redComponent < 0.95 || color.greenComponent < 0.95 || color.blueComponent < 0.95 else {
                continue
            }
            minX = min(minX, pixelX)
            minY = min(minY, pixelY)
            maxX = max(maxX, pixelX)
            maxY = max(maxY, pixelY)
        }
    }
    guard maxX >= minX, maxY >= minY else {
        return try XCTUnwrap(Optional<NSRect>.none)
    }
    return NSRect(
        x: CGFloat(minX) / scale,
        y: CGFloat(minY) / scale,
        width: CGFloat(maxX - minX + 1) / scale,
        height: CGFloat(maxY - minY + 1) / scale
    )
}

private extension Array {
    var only: Element? {
        count == 1 ? first : nil
    }
}
