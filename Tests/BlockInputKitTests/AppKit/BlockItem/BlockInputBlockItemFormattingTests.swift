import XCTest
@testable import BlockInputKit

final class BlockInputBlockItemFormattingTests: XCTestCase {
    @MainActor
    func testPrefixReflectsBlockKindAndIndentation() {
        XCTAssertEqual(BlockInputBlockItem.prefix(for: .paragraph, indentationLevel: 2), "")
        XCTAssertEqual(BlockInputBlockItem.prefix(for: .heading(level: 3), indentationLevel: 0), "")
        XCTAssertEqual(BlockInputBlockItem.prefix(for: .code(language: nil), indentationLevel: 1), "")
        XCTAssertEqual(BlockInputBlockItem.prefix(for: .horizontalRule, indentationLevel: 0), "")
        XCTAssertEqual(BlockInputBlockItem.prefix(for: .quote, indentationLevel: 2), "")
        XCTAssertEqual(BlockInputBlockItem.prefix(for: .rawMarkdown, indentationLevel: 0), "")
        XCTAssertEqual(BlockInputBlockItem.prefix(for: .bulletedListItem, indentationLevel: 0), "•")
        XCTAssertEqual(BlockInputBlockItem.prefix(for: .bulletedListItem, indentationLevel: 1), "◦")
        XCTAssertEqual(BlockInputBlockItem.prefix(for: .bulletedListItem, indentationLevel: 2), "▪")
        XCTAssertEqual(BlockInputBlockItem.prefix(for: .numberedListItem(start: 3), indentationLevel: 1), "c.")
        XCTAssertEqual(BlockInputBlockItem.prefix(for: .numberedListItem(start: 3), indentationLevel: 2), "iii.")
        XCTAssertEqual(BlockInputBlockItem.prefix(for: .checklistItem(isChecked: false), indentationLevel: 1), "[ ]")
        XCTAssertEqual(BlockInputBlockItem.prefix(for: .checklistItem(isChecked: true), indentationLevel: 1), "[x]")
    }

    @MainActor
    func testMultilinePrefixesReflectRepeatedTextLines() {
        XCTAssertEqual(
            BlockInputBlockItem.prefixes(for: .bulletedListItem, indentationLevel: 0, text: "One\nTwo\n"),
            "•\n•\n•"
        )
        XCTAssertEqual(
            BlockInputBlockItem.prefixes(for: .numberedListItem(start: 3), indentationLevel: 0, text: "One\nTwo"),
            "3.\n4."
        )
        XCTAssertEqual(
            BlockInputBlockItem.prefixes(for: .bulletedListItem, indentationLevel: 0, text: "One\r\nTwo"),
            "•\n•"
        )
    }

