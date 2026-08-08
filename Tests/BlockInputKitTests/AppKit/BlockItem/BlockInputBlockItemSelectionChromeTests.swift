import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputBlockItemSelectionChromeTests: XCTestCase {
    func testListSelectionChromeUsesContentWidth() throws {
        let paragraphItem = selectedItemForWidthTesting(
            block: BlockInputBlock(id: "paragraph", text: "Try mention query")
        )
        let orderedItem = selectedItemForWidthTesting(
            block: BlockInputBlock(id: "ordered", kind: .numberedListItem(start: 1), text: "Toggle reordering")
        )
        let checklistItem = selectedItemForWidthTesting(
            block: BlockInputBlock(id: "check", kind: .checklistItem(isChecked: false), text: "Checklist data")
        )

        XCTAssertEqual(orderedItem.testingSelectionBackgroundView.frame.minX, paragraphItem.testingSelectionBackgroundView.frame.minX)
        XCTAssertEqual(checklistItem.testingSelectionBackgroundView.frame.minX, paragraphItem.testingSelectionBackgroundView.frame.minX)
        XCTAssertLessThan(orderedItem.testingSelectionBackgroundView.frame.maxX, orderedItem.view.bounds.width / 2)
        XCTAssertLessThan(checklistItem.testingSelectionBackgroundView.frame.maxX, checklistItem.view.bounds.width / 2)
    }

    func testWholeSelectionChromeStartsAtContentLeadingEdge() throws {
        let item = selectedItemForWidthTesting(
            block: BlockInputBlock(id: "paragraph", text: "BlockInputKit demo")
        )
        let scrollView = try XCTUnwrap(item.testingTextScrollView)
        let textView = try XCTUnwrap(item.testingTextView)
        let expectedLeading = floor(scrollView.frame.minX + textView.textContainerInset.width)

        XCTAssertEqual(item.testingSelectionBackgroundView.frame.minX, expectedLeading, accuracy: 1)
    }

    func testHorizontalRuleSelectionChromeUsesTextColumnLeadingEdge() throws {
        let paragraphItem = selectedItemForWidthTesting(
            block: BlockInputBlock(id: "paragraph", text: "Try mention query")
        )
        let ruleItem = selectedItemForWidthTesting(
            block: BlockInputBlock(id: "rule", kind: .horizontalRule)
        )

        XCTAssertEqual(ruleItem.testingSelectionBackgroundView.frame.minX, paragraphItem.testingSelectionBackgroundView.frame.minX)
    }

    func testCodeBlockWholeSelectionChromeMatchesCodeSurface() throws {
        let codeItem = selectedItemForWidthTesting(
            block: BlockInputBlock(id: "code", kind: .code(language: "swift"), text: "let value = 1")
        )
        let codeSurface = codeItem.testingCodeBackgroundView

        XCTAssertEqual(codeItem.testingSelectionBackgroundView.frame, codeSurface.frame)
        XCTAssertEqual(codeItem.testingSelectionBackgroundSegmentFrames, [codeSurface.frame])
        XCTAssertLessThan(codeItem.testingSelectionBackgroundView.frame.width, codeItem.view.bounds.width / 2)
    }

    func testNestedNumberedListWholeSelectionChromeIncludesDeepestLineBounds() throws {
        let block = BlockInputBlock(
            id: "numbered",
            kind: .numberedListItem(start: 1),
            text: "Numbered list item\nNested numbered item\nDeep nested numbered item",
            lineIndentationLevels: [0, 1, 2]
        )
        let item = multilineListItemForSelectionChromeTesting(block: block)
        let markerView = try XCTUnwrap(item.testingMarkerView)
        let deepestLineFrame = try renderedLineFrame(in: item, utf16Offset: utf16Offset(of: "Deep nested numbered item", in: block.text))
        let renderedTextMaxX = try renderedTextMaxX(in: item)

        XCTAssertLessThanOrEqual(item.testingSelectionBackgroundView.frame.minX, markerView.frame.minX)
        XCTAssertGreaterThanOrEqual(item.testingSelectionBackgroundView.frame.maxX, deepestLineFrame.maxX)
        XCTAssertEqual(item.testingSelectionBackgroundView.frame.maxX, ceil(renderedTextMaxX + 6), accuracy: 1.5)
        XCTAssertLessThan(item.testingSelectionBackgroundView.frame.maxX, item.view.bounds.width - 100)
    }

    func testNestedBulletedListWholeSelectionChromeIncludesDeepestLineBounds() throws {
        let block = BlockInputBlock(
            id: "bullets",
            kind: .bulletedListItem,
            text: "Bulleted list item\nNested bullet item\nDeep nested bullet item",
            lineIndentationLevels: [0, 1, 2]
        )
        let item = multilineListItemForSelectionChromeTesting(block: block)
        let markerView = try XCTUnwrap(item.testingMarkerView)
        let deepestLineFrame = try renderedLineFrame(in: item, utf16Offset: utf16Offset(of: "Deep nested bullet item", in: block.text))
        let renderedTextMaxX = try renderedTextMaxX(in: item)

        XCTAssertLessThanOrEqual(item.testingSelectionBackgroundView.frame.minX, markerView.frame.minX)
        XCTAssertGreaterThanOrEqual(item.testingSelectionBackgroundView.frame.maxX, deepestLineFrame.maxX)
        XCTAssertEqual(item.testingSelectionBackgroundView.frame.maxX, ceil(renderedTextMaxX + 6), accuracy: 1.5)
        XCTAssertLessThan(item.testingSelectionBackgroundView.frame.maxX, item.view.bounds.width - 100)
    }

    func testNestedListWholeSelectionChromeDoesNotUseMaxIndentPlusLongestTextLine() throws {
        let block = BlockInputBlock(
            id: "numbered",
            kind: .numberedListItem(start: 1),
            text: "A very long root list item that should stay wider than the nested item\nNested",
            lineIndentationLevels: [0, 2]
        )
        let item = multilineListItemForSelectionChromeTesting(block: block)
        let renderedTextMaxX = try renderedTextMaxX(in: item)
        let rawMaxIndentPlusTextWidth = try rawMaxIndentPlusTextWidth(in: item, block: block)

        XCTAssertEqual(item.testingSelectionBackgroundView.frame.maxX, ceil(renderedTextMaxX + 6), accuracy: 1.5)
        XCTAssertLessThan(item.testingSelectionBackgroundView.frame.maxX, ceil(rawMaxIndentPlusTextWidth + 6) - 20)
    }

    func testNestedWrappedListWholeSelectionChromeUsesRenderedVisualFragments() throws {
        let block = BlockInputBlock(
            id: "bullets",
            kind: .bulletedListItem,
            text: "Root\nNested \(String(repeating: "wrapped content ", count: 12))",
            lineIndentationLevels: [0, 2]
        )
        let item = multilineListItemForSelectionChromeTesting(block: block, width: 420)
        let renderedTextMaxX = try renderedTextMaxX(in: item)
        let rawMaxIndentPlusTextWidth = try rawMaxIndentPlusTextWidth(in: item, block: block)

        XCTAssertGreaterThanOrEqual(item.testingSelectionBackgroundView.frame.maxX, renderedTextMaxX)
        XCTAssertEqual(
            item.testingSelectionBackgroundView.frame.maxX,
            min(ceil(renderedTextMaxX + 6), item.view.bounds.maxX - 6),
            accuracy: 1.5
        )
        // The unwrapped logical line runs far past the row, so tracking it instead of the
        // rendered fragments would pin the chrome to the trailing clamp on every width.
        XCTAssertGreaterThan(rawMaxIndentPlusTextWidth, item.view.bounds.maxX)
    }

    func testSelectionChromeUsesConfiguredBackgroundColor() {
        let style = BlockInputStyle(selectionBackgroundColor: .systemGreen)
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", text: "BlockInputKit demo"),
            allowsReordering: true,
            style: style,
            isSelected: true,
            delegate: BlockInputView()
        )

        XCTAssertEqual(item.testingSelectionBackgroundView.fillColor, .systemGreen)
    }

    func testSelectedCodeBlockSelectionChromeResizesWithCodeSurfaceAfterTextChange() throws {
        let shortBlock = BlockInputBlock(id: "code", kind: .code(language: "swift"), text: "let value = 1")
        let item = BlockInputBlockItem.configuredForTesting(
            block: shortBlock,
            allowsReordering: true,
            isSelected: true,
            delegate: BlockInputView()
        )
        item.view.frame = NSRect(x: 0, y: 0, width: 900, height: 44)
        item.view.layoutSubtreeIfNeeded()
        let shortSurfaceWidth = item.testingCodeBackgroundView.frame.width

        let longBlock = BlockInputBlock(
            id: "code",
            kind: .code(language: "swift"),
            text: "let value = \"\(String(repeating: "wide ", count: 30))\""
        )
        item.testingTextView?.string = longBlock.text
        item.updateTextDependentChrome(for: longBlock)
        item.view.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(item.testingCodeBackgroundView.frame.width, shortSurfaceWidth)
        XCTAssertEqual(item.testingSelectionBackgroundView.frame, item.testingCodeBackgroundView.frame)

        item.testingTextView?.string = shortBlock.text
        item.updateTextDependentChrome(for: shortBlock)
        item.view.layoutSubtreeIfNeeded()

        XCTAssertEqual(item.testingCodeBackgroundView.frame.width, shortSurfaceWidth, accuracy: 0.5)
        XCTAssertEqual(item.testingSelectionBackgroundView.frame, item.testingCodeBackgroundView.frame)
    }

    func testPartialSelectionChromeCollapsesNativeTextSelection() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", text: "BlockInputKit demo"),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 5, length: 8))

        item.setSelectionHighlightRange(NSRange(location: 5, length: 8))

        XCTAssertEqual(textView.selectedRange(), NSRange(location: 5, length: 0))
        XCTAssertFalse(item.testingSelectionBackgroundView.isHidden)
    }

    func testPartialSelectionChromeSuppressesNativeSelectionBackground() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", text: "BlockInputKit demo"),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let textView = try XCTUnwrap(item.testingTextView)

        item.setSelectionHighlightRange(NSRange(location: 5, length: 8))

        XCTAssertEqual(textView.selectedTextAttributes[.backgroundColor] as? NSColor, .clear)
        XCTAssertTrue(textView.isSelectable)
        item.setBlockSelection(false)
        XCTAssertEqual(textView.selectedTextAttributes[.backgroundColor] as? NSColor, .clear)
        XCTAssertTrue(textView.isSelectable)
    }

    func testPartialSelectionChromeKeepsTextViewSelectableForCaretMechanics() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", text: "BlockInputKit demo"),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let textView = try XCTUnwrap(item.testingTextView)

        item.setSelectionHighlightRange(NSRange(location: 5, length: 8))

        XCTAssertTrue(textView.isSelectable)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 5, length: 0))
    }

    func testNativeSelectionBackgroundStaysDisabledForTextViewSelectionMechanics() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", text: "BlockInputKit demo"),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let textView = try XCTUnwrap(item.testingTextView)

        XCTAssertEqual(textView.selectedTextAttributes[.backgroundColor] as? NSColor, .clear)
        XCTAssertTrue(textView.isSelectable)
        item.restoreNativeSelectionDisplay()
        XCTAssertEqual(textView.selectedTextAttributes[.backgroundColor] as? NSColor, .clear)
        XCTAssertTrue(textView.isSelectable)
    }

    func testPartialSelectionChromeIncludesChecklistMarkerWhenStartingAtBeginning() throws {
        let item = partialSelectedItemForWidthTesting(
            block: BlockInputBlock(id: "check", kind: .checklistItem(isChecked: false), text: "Checklist data"),
            range: NSRange(location: 0, length: 1)
        )
        let checkbox = try XCTUnwrap(item.testingChecklistButton)

        XCTAssertLessThanOrEqual(item.testingSelectionBackgroundView.frame.minX, checkbox.frame.minX)
        XCTAssertGreaterThanOrEqual(item.testingSelectionBackgroundView.frame.maxX, checkbox.frame.maxX)
    }

    func testPartialSelectionChromeIncludesListMarkerWhenStartingAtBeginning() throws {
        let item = partialSelectedItemForWidthTesting(
            block: BlockInputBlock(id: "ordered", kind: .numberedListItem(start: 100), text: "Item"),
            range: NSRange(location: 0, length: 1)
        )
        let markerView = try XCTUnwrap(item.testingMarkerView)

        XCTAssertLessThanOrEqual(item.testingSelectionBackgroundView.frame.minX, markerView.frame.minX)
        XCTAssertGreaterThanOrEqual(item.testingSelectionBackgroundView.frame.maxX, markerView.frame.maxX)
    }

    func testPartialSelectionChromeEndsAtInsertionCaret() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "plain", text: "reveal")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)

        item.setSelectionHighlightRange(NSRange(location: 0, length: 4))
        item.view.layoutSubtreeIfNeeded()

        let endCaretX = try XCTUnwrap(item.textContainerX(forUTF16Offset: 4))
        let textContainerOrigin = textView.textContainerOrigin
        let endViewX = textView.convert(NSPoint(x: textContainerOrigin.x + endCaretX, y: textContainerOrigin.y), to: item.view).x
        XCTAssertEqual(item.testingSelectionBackgroundView.frame.maxX, ceil(endViewX), accuracy: 1)
    }

    func testPartialSelectionChromeLimitsSingleSelectedLineInMultilineCodeBlock() throws {
        let block = BlockInputBlock(
            id: "code",
            kind: .code(language: nil),
            text: "let one = 1\nlet two = 2\nlet three = 3"
        )
        let item = multilineCodeItemForSelectionChromeTesting(block: block)
        let firstLineRange = (block.text as NSString).lineRange(for: NSRange(location: 0, length: 0))

        item.setSelectionHighlightRange(firstLineRange)
        item.view.layoutSubtreeIfNeeded()

        let segments = item.testingSelectionBackgroundSegmentFrames
        XCTAssertEqual(segments.count, 1)
        XCTAssertLessThan(segments[0].height, item.view.bounds.height / 2)
        XCTAssertLessThan(item.testingSelectionBackgroundView.frame.height, item.view.bounds.height / 2)
    }

    func testPartialSelectionChromeSplitsMultilineCodeSelectionIntoLineSegments() throws {
        let block = BlockInputBlock(
            id: "code",
            kind: .code(language: nil),
            text: "let one = 1\nlet two = 2\nlet three = 3"
        )
        let item = multilineCodeItemForSelectionChromeTesting(block: block)
        let text = block.text as NSString
        let startOffset = text.range(of: "one").location
        let endOffset = text.range(of: "two").location + 3

        item.setSelectionHighlightRange(NSRange(location: startOffset, length: endOffset - startOffset))
        item.view.layoutSubtreeIfNeeded()

        let segments = item.testingSelectionBackgroundSegmentFrames
        XCTAssertEqual(segments.count, 2)
        XCTAssertGreaterThan(abs(segments[0].midY - segments[1].midY), 4)
        XCTAssertLessThan(segments[0].height, item.view.bounds.height / 2)
        XCTAssertLessThan(segments[1].height, item.view.bounds.height / 2)
    }

    func testPartialSelectionChromeIncludesBlankCodeLineSegment() throws {
        let block = BlockInputBlock(
            id: "code",
            kind: .code(language: nil),
            text: "let one = 1\n\nlet three = 3"
        )
        let item = multilineCodeItemForSelectionChromeTesting(block: block)

        item.setSelectionHighlightRange(NSRange(location: 0, length: block.utf16Length))
        item.view.layoutSubtreeIfNeeded()

        let segments = item.testingSelectionBackgroundSegmentFrames
        XCTAssertEqual(segments.count, 3)
        XCTAssertGreaterThan(segments[1].width, 1)
    }

    func testPartialSelectionChromeIncludesTrailingBlankCodeLineSegment() throws {
        let block = BlockInputBlock(
            id: "code",
            kind: .code(language: nil),
            text: "let one = 1\n"
        )
        let item = multilineCodeItemForSelectionChromeTesting(block: block)

        item.setSelectionHighlightRange(NSRange(location: 0, length: block.utf16Length))
        item.view.layoutSubtreeIfNeeded()

        let segments = item.testingSelectionBackgroundSegmentFrames
        XCTAssertEqual(segments.count, 2)
        XCTAssertGreaterThan(segments[1].width, 1)
        XCTAssertGreaterThan(abs(segments[1].midY - segments[0].midY), 4)
    }

    private func selectedItemForWidthTesting(block: BlockInputBlock) -> BlockInputBlockItem {
        let item = BlockInputBlockItem.configuredForTesting(
            block: block,
            allowsReordering: true,
            delegate: BlockInputView()
        )
        item.view.frame = NSRect(x: 0, y: 0, width: 900, height: 44)
        item.view.layoutSubtreeIfNeeded()
        item.setBlockSelection(true)
        item.view.layoutSubtreeIfNeeded()
        return item
    }

    private func partialSelectedItemForWidthTesting(block: BlockInputBlock, range: NSRange) -> BlockInputBlockItem {
        let item = BlockInputBlockItem.configuredForTesting(
            block: block,
            allowsReordering: true,
            delegate: BlockInputView()
        )
        item.view.frame = NSRect(x: 0, y: 0, width: 900, height: 44)
        item.view.layoutSubtreeIfNeeded()
        item.setSelectionHighlightRange(range)
        item.view.layoutSubtreeIfNeeded()
        return item
    }

    private func multilineListItemForSelectionChromeTesting(block: BlockInputBlock, width: CGFloat = 900) -> BlockInputBlockItem {
        let textWidth = BlockInputBlockItem.measuredTextWidth(
            for: width,
            block: block,
            allowsReordering: true
        )
        let item = BlockInputBlockItem.configuredForTesting(
            block: block,
            allowsReordering: true,
            delegate: BlockInputView()
        )
        item.view.frame = NSRect(
            x: 0,
            y: 0,
            width: width,
            height: BlockInputBlockItem.height(for: block, textWidth: textWidth)
        )
        item.view.layoutSubtreeIfNeeded()
        item.setBlockSelection(true)
        item.view.layoutSubtreeIfNeeded()
        return item
    }

    private func multilineCodeItemForSelectionChromeTesting(block: BlockInputBlock) -> BlockInputBlockItem {
        let item = BlockInputBlockItem.configuredForTesting(
            block: block,
            allowsReordering: true,
            delegate: BlockInputView()
        )
        item.view.frame = NSRect(
            x: 0,
            y: 0,
            width: 900,
            height: BlockInputBlockItem.height(for: block, textWidth: 820)
        )
        item.view.layoutSubtreeIfNeeded()
        return item
    }

    private func utf16Offset(of substring: String, in text: String) throws -> Int {
        let range = (text as NSString).range(of: substring)
        return try XCTUnwrap(range.location == NSNotFound ? nil : range.location)
    }

    private func renderedLineFrame(in item: BlockInputBlockItem, utf16Offset: Int) throws -> NSRect {
        let textView = try XCTUnwrap(item.testingTextView)
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        layoutManager.ensureLayout(for: textContainer)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: utf16Offset)
        let lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        return textView.convert(lineRect.offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y), to: item.view)
    }

    private func renderedTextMaxX(in item: BlockInputBlockItem) throws -> CGFloat {
        let textView = try XCTUnwrap(item.testingTextView)
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        var maxX = CGFloat.zero
        var glyphIndex = glyphRange.location
        while glyphIndex < NSMaxRange(glyphRange) {
            var lineGlyphRange = NSRange()
            let lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: &lineGlyphRange)
            let itemRect = textView.convert(
                lineRect.offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y),
                to: item.view
            )
            maxX = max(maxX, itemRect.maxX)
            glyphIndex = NSMaxRange(lineGlyphRange)
        }
        return maxX
    }

    private func rawMaxIndentPlusTextWidth(in item: BlockInputBlockItem, block: BlockInputBlock) throws -> CGFloat {
        let textView = try XCTUnwrap(item.testingTextView)
        let font = try XCTUnwrap(textView.font)
        let maxLineWidth = block.text
            .components(separatedBy: .newlines)
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        let maxIndent = BlockInputBlockItem.contentIndent(
            forIndentationLevel: block.lineIndentationLevels.max() ?? block.indentationLevel
        )
        return textView.convert(
            NSPoint(x: textView.textContainerOrigin.x + maxIndent + maxLineWidth, y: textView.textContainerOrigin.y),
            to: item.view
        ).x
    }
}
