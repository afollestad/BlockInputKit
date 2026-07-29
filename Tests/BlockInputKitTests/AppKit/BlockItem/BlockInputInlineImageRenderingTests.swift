import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputInlineImageRenderingTests: XCTestCase {
    private let text = "Badge ![P1](https://example.com/p1.png) alert"
    private let source = "https://example.com/p1.png"

    func testUnloadedInlineImageReservesPlaceholderAdvance() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "block", text: text)]),
            imageLoader: SizedInlineImageLoader(sizesBySource: [:])
        ))
        let textStorage = try XCTUnwrap(textStorage(in: mounted))
        let anchorOffset = anchorOffset(in: text)

        let run = try XCTUnwrap(
            textStorage.attribute(.blockInputInlineImage, at: anchorOffset, effectiveRange: nil) as? BlockInputInlineImageRun
        )
        XCTAssertFalse(run.isLoaded)
        XCTAssertEqual(run.displaySize.width, run.displaySize.height)
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: anchorOffset, effectiveRange: nil) as? NSColor, .clear)
        XCTAssertGreaterThan(try XCTUnwrap(textStorage.attribute(.kern, at: anchorOffset, effectiveRange: nil) as? CGFloat), 0)
        XCTAssertEqual(
            textStorage.attribute(.blockInputHiddenDelimiter, at: anchorOffset + 1, effectiveRange: nil) as? Bool,
            true
        )
        XCTAssertEqual(textStorage.attribute(.toolTip, at: anchorOffset, effectiveRange: nil) as? String, "P1")
    }

    func testLoadedInlineImageUsesNaturalSizeAndGrowsLine() async throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "block", text: text)]),
            imageLoader: SizedInlineImageLoader(source: "https://example.com/p1.png", width: 64, height: 48)
        ))
        try await waitForInlineImage(in: mounted.view)
        let textView = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0)?.testingTextView)
        let textStorage = try XCTUnwrap(textView.textStorage)
        let anchorOffset = anchorOffset(in: text)

        let run = try XCTUnwrap(
            textStorage.attribute(.blockInputInlineImage, at: anchorOffset, effectiveRange: nil) as? BlockInputInlineImageRun
        )
        XCTAssertTrue(run.isLoaded)
        XCTAssertEqual(run.displaySize, NSSize(width: 64, height: 48))

        let layoutManager = try XCTUnwrap(textView.layoutManager)
        layoutManager.ensureLayout(for: try XCTUnwrap(textView.textContainer))
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: anchorOffset)
        let lineFragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        XCTAssertGreaterThanOrEqual(lineFragmentRect.height, 48)
    }

    func testLoadedInlineImageGrowsMeasuredRowHeightToMatch() async throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "block", text: text)]),
            imageLoader: SizedInlineImageLoader(source: "https://example.com/p1.png", width: 64, height: 96)
        ))
        try await waitForInlineImage(in: mounted.view)
        mounted.view.collectionView.layoutSubtreeIfNeeded()
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))

        // Mounted row height and offscreen measurement must agree on the grown line.
        let measuredHeight = mounted.view.measuredBlockItemHeight(
            for: try XCTUnwrap(item.renderedBlock),
            itemWidth: mounted.view.collectionView.bounds.width,
            isDocumentStartBlock: true
        )
        XCTAssertGreaterThanOrEqual(measuredHeight, 96)
        XCTAssertEqual(item.view.frame.height, measuredHeight, accuracy: 0.5)
    }

    func testBackspaceAfterInlineImageRemovesWholeSpan() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "block", text: text)]),
            imageLoader: SizedInlineImageLoader(sizesBySource: [:])
        ))
        let textView = try activeTextView(in: mounted)
        let imageEnd = NSMaxRange((text as NSString).range(of: "![P1](\(source))"))
        textView.setSelectedRange(NSRange(location: imageEnd, length: 0))

        textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["Badge  alert"])
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: "block", utf16Offset: 6)))
    }

    func testDeleteForwardBeforeInlineImageRemovesWholeSpan() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "block", text: text)]),
            imageLoader: SizedInlineImageLoader(sizesBySource: [:])
        ))
        let textView = try activeTextView(in: mounted)
        let anchorOffset = anchorOffset(in: text)
        textView.setSelectedRange(NSRange(location: anchorOffset, length: 0))

        textView.doCommand(by: #selector(NSResponder.deleteForward(_:)))

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["Badge  alert"])
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: "block", utf16Offset: anchorOffset)))
    }

    func testPlainRightArrowSkipsInlineImageAsOneStep() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "block", text: text)]),
            imageLoader: SizedInlineImageLoader(sizesBySource: [:])
        ))
        let textView = try activeTextView(in: mounted)
        let anchorOffset = anchorOffset(in: text)
        let imageEnd = NSMaxRange((text as NSString).range(of: "![P1](\(source))"))
        textView.setSelectedRange(NSRange(location: anchorOffset, length: 0))

        textView.keyDown(with: try plainRightEvent())

        XCTAssertEqual(textView.selectedRange(), NSRange(location: imageEnd, length: 0))
    }

    func testPlainLeftArrowSkipsInlineImageAsOneStep() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "block", text: text)]),
            imageLoader: SizedInlineImageLoader(sizesBySource: [:])
        ))
        let textView = try activeTextView(in: mounted)
        let anchorOffset = anchorOffset(in: text)
        let imageEnd = NSMaxRange((text as NSString).range(of: "![P1](\(source))"))
        textView.setSelectedRange(NSRange(location: imageEnd, length: 0))

        textView.keyDown(with: try plainLeftEvent())

        XCTAssertEqual(textView.selectedRange(), NSRange(location: anchorOffset, length: 0))
    }

    func testCopyingSelectionAcrossInlineImageKeepsSourceSyntax() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "block", text: text)]),
            imageLoader: SizedInlineImageLoader(sizesBySource: [:])
        ))
        let textView = try activeTextView(in: mounted)
        textView.setSelectedRange(NSRange(location: 0, length: (text as NSString).length))

        NSPasteboard.general.clearContents()
        textView.copy(nil)

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), text)
    }

    private func waitForInlineImage(in view: BlockInputView) async throws {
        for _ in 0..<40 {
            if view.inlineImageStore.image(forSource: source) != nil {
                // One extra hop lets the store's change callback restyle mounted rows.
                await Task.yield()
                return
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTFail("Inline image did not load.")
    }

    private func textStorage(in mounted: (view: BlockInputView, window: NSWindow)) throws -> NSTextStorage? {
        try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0)?.testingTextView).textStorage
    }

    private func activeTextView(in mounted: (view: BlockInputView, window: NSWindow)) throws -> BlockInputTextView {
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        return textView
    }

    private func anchorOffset(in text: String) -> Int {
        (text as NSString).range(of: "!").location
    }
}
