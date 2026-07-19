import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewInlineHintTests: XCTestCase {
    func testInlineHintDrawsAfterFocusedCaretAndSuppliesContext() throws {
        let blockID = BlockInputBlockID(rawValue: "command")
        let text = "/review-github-pr"
        var contexts: [BlockInputInlineHintContext] = []
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: text)
            ]),
            inlineHintProvider: { context in
                contexts.append(context)
                return BlockInputInlineHint(text: " [PR URL]")
            }
        ))

        mounted.view.focus(blockID: blockID, utf16Offset: (text as NSString).length)

        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let hintView = item.testingInlineHintView
        let context = try XCTUnwrap(contexts.last)

        XCTAssertFalse(hintView.isHidden)
        XCTAssertEqual(hintView.text, " [PR URL]")
        XCTAssertGreaterThan(hintView.frame.minX, textView.textContainerInset.width)
        XCTAssertGreaterThan(hintView.frame.width, 1)
        XCTAssertTrue(context.editorView === mounted.view)
        XCTAssertEqual(context.block.id, blockID)
        XCTAssertEqual(context.blockIndex, 0)
        XCTAssertEqual(context.cursor, BlockInputCursor(blockID: blockID, utf16Offset: (text as NSString).length))
        XCTAssertEqual(context.selectedRange, NSRange(location: (text as NSString).length, length: 0))
        XCTAssertTrue(context.isDocumentStartBlock)
        XCTAssertFalse(context.isAtDocumentStart)
    }

    func testInlineHintCanAppearAfterSlashCommandCompletionIsAccepted() async throws {
        let blockID = BlockInputBlockID(rawValue: "command")
        let expectedText = "[/heading](demo://heading) "
        let provider = PopupCompletionProvider(suggestions: [
            .slashCommand(id: "heading", title: "Heading", uri: "demo://heading", label: "heading")
        ])
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "/")
            ]),
            inlineHintProvider: { context in
                context.block.text == expectedText
                    ? BlockInputInlineHint(text: "Heading text")
                    : nil
            },
            completionProvider: provider
        ))
        mounted.view.focus(blockID: blockID, utf16Offset: 1)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))

        mounted.view.refreshCompletionSession(item: item, blockID: blockID)
        await mounted.view.completionRequestTask?.value

        XCTAssertTrue(item.testingInlineHintView.isHidden)
        XCTAssertTrue(mounted.view.handleCompletionCommand(#selector(NSResponder.insertNewline(_:))))

        let updatedItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        XCTAssertEqual(mounted.view.document.blocks.map(\.text), [expectedText])
        XCTAssertEqual(updatedItem.testingInlineHintView.text, "Heading text")
        XCTAssertFalse(updatedItem.testingInlineHintView.isHidden)
    }

    func testSlashCommandHintGlyphAlignsAcrossSingleVirtualLiteralAndTypedSpaces() throws {
        let styles = [
            BlockInputStyle.default,
            BlockInputStyle(baseText: BlockInputTextStyle(font: .systemFont(ofSize: 17, weight: .semibold)))
        ]
        let cases = [
            SlashHintGeometryCase(
                bareText: "/review",
                spacedText: "/review ",
                argumentText: "/review x",
                rawSlashCommandChips: true
            ),
            SlashHintGeometryCase(
                bareText: "[/review](demo://review)",
                spacedText: "[/review](demo://review) ",
                argumentText: "[/review](demo://review) x",
                rawSlashCommandChips: false
            )
        ]

        for style in styles {
            for testCase in cases {
                try assertSlashHintGeometry(testCase, style: style)
            }
        }
    }

    func testPartialRawSlashCommandDoesNotReserveHintSpacing() throws {
        let text = "/effo"
        let argumentHints = BlockInputSlashCommandArgumentHints(["effort": "low|medium|high"])
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "command", text: text)
            ]),
            inlineHintProvider: { argumentHints.inlineHint(for: $0) },
            rawSlashCommandChips: true
        ))

        mounted.view.focus(blockID: "command", utf16Offset: (text as NSString).length)
        mounted.view.updateInlineHintsForVisibleItems()

        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)
        XCTAssertTrue(item.testingInlineHintView.isHidden)
        XCTAssertNil(textStorage.attribute(.kern, at: textStorage.length - 1, effectiveRange: nil))
    }

    func testBareRawSlashCommandHintDoesNotMoveCaretOrMutateTextSpacing() throws {
        let text = "/effort"
        let hintState = InlineHintVisibilityState()
        let argumentHints = BlockInputSlashCommandArgumentHints(["effort": "low|medium|high"])
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "command", text: text)
            ]),
            inlineHintProvider: { context in
                hintState.returnsHint ? argumentHints.inlineHint(for: context) : nil
            },
            rawSlashCommandChips: true
        ))
        mounted.view.focus(blockID: "command", utf16Offset: (text as NSString).length)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)

        XCTAssertNil(textStorage.attribute(.kern, at: textStorage.length - 1, effectiveRange: nil))

        hintState.returnsHint = true
        mounted.view.updateInlineHintsForVisibleItems()

        let textView = try XCTUnwrap(item.testingTextView)
        let textContainerX = try XCTUnwrap(item.textContainerX(forUTF16Offset: (text as NSString).length))
        let caretX = textView.textContainerOrigin.x + textContainerX
        XCTAssertFalse(item.testingInlineHintView.isHidden)
        XCTAssertNil(textStorage.attribute(.kern, at: textStorage.length - 1, effectiveRange: nil))
        XCTAssertEqual(
            item.testingInlineHintView.frame.minX,
            caretX,
            accuracy: 1
        )

        hintState.returnsHint = false
        mounted.view.updateInlineHintsForVisibleItems()

        XCTAssertTrue(item.testingInlineHintView.isHidden)
        XCTAssertNil(textStorage.attribute(.kern, at: textStorage.length - 1, effectiveRange: nil))
    }

    func testTypingAndUndoingSlashCommandSpaceOnlyMutatesLiteralDocumentText() throws {
        let text = "/review"
        let mounted = makeSlashHintView(text: text, rawSlashCommandChips: true)
        mounted.view.focus(blockID: "command", utf16Offset: (text as NSString).length)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)

        XCTAssertEqual(mounted.view.document.markdown, text)
        XCTAssertEqual(textView.accessibilityValue(), text)
        XCTAssertEqual(item.testingInlineHintView.text, " hint")

        textView.insertText(" ", replacementRange: textView.selectedRange())

        XCTAssertEqual(mounted.view.document.markdown, "\(text) ")
        XCTAssertEqual(textView.accessibilityValue(), "\(text) ")
        XCTAssertEqual(item.testingInlineHintView.text, "hint")
        XCTAssertTrue(textView.performKeyEquivalent(with: try commandZEvent()))
        XCTAssertEqual(mounted.view.document.markdown, text)
        XCTAssertEqual(textView.accessibilityValue(), text)
        XCTAssertEqual(item.testingInlineHintView.text, " hint")
    }

    func testInlineHintHidesForNilProviderNonCollapsedSelectionReadOnlyAndUnsupportedBlocks() throws {
        try assertHintHidden(
            blocks: [BlockInputBlock(id: "plain", text: "/command")],
            focus: BlockInputCursor(blockID: "plain", utf16Offset: 8),
            inlineHintProvider: nil
        )
        try assertHintHidden(
            blocks: [BlockInputBlock(id: "selection", text: "/command")],
            focus: BlockInputCursor(blockID: "selection", utf16Offset: 8),
            selectedRangeOverride: NSRange(location: 0, length: 2),
            inlineHintProvider: { _ in BlockInputInlineHint(text: " hint") }
        )
        try assertHintHidden(
            blocks: [BlockInputBlock(id: "readonly", text: "/command")],
            focus: BlockInputCursor(blockID: "readonly", utf16Offset: 8),
            isEditable: false,
            inlineHintProvider: { _ in BlockInputInlineHint(text: " hint") }
        )
        try assertHintHidden(
            blocks: [BlockInputBlock(id: "code", kind: .code(language: nil), text: "/command")],
            focus: BlockInputCursor(blockID: "code", utf16Offset: 8),
            inlineHintProvider: { _ in BlockInputInlineHint(text: " hint") }
        )
    }

    func testInlineHintHidesWhenSelectionIsStaleOrBlockIsNotFocused() throws {
        let blockID = BlockInputBlockID(rawValue: "command")
        let text = "/command"
        var providerCallCount = 0
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: text)
            ]),
            inlineHintProvider: { _ in
                providerCallCount += 1
                return BlockInputInlineHint(text: " hint")
            }
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        providerCallCount = 0
        mounted.view.selection = .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 100))
        mounted.view.updateInlineHintsForVisibleItems()

        XCTAssertTrue(item.testingInlineHintView.isHidden)
        XCTAssertEqual(providerCallCount, 0)

        let unfocusedMounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: text)
            ]),
            inlineHintProvider: { _ in
                providerCallCount += 1
                return BlockInputInlineHint(text: " hint")
            }
        ))
        let unfocusedItem = try XCTUnwrap(unfocusedMounted.view.visibleBlockItemForTesting(at: 0))
        unfocusedMounted.view.selection = .cursor(BlockInputCursor(blockID: blockID, utf16Offset: (text as NSString).length))
        unfocusedItem.textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        unfocusedMounted.view.updateInlineHintsForVisibleItems()

        XCTAssertTrue(unfocusedItem.testingInlineHintView.isHidden)
        XCTAssertEqual(providerCallCount, 0)
    }

    func testInlineHintDoesNotMutateDocumentExportOrAccessibilityValue() throws {
        let blockID = BlockInputBlockID(rawValue: "command")
        let text = "/review-github-pr"
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: text)
            ]),
            inlineHintProvider: { _ in BlockInputInlineHint(text: " [PR URL]") }
        ))

        mounted.view.focus(blockID: blockID, utf16Offset: (text as NSString).length)
        mounted.view.updateInlineHintsForVisibleItems()

        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)

        XCTAssertFalse(item.testingInlineHintView.isHidden)
        XCTAssertEqual(textView.string, text)
        XCTAssertEqual(mounted.view.document.blocks[0].text, text)
        XCTAssertEqual(mounted.view.document.markdown, text)
        XCTAssertEqual(textView.accessibilityValue(), text)
    }

    func testInlineHintClearsDuringBlockReuse() throws {
        let view = BlockInputView()
        view.configure(BlockInputConfiguration())
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "first", text: "/first"),
            allowsReordering: true,
            inlineHint: BlockInputInlineHint(text: " hint"),
            delegate: view
        )

        item.testingInlineHintView.isHidden = false
        item.prepareForReuse()

        XCTAssertTrue(item.testingInlineHintView.isHidden)
        XCTAssertNil(item.textView.inlineHint)
    }

    private func assertHintHidden(
        blocks: [BlockInputBlock],
        focus: BlockInputCursor,
        selectedRangeOverride: NSRange? = nil,
        isEditable: Bool = true,
        inlineHintProvider: BlockInputInlineHintProvider?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: blocks),
            isEditable: isEditable,
            inlineHintProvider: inlineHintProvider
        ))
        mounted.view.focus(blockID: focus.blockID, utf16Offset: focus.utf16Offset)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0), file: file, line: line)
        if let selectedRangeOverride {
            item.setSelectedRange(selectedRangeOverride)
            mounted.view.applySelection(.text(BlockInputTextRange(blockID: focus.blockID, range: selectedRangeOverride)), notify: false)
        }
        mounted.view.updateInlineHintsForVisibleItems()

        XCTAssertTrue(item.testingInlineHintView.isHidden, file: file, line: line)
    }

    private func assertSlashHintGeometry(
        _ testCase: SlashHintGeometryCase,
        style: BlockInputStyle
    ) throws {
        let bare = try slashHintGeometry(
            text: testCase.bareText,
            rawSlashCommandChips: testCase.rawSlashCommandChips,
            style: style
        )
        let spaced = try slashHintGeometry(
            text: testCase.spacedText,
            rawSlashCommandChips: testCase.rawSlashCommandChips,
            style: style
        )
        let argumentX = try slashArgumentX(
            text: testCase.argumentText,
            rawSlashCommandChips: testCase.rawSlashCommandChips,
            style: style
        )
        let unhintedCaretX = try slashCaretXWithoutHint(
            text: testCase.bareText,
            rawSlashCommandChips: testCase.rawSlashCommandChips,
            style: style
        )

        XCTAssertEqual(bare.caretX, unhintedCaretX, accuracy: 1, testCase.bareText)
        XCTAssertEqual(bare.hintFrameX, bare.caretX, accuracy: 1, testCase.bareText)
        XCTAssertEqual(spaced.hintFrameX, spaced.caretX, accuracy: 1, testCase.spacedText)
        XCTAssertEqual(spaced.trailingSpaceFont, bare.hintFont, testCase.spacedText)
        XCTAssertEqual(bare.virtualSpaceWidth, spaced.caretX - bare.caretX, accuracy: 0.01, testCase.bareText)
        XCTAssertEqual(bare.visibleHintGlyphX, spaced.visibleHintGlyphX, accuracy: 1, testCase.bareText)
        XCTAssertEqual(spaced.visibleHintGlyphX, argumentX, accuracy: 1, testCase.spacedText)
        XCTAssertEqual(bare.hintText, " hint")
        XCTAssertEqual(spaced.hintText, "hint")
    }

    private func slashHintGeometry(
        text: String,
        rawSlashCommandChips: Bool,
        style: BlockInputStyle = .default
    ) throws -> SlashHintGeometry {
        let mounted = makeSlashHintView(text: text, rawSlashCommandChips: rawSlashCommandChips, style: style)
        mounted.view.focus(blockID: "command", utf16Offset: (text as NSString).length)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let hintView = item.testingInlineHintView
        let textContainerX = try XCTUnwrap(item.textContainerX(forUTF16Offset: (text as NSString).length))
        let leadingSpaceWidth = hintView.text.hasPrefix(" ")
            ? (" " as NSString).size(withAttributes: [.font: hintView.font]).width
            : 0
        let trailingSpaceFont = text.last?.isWhitespace == true
            ? textView.textStorage?.attribute(.font, at: (text as NSString).length - 1, effectiveRange: nil) as? NSFont
            : nil

        XCTAssertFalse(hintView.isHidden)
        return SlashHintGeometry(
            caretX: textView.textContainerOrigin.x + textContainerX,
            hintFrameX: hintView.frame.minX,
            virtualSpaceWidth: leadingSpaceWidth,
            visibleHintGlyphX: hintView.frame.minX + leadingSpaceWidth,
            hintText: hintView.text,
            hintFont: hintView.font,
            trailingSpaceFont: trailingSpaceFont
        )
    }

    private func slashArgumentX(
        text: String,
        rawSlashCommandChips: Bool,
        style: BlockInputStyle = .default
    ) throws -> CGFloat {
        let mounted = makeSlashHintView(text: text, rawSlashCommandChips: rawSlashCommandChips, style: style)
        mounted.view.focus(blockID: "command", utf16Offset: (text as NSString).length)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let argumentOffset = (text as NSString).range(of: "x", options: .backwards).location
        let textContainerX = try XCTUnwrap(item.textContainerX(forUTF16Offset: argumentOffset))

        return textView.textContainerOrigin.x + textContainerX
    }

    private func slashCaretXWithoutHint(
        text: String,
        rawSlashCommandChips: Bool,
        style: BlockInputStyle = .default
    ) throws -> CGFloat {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "command", text: text)
            ]),
            rawSlashCommandChips: rawSlashCommandChips,
            style: style
        ))
        mounted.view.focus(blockID: "command", utf16Offset: (text as NSString).length)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let textContainerX = try XCTUnwrap(item.textContainerX(forUTF16Offset: (text as NSString).length))
        return textView.textContainerOrigin.x + textContainerX
    }

    private func makeSlashHintView(
        text: String,
        rawSlashCommandChips: Bool,
        style: BlockInputStyle = .default
    ) -> (view: BlockInputView, window: NSWindow) {
        let argumentHints = BlockInputSlashCommandArgumentHints(["review": "hint"])
        return makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "command", text: text)
            ]),
            inlineHintProvider: { argumentHints.inlineHint(for: $0) },
            rawSlashCommandChips: rawSlashCommandChips,
            style: style
        ))
    }
}

private struct SlashHintGeometryCase {
    var bareText: String
    var spacedText: String
    var argumentText: String
    var rawSlashCommandChips: Bool
}

private struct SlashHintGeometry {
    var caretX: CGFloat
    var hintFrameX: CGFloat
    var virtualSpaceWidth: CGFloat
    var visibleHintGlyphX: CGFloat
    var hintText: String
    var hintFont: NSFont
    var trailingSpaceFont: NSFont?
}

@MainActor
private final class InlineHintVisibilityState {
    var returnsHint = false
}
