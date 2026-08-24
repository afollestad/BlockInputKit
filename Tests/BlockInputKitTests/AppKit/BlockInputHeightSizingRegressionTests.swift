import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputHeightSizingRegressionTests: XCTestCase {
    func testDefaultVisibleLineCountIncludesTrailingEmptyLine() {
        let shortView = configuredView(text: "ss\ns")
        let trailingLineView = configuredView(text: "ss\ns\n")

        XCTAssertEqual(
            trailingLineView.preferredHeight(forWidth: 360),
            shortView.preferredHeight(forWidth: 360),
            accuracy: 0.5
        )
    }

    func testHeightSizedShortDocumentAutohidesDocumentScrollerWhenContentFits() {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "first", text: "")]),
            editorVerticalInset: 10,
            blockVerticalInsetMultiplier: 0.7,
            heightSizing: BlockInputEditorHeightSizing(defaultVisibleLineCount: 2, maximumVisibleLineCount: 9)
        ), size: NSSize(width: 360, height: 200))
        let preferredHeight = mounted.view.preferredHeight(forWidth: 360)

        resizeMountedBlockInputView(mounted, to: NSSize(width: 360, height: preferredHeight))
        mounted.view.scrollView.tile()

        XCTAssertTrue(mounted.view.scrollView.hasVerticalScroller)
        XCTAssertTrue(mounted.view.scrollView.autohidesScrollers)
        XCTAssertTrue(mounted.view.scrollView.verticalScroller?.isHidden ?? true)

        let contentHeight = mounted.view.collectionView.collectionViewLayout?.collectionViewContentSize.height ?? 0
        XCTAssertLessThanOrEqual(contentHeight, mounted.view.scrollView.contentSize.height + 0.5)
        XCTAssertEqual(mounted.view.scrollView.contentView.bounds.minY, 0, accuracy: 0.5)
    }

    func testResizedDocumentDropsItsScrollRangeAfterContentShrinks() async throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "first", text: String(repeating: "wrapping paragraph text ", count: 6))
            ]),
            editorVerticalInset: 10,
            blockVerticalInsetMultiplier: 0.7,
            heightSizing: BlockInputEditorHeightSizing(defaultVisibleLineCount: 2, maximumVisibleLineCount: 9)
        ), size: NSSize(width: 360, height: 200))
        resizeMountedBlockInputView(mounted, to: NSSize(width: 360, height: mounted.view.preferredHeight(forWidth: 360)))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)

        textView.string = "One"
        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        await Task.yield()
        resizeMountedBlockInputView(mounted, to: NSSize(width: 360, height: mounted.view.preferredHeight(forWidth: 360)))

        // The document frame used to ratchet upward, so deleting the wrapped lines left a scroll
        // range for content that no longer existed and a two-line editor still scrolled.
        XCTAssertLessThanOrEqual(
            mounted.view.collectionView.frame.height,
            mounted.view.scrollView.contentSize.height + 0.5
        )
        XCTAssertTrue(mounted.view.scrollView.verticalScroller?.isHidden ?? true)
        XCTAssertEqual(mounted.view.scrollView.contentView.bounds.minY, 0, accuracy: 0.5)
        XCTAssertEqual(mounted.view.scrollView.verticalScrollElasticity, .none)
    }

    func testFixedViewportDocumentUnscrollsAfterContentShrinks() async throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "first", text: "One\nTwo\nThree\nFour\nFive\nSix")]),
            editorVerticalInset: 10,
            blockVerticalInsetMultiplier: 0.7
        ), size: NSSize(width: 360, height: 80))
        let scrollView = mounted.view.scrollView
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let bottomOffset = max(0, mounted.view.collectionView.frame.height - scrollView.contentSize.height)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: bottomOffset))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        XCTAssertGreaterThan(scrollView.contentView.bounds.minY, 0)
        XCTAssertEqual(scrollView.verticalScrollElasticity, .allowed)

        // Nothing resizes the viewport here, so neither of the scroll view's own hooks fires and
        // the editor has to reconcile the shrink on its own once the text change has unwound.
        textView.string = "One"
        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        await Task.yield()

        XCTAssertLessThanOrEqual(mounted.view.collectionView.frame.height, scrollView.contentSize.height + 0.5)
        XCTAssertTrue(scrollView.verticalScroller?.isHidden ?? true)
        XCTAssertEqual(scrollView.contentView.bounds.minY, 0, accuracy: 0.5)
        XCTAssertEqual(scrollView.verticalScrollElasticity, .none)
    }

    func testInlineNewlineKeepsCaretVisibleWhileHostHeightAnimates() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "first", text: "One\nTwo\nThree")]),
            heightSizing: BlockInputEditorHeightSizing(defaultVisibleLineCount: 1, maximumVisibleLineCount: 6)
        ), size: NSSize(width: 360, height: 200))
        let collapsedHeight = mounted.view.preferredHeight(forWidth: 360)
        resizeMountedBlockInputView(mounted, to: NSSize(width: 360, height: collapsedHeight))
        mounted.view.scrollView.contentView.scroll(to: .zero)

        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let expandedText = "One\nTwo\nThree\n"
        let expandedOffset = (expandedText as NSString).length

        mounted.window.makeFirstResponder(textView)
        textView.string = expandedText
        textView.setSelectedRange(NSRange(location: expandedOffset, length: 0))
        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        mounted.view.collectionView.layoutSubtreeIfNeeded()

        let caretRect = mounted.view.collectionView.convert(item.anchorWindowRect(forUTF16Offset: expandedOffset), from: nil)
        let visibleRect = mounted.view.scrollView.contentView.bounds
        XCTAssertGreaterThan(visibleRect.minY, 0)
        XCTAssertLessThanOrEqual(caretRect.maxY, visibleRect.maxY + 0.5)

        let expandedHeight = mounted.view.preferredHeight(forWidth: 360)
        resizeMountedBlockInputView(mounted, to: NSSize(width: 360, height: expandedHeight))
        let contentHeight = mounted.view.collectionView.collectionViewLayout?.collectionViewContentSize.height ?? 0
        XCTAssertLessThanOrEqual(
            mounted.view.scrollView.contentView.bounds.minY,
            max(0, contentHeight - mounted.view.scrollView.contentSize.height) + 0.5
        )
    }

    func testPreferredHeightCallbackPublishesAfterWidthBecomesAvailable() async {
        var transitions: [BlockInputEditorHeightTransition] = []
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 0, height: 200))
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "first", text: "Short")]),
            heightSizing: BlockInputEditorHeightSizing(
                defaultVisibleLineCount: 3,
                maximumVisibleLineCount: 6,
                animation: .default,
                onPreferredHeightTransition: { transitions.append($0) }
            )
        ))
        view.layoutSubtreeIfNeeded()
        await Task.yield()
        XCTAssertTrue(transitions.isEmpty)

        view.frame = NSRect(x: 0, y: 0, width: 360, height: 200)
        view.layoutSubtreeIfNeeded()
        view.scrollView.layoutSubtreeIfNeeded()
        await Task.yield()

        XCTAssertEqual(transitions.count, 1)
        XCTAssertTrue(transitions[0].isInitial)
        XCTAssertEqual(transitions[0].targetHeight, view.preferredHeight(forWidth: 360), accuracy: 0.5)
    }

    func testStructuralReturnInsertionPublishesPreferredHeightTransition() async {
        let thirdID = BlockInputBlockID(rawValue: "third")
        var transitions: [BlockInputEditorHeightTransition] = []
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 360, height: 200))
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "first", text: "One"),
                BlockInputBlock(id: "second", text: "Two"),
                BlockInputBlock(id: thirdID, text: "Three")
            ]),
            blockVerticalInsetMultiplier: 0.7,
            heightSizing: BlockInputEditorHeightSizing(
                defaultVisibleLineCount: 3,
                maximumVisibleLineCount: 9,
                animation: .default,
                onPreferredHeightTransition: { transitions.append($0) }
            )
        ))
        view.layoutSubtreeIfNeeded()
        await Task.yield()
        let initialHeight = transitions.last?.targetHeight ?? view.preferredHeight(forWidth: 360)

        view.focus(blockID: thirdID, utf16Offset: 5)
        _ = view.insertBlockBelowCurrentBlock()
        await Task.yield()

        XCTAssertGreaterThan(transitions.last?.targetHeight ?? 0, initialHeight)
        XCTAssertFalse(transitions.last?.isInitial ?? true)
    }

    func testStructuralReturnReplacementPublishesPreferredHeightTransition() async {
        let quoteID = BlockInputBlockID(rawValue: "quote")
        var transitions: [BlockInputEditorHeightTransition] = []
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 360, height: 200))
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: quoteID, kind: .quote)
            ]),
            heightSizing: BlockInputEditorHeightSizing(
                defaultVisibleLineCount: 1,
                maximumVisibleLineCount: 9,
                animation: .default,
                onPreferredHeightTransition: { transitions.append($0) }
            )
        ))
        view.layoutSubtreeIfNeeded()
        await Task.yield()
        let initialHeight = transitions.last?.targetHeight ?? view.preferredHeight(forWidth: 360)

        view.focus(blockID: quoteID, utf16Offset: 0)
        _ = view.insertBlockBelowCurrentBlock()
        await Task.yield()

        XCTAssertLessThan(transitions.last?.targetHeight ?? .greatestFiniteMagnitude, initialHeight)
        XCTAssertFalse(transitions.last?.isInitial ?? true)
    }

    private func configuredView(text: String) -> BlockInputView {
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 360, height: 200))
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "first", text: text)
            ]),
            editorVerticalInset: 10,
            blockVerticalInsetMultiplier: 0.7,
            heightSizing: BlockInputEditorHeightSizing(defaultVisibleLineCount: 3, maximumVisibleLineCount: 9)
        ))
        view.layoutSubtreeIfNeeded()
        return view
    }
}