    @MainActor
    func testHeadingUsesHeaderTypographyWithoutMarkdownMarker() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "heading", kind: .heading(level: 2), text: "Title"),
            allowsReordering: true,
            delegate: BlockInputView()
        )

        let textView = try XCTUnwrap(item.testingTextView)
        let kindLabel = try XCTUnwrap(item.testingKindLabel)
        XCTAssertEqual(kindLabel.markerLines, [])
        XCTAssertEqual(textView.font?.pointSize, BlockInputBlockItem.font(for: .heading(level: 2)).pointSize)
        XCTAssertGreaterThan(
            BlockInputBlockItem.height(for: BlockInputBlock(kind: .heading(level: 1), text: "Title"), textWidth: 240),
            BlockInputBlockItem.height(for: BlockInputBlock(kind: .paragraph, text: "Title"), textWidth: 240)
        )
    }

    @MainActor
    func testTextViewDisablesAutomaticDashAndQuoteSubstitution() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", text: ""),
            allowsReordering: true,
            delegate: BlockInputView()
        )

        let textView = try XCTUnwrap(item.testingTextView)
        XCTAssertFalse(textView.isAutomaticDashSubstitutionEnabled)
        XCTAssertFalse(textView.isAutomaticQuoteSubstitutionEnabled)
    }

    @MainActor
    func testTextUsesDynamicLabelForegroundColor() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", text: "Plain"),
            allowsReordering: true,
            delegate: BlockInputView()
        )

        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .labelColor)
    }

    @MainActor
    func testCustomBaseStyleAppliesToTextAndScalesHeadings() throws {
        let baseFont = NSFont.systemFont(ofSize: 20, weight: .light)
        let style = BlockInputStyle(baseText: BlockInputTextStyle(font: baseFont, foregroundColor: .systemPurple))
        let paragraphItem = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", text: "Plain"),
            allowsReordering: true,
            style: style,
            delegate: BlockInputView()
        )
        let headingItem = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "heading", kind: .heading(level: 2), text: "Title"),
            allowsReordering: true,
            style: style,
            delegate: BlockInputView()
        )

        let paragraphTextView = try XCTUnwrap(paragraphItem.testingTextView)
        let paragraphStorage = try XCTUnwrap(paragraphTextView.textStorage)
        XCTAssertEqual(paragraphTextView.font?.pointSize, baseFont.pointSize)
        XCTAssertEqual(paragraphStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .systemPurple)
        XCTAssertEqual(paragraphTextView.typingAttributes[.foregroundColor] as? NSColor, .systemPurple)

        let defaultBaseSize = NSFont.preferredFont(forTextStyle: .body).pointSize
        let expectedHeadingSize = 23 * (baseFont.pointSize / defaultBaseSize)
        XCTAssertEqual(try XCTUnwrap(headingItem.testingTextView?.font).pointSize, expectedHeadingSize, accuracy: 0.5)
        XCTAssertGreaterThan(
            BlockInputBlockItem.height(for: BlockInputBlock(kind: .heading(level: 2), text: "Title"), textWidth: 240, style: style),
            BlockInputBlockItem.height(for: BlockInputBlock(kind: .paragraph, text: "Title"), textWidth: 240, style: style)
        )
    }

    @MainActor
    func testQuoteUsesLeadingRuleInsteadOfMarkdownMarker() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "quote", kind: .quote, text: "Quoted"),
            allowsReordering: true,
            delegate: BlockInputView()
        )

        XCTAssertEqual(try XCTUnwrap(item.testingKindLabel).markerLines, [])
        XCTAssertFalse(try XCTUnwrap(item.testingQuoteBarView).isHidden)

        item.configure(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: "Plain"),
            allowsReordering: true,
            delegate: BlockInputView()
        )

        XCTAssertTrue(try XCTUnwrap(item.testingQuoteBarView).isHidden)
    }

    @MainActor
    func testMultilineParagraphAndQuoteHeightsGrowWithTextLines() {
        let paragraphSingleLine = BlockInputBlockItem.height(
            for: BlockInputBlock(id: "paragraph", kind: .paragraph, text: "First"),
            textWidth: 360
        )
        let paragraphMultiline = BlockInputBlockItem.height(
            for: BlockInputBlock(id: "paragraph", kind: .paragraph, text: "First\nSecond\nThird"),
            textWidth: 360
        )
        let quoteSingleLine = BlockInputBlockItem.height(
            for: BlockInputBlock(id: "quote", kind: .quote, text: "First"),
            textWidth: 360
        )
        let quoteMultiline = BlockInputBlockItem.height(
            for: BlockInputBlock(id: "quote", kind: .quote, text: "First\nSecond\nThird"),
            textWidth: 360
        )

        XCTAssertGreaterThan(paragraphMultiline, paragraphSingleLine)
        XCTAssertGreaterThan(quoteMultiline, quoteSingleLine)
        XCTAssertGreaterThanOrEqual(quoteSingleLine, BlockInputBlockItem.minimumQuoteBarHeight + BlockInputBlockItem.quoteBarVerticalInset * 2)
        XCTAssertGreaterThan(quoteMultiline, paragraphMultiline)
    }

    @MainActor
    func testPerLineChecklistIndentationUsesFirstLineCheckboxAndRemainingLineCheckboxMarkers() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(
                id: "checklist",
                kind: .checklistItem(isChecked: false),
                text: "One\nTwo\nThree",
                lineIndentationLevels: [1, 2, 1]
            ),
            allowsReordering: true,
            delegate: BlockInputView()
        )

        let markerView = try XCTUnwrap(item.testingMarkerView)
        XCTAssertEqual(markerView.markerLines, [
            BlockInputMarkerView.MarkerLine(text: "", indentationLevel: 0),
            BlockInputMarkerView.MarkerLine(text: "", indentationLevel: 2, checkboxState: .unchecked),
            BlockInputMarkerView.MarkerLine(text: "", indentationLevel: 1, checkboxState: .unchecked)
        ])
        XCTAssertFalse(try XCTUnwrap(item.testingChecklistButton).isHidden)
    }

    @MainActor
    func testPerLineCheckedChecklistUsesCheckedCheckboxMarkers() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(
                id: "checklist",
                kind: .checklistItem(isChecked: true),
                text: "One\nTwo"
            ),
            allowsReordering: true,
            delegate: BlockInputView()
        )

        let markerView = try XCTUnwrap(item.testingMarkerView)
        XCTAssertEqual(markerView.markerLines, [
            BlockInputMarkerView.MarkerLine(text: "", indentationLevel: 0),
            BlockInputMarkerView.MarkerLine(text: "", indentationLevel: 0, checkboxState: .checked)
        ])
    }

    @MainActor
    func testChecklistButtonStaysAlignedToFirstLineWhenTextBecomesMultiline() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(
                id: "checklist",
                kind: .checklistItem(isChecked: false),
                text: "One"
            ),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        item.view.frame = NSRect(x: 0, y: 0, width: 420, height: 80)
        item.view.layoutSubtreeIfNeeded()
        let checkbox = try XCTUnwrap(item.testingChecklistButton)
        let singleLineCheckboxMinY = checkbox.frame.minY

        item.configure(
            block: BlockInputBlock(
                id: "checklist",
                kind: .checklistItem(isChecked: false),
                text: "One\n"
            ),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        item.view.layoutSubtreeIfNeeded()

        XCTAssertEqual(checkbox.frame.minY, singleLineCheckboxMinY, accuracy: 0.5)
    }

    @MainActor
    func testEmptyIndentedListLineUsesIndentedTypingParagraphStyle() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(
                id: "list",
                kind: .bulletedListItem,
                text: "One\n",
                lineIndentationLevels: [0, 1]
            ),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let textView = try XCTUnwrap(item.testingTextView)

        item.setSelectedRange(NSRange(location: 4, length: 0))

        let paragraphStyle = try XCTUnwrap(textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle)
        XCTAssertEqual(paragraphStyle.firstLineHeadIndent, 24)
        XCTAssertEqual(paragraphStyle.headIndent, 24)
        XCTAssertEqual(textView.defaultParagraphStyle?.firstLineHeadIndent, 24)
        XCTAssertEqual(textView.defaultParagraphStyle?.headIndent, 24)
    }

    @MainActor
    func testEmptyIndentedListBlockUsesIndentedTypingParagraphStyle() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(
                id: "list",
                kind: .bulletedListItem,
                text: "",
                lineIndentationLevels: [1]
            ),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let textView = try XCTUnwrap(item.testingTextView)

        let paragraphStyle = try XCTUnwrap(textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle)
        XCTAssertEqual(paragraphStyle.firstLineHeadIndent, 24)
        XCTAssertEqual(paragraphStyle.headIndent, 24)
        XCTAssertEqual(textView.defaultParagraphStyle?.firstLineHeadIndent, 24)
        XCTAssertEqual(textView.defaultParagraphStyle?.headIndent, 24)
    }

    @MainActor
    func testHeightUsesMinimumForEmptyBlocks() {
        let height = BlockInputBlockItem.height(for: .emptyParagraph(), textWidth: 240)

        XCTAssertGreaterThanOrEqual(height, BlockInputBlockItemVerticalMetrics.textBlock.minimumHeight)
    }

    @MainActor
    func testChecklistButtonReflectsBlockState() throws {
        let blockID = BlockInputBlockID(rawValue: "check")
        let view = BlockInputView()
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: blockID, kind: .checklistItem(isChecked: true), text: "Done"),
            allowsReordering: true,
            delegate: view
        )

        let checkbox = try XCTUnwrap(item.testingChecklistButton)
        XCTAssertFalse(checkbox.isHidden)
        XCTAssertEqual(checkbox.state, .on)
        XCTAssertEqual(checkbox.accessibilityLabel(), "Toggle checklist item")
    }

    @MainActor
    func testChecklistButtonIsHiddenForNonChecklistBlocks() throws {
        let blockID = BlockInputBlockID(rawValue: "paragraph")
        let view = BlockInputView()
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: blockID, kind: .paragraph, text: "Plain"),
            allowsReordering: true,
            delegate: view
        )

        let checkbox = try XCTUnwrap(item.testingChecklistButton)
        XCTAssertTrue(checkbox.isHidden)
        XCTAssertEqual(checkbox.state, .off)
    }

    @MainActor
    func testHorizontalRuleUsesNonEditableEmptyTextView() throws {
        let blockID = BlockInputBlockID(rawValue: "rule")
        let view = BlockInputView()
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: blockID, kind: .horizontalRule, text: "Hidden"),
            allowsReordering: true,
            delegate: view
        )

        let textView = try XCTUnwrap(item.testingTextView)
        XCTAssertEqual(textView.string, "")
        XCTAssertFalse(textView.isEditable)
        XCTAssertTrue(try XCTUnwrap(item.testingTextScrollView).isHidden)
        XCTAssertFalse(try XCTUnwrap(item.testingHorizontalRuleView).isHidden)
    }

    @MainActor
    func testHorizontalRuleSelectionUsesAccentColor() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "rule", kind: .horizontalRule),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let ruleView = try XCTUnwrap(item.testingHorizontalRuleSelectionView)
        ruleView.accentColor = .systemPink

        item.setBlockSelection(true)

        XCTAssertEqual(ruleView.testingLineView?.layer?.backgroundColor, NSColor.systemPink.cgColor)
        XCTAssertEqual(ruleView.testingLineHeight, 4)
        let selectionBackground = try XCTUnwrap(ruleView.layer?.backgroundColor)
        XCTAssertGreaterThan(selectionBackground.alpha, 0)
    }

    @MainActor
    func testTextBlockSelectionUsesVisibleRowChrome() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", text: "Plain"),
            allowsReordering: true,
            delegate: BlockInputView()
        )

        item.setBlockSelection(true)

        XCTAssertFalse(item.testingSelectionBackgroundView.isHidden)
        XCTAssertGreaterThan(item.testingSelectionBackgroundView.fillColor.alphaComponent, 0)
        XCTAssertEqual(item.view.layer?.borderWidth, CGFloat(0))
        XCTAssertEqual(item.view.layer?.backgroundColor, NSColor.clear.cgColor)
    }

    @MainActor
    func testHorizontalRuleViewIsHiddenForTextBlocks() throws {
        let view = BlockInputView()
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "rule", kind: .horizontalRule),
            allowsReordering: true,
            delegate: view
        )

        item.configure(
            block: BlockInputBlock(id: "paragraph", text: "Plain"),
            allowsReordering: true,
            delegate: view
        )

        let ruleView = try XCTUnwrap(item.testingHorizontalRuleView)
        XCTAssertTrue(ruleView.isHidden)
        XCTAssertEqual(ruleView.alphaValue, 0)
        XCTAssertFalse(try XCTUnwrap(item.testingTextScrollView).isHidden)
    }

    @MainActor
    func testSelectedHorizontalRuleOverlayIsClearedWhenReconfiguredAsTextBlock() throws {
        let view = BlockInputView()
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "rule", kind: .horizontalRule),
            allowsReordering: true,
            delegate: view
        )
        item.setBlockSelection(true)

        item.configure(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: "Plain"),
            allowsReordering: true,
            isSelected: true,
            delegate: view
        )

        let ruleView = try XCTUnwrap(item.testingHorizontalRuleSelectionView)
        XCTAssertTrue(ruleView.isHidden)
        XCTAssertEqual(ruleView.alphaValue, 0)
        XCTAssertEqual(ruleView.testingLineHeight, 2)
        XCTAssertEqual(ruleView.testingLineView?.layer?.backgroundColor, NSColor.separatorColor.cgColor)
        XCTAssertEqual(ruleView.layer?.backgroundColor, NSColor.clear.cgColor)
        XCTAssertEqual(try XCTUnwrap(item.testingTextView).string, "Plain")
        XCTAssertFalse(try XCTUnwrap(item.testingTextScrollView).isHidden)
    }

    @MainActor
    func testChecklistButtonStateIsClearedWhenItemIsReconfigured() throws {
        let view = BlockInputView()
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "check", kind: .checklistItem(isChecked: true), text: "Done"),
            allowsReordering: true,
            delegate: view
        )

        item.configure(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: "Plain"),
            allowsReordering: true,
            delegate: view
        )

        let checkbox = try XCTUnwrap(item.testingChecklistButton)
        XCTAssertTrue(checkbox.isHidden)
        XCTAssertEqual(checkbox.state, .off)
    }

    @MainActor
    func testChecklistButtonReflectsIndentationWhenReconfigured() throws {
        let view = BlockInputView()
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "check", kind: .checklistItem(isChecked: true), text: "Done"),
            allowsReordering: true,
            delegate: view
        )
        item.view.frame = NSRect(x: 0, y: 0, width: 320, height: 44)
        item.view.layoutSubtreeIfNeeded()
        let checkbox = try XCTUnwrap(item.testingChecklistButton)
        let initialMinX = checkbox.frame.minX

        item.configure(
            block: BlockInputBlock(
                id: "indented",
                kind: .checklistItem(isChecked: true),
                text: "Indented",
                indentationLevel: 2
            ),
            allowsReordering: true,
            delegate: view
        )
        item.view.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(checkbox.frame.minX, initialMinX)
    }

}
