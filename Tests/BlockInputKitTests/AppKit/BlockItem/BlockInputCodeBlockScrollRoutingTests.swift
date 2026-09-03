import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputCodeBlockScrollRoutingTests: XCTestCase {
    func testLongSingleLineCodeUsesHorizontalOverflow() throws {
        let item = configuredItem(block: Self.longCodeBlock())
        let scrollView = try XCTUnwrap(item.testingTextScrollView)
        let textView = try XCTUnwrap(item.testingTextView)

        XCTAssertTrue(scrollView.hasHorizontalScroller)
        XCTAssertFalse(scrollView.hasVerticalScroller)
        XCTAssertEqual(scrollView.scrollerStyle, .overlay)
        XCTAssertFalse(textView.textContainer?.widthTracksTextView ?? true)
        XCTAssertGreaterThan(textView.frame.width, scrollView.contentView.bounds.width)
    }

    func testLongParagraphStillWrapsToViewport() throws {
        let item = configuredItem(block: BlockInputBlock(id: "paragraph", text: Self.longText()))
        let scrollView = try XCTUnwrap(item.testingTextScrollView)
        let textView = try XCTUnwrap(item.testingTextView)

        XCTAssertFalse(scrollView.hasHorizontalScroller)
        XCTAssertTrue(textView.textContainer?.widthTracksTextView ?? false)
        XCTAssertEqual(textView.frame.width, scrollView.contentView.bounds.width, accuracy: 0.5)
    }

    func testReusingCodeItemForParagraphResetsHorizontalScrolling() throws {
        let item = configuredItem(block: Self.longCodeBlock())
        let scrollView = try XCTUnwrap(item.testingTextScrollView)
        scrollView.contentView.scroll(to: NSPoint(x: 120, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        item.configure(
            block: BlockInputBlock(id: "paragraph", text: Self.longText()),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        item.view.layoutSubtreeIfNeeded()

        let textView = try XCTUnwrap(item.testingTextView)
        XCTAssertFalse(scrollView.hasHorizontalScroller)
        XCTAssertTrue(textView.textContainer?.widthTracksTextView ?? false)
        XCTAssertEqual(scrollView.contentView.bounds.origin.x, 0, accuracy: 0.5)
    }

    func testMostlyVerticalWheelOverCodeTextForwardsToAncestor() throws {
        let item = configuredItem(block: Self.longCodeBlock(), embeddedInVerticalScrollView: true)
        let parentScrollView = try XCTUnwrap(item.view.enclosingScrollView as? RecordingScrollView)
        let textView = try XCTUnwrap(item.testingTextView)

        textView.scrollWheel(with: try Self.scrollEvent(deltaY: -12, deltaX: -4))

        XCTAssertEqual(parentScrollView.verticalScrollCount, 1)
    }

    func testHorizontalDominantWheelOverCodeScrollViewStaysLocal() throws {
        let item = configuredItem(block: Self.longCodeBlock(), embeddedInVerticalScrollView: true)
        let parentScrollView = try XCTUnwrap(item.view.enclosingScrollView as? RecordingScrollView)
        let scrollView = try XCTUnwrap(item.testingTextScrollView)

        scrollView.scrollWheel(with: try Self.scrollEvent(deltaY: -4, deltaX: -12))

        XCTAssertEqual(parentScrollView.verticalScrollCount, 0)
    }

    func testHorizontalDominantWheelOverCodeTextScrollsCodeBlock() throws {
        let item = configuredItem(block: Self.longCodeBlock())
        let scrollView = try XCTUnwrap(item.testingTextScrollView)
        let textView = try XCTUnwrap(item.testingTextView)

        textView.scrollWheel(with: try Self.scrollEvent(deltaY: 0, deltaX: -12))

        XCTAssertGreaterThan(scrollView.contentView.bounds.origin.x, 0)
    }

    func testShiftWheelOverCodeTextScrollsCodeBlockHorizontally() throws {
        let item = configuredItem(block: Self.longCodeBlock(), embeddedInVerticalScrollView: true)
        let parentScrollView = try XCTUnwrap(item.view.enclosingScrollView as? RecordingScrollView)
        let scrollView = try XCTUnwrap(item.testingTextScrollView)
        let textView = try XCTUnwrap(item.testingTextView)

        textView.scrollWheel(with: try Self.scrollEvent(deltaY: -12, deltaX: 0, modifierFlags: .shift))

        XCTAssertEqual(parentScrollView.verticalScrollCount, 0)
        XCTAssertGreaterThan(scrollView.contentView.bounds.origin.x, 0)
    }

    func testSmallMouseWheelDeltaUsesLineScrollDistanceForHorizontalCodeScroll() throws {
        let item = configuredItem(block: Self.longCodeBlock())
        let scrollView = try XCTUnwrap(item.testingTextScrollView)
        let textView = try XCTUnwrap(item.testingTextView)

        textView.scrollWheel(with: try Self.scrollEvent(deltaY: 0, deltaX: -1))

        XCTAssertGreaterThanOrEqual(scrollView.contentView.bounds.origin.x, scrollView.horizontalLineScroll - 0.5)
    }

    func testShiftWheelAfterVerticalScrollSequenceBreaksToHorizontalCodeScroll() throws {
        let item = configuredItem(block: Self.longCodeBlock(), embeddedInVerticalScrollView: true)
        let parentScrollView = try XCTUnwrap(item.view.enclosingScrollView as? RecordingScrollView)
        let scrollView = try XCTUnwrap(item.testingTextScrollView)
        let textView = try XCTUnwrap(item.testingTextView)

        textView.scrollWheel(with: try Self.scrollEvent(deltaY: -12, deltaX: 0))
        textView.scrollWheel(with: try Self.scrollEvent(deltaY: -1, deltaX: 0, modifierFlags: .shift))

        XCTAssertEqual(parentScrollView.verticalScrollCount, 1)
        XCTAssertGreaterThan(scrollView.contentView.bounds.origin.x, 0)
    }

    func testDecayingVerticalMomentumContinuesForwardingToAncestor() throws {
        let item = configuredItem(block: Self.longCodeBlock(), embeddedInVerticalScrollView: true)
        let parentScrollView = try XCTUnwrap(item.view.enclosingScrollView as? RecordingScrollView)
        let scrollView = try XCTUnwrap(item.testingTextScrollView)

        scrollView.scrollWheel(with: try Self.preciseScrollEvent(deltaY: -12, deltaX: -1))
        scrollView.scrollWheel(with: try Self.preciseScrollEvent(deltaY: -1, deltaX: -4))

        XCTAssertEqual(parentScrollView.verticalScrollCount, 2)
    }

    func testOuterEditorScrollViewClampsHorizontalOrigin() throws {
        // Mounted shorter than the block so the vertical offset below is a legitimate scroll
        // position; a document that fits its viewport is pulled back to zero.
        let mounted = makeMountedBlockInputView(
            configuration: BlockInputConfiguration(document: BlockInputDocument(blocks: [Self.longCodeBlock()])),
            size: NSSize(width: 720, height: 40)
        )
        let outerScrollView = try XCTUnwrap(mounted.view.testingOuterScrollView)

        outerScrollView.contentView.scroll(to: NSPoint(x: 48, y: 10))
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: outerScrollView.contentView)

        XCTAssertEqual(outerScrollView.contentView.bounds.origin.x, 0, accuracy: 0.5)
        XCTAssertEqual(outerScrollView.contentView.bounds.origin.y, 10, accuracy: 0.5)
    }

    func testLongSingleLineCodeHeightDoesNotWrap() {
        let singleLineHeight = BlockInputBlockItem.height(for: Self.longCodeBlock(), textWidth: 240)
        let multilineHeight = BlockInputBlockItem.height(
            for: BlockInputBlock(id: "code", kind: .code(language: nil), text: "let one = 1\nlet two = 2\nlet three = 3"),
            textWidth: 240
        )

        XCTAssertGreaterThan(multilineHeight, singleLineHeight)
    }

    func testFocusingLongCodeLineEndScrollsCaretIntoView() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.longCodeBlock()])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let scrollView = try XCTUnwrap(item.testingTextScrollView)

        item.focusText(atUTF16Offset: textView.string.utf16.count)
        item.view.layoutSubtreeIfNeeded()

        let caretX = try XCTUnwrap(item.textContainerX(forUTF16Offset: textView.string.utf16.count))
        let caretPoint = textView.convert(
            NSPoint(x: textView.textContainerOrigin.x + caretX, y: textView.textContainerOrigin.y),
            to: item.view
        )
        let viewport = item.visibleTextViewportInItemCoordinates
        XCTAssertGreaterThan(scrollView.contentView.bounds.origin.x, 0)
        XCTAssertGreaterThanOrEqual(caretPoint.x, viewport.minX - 1)
        XCTAssertLessThanOrEqual(caretPoint.x, viewport.maxX + 1)
    }

    func testCodeViewportStaysInsideBorderAfterHorizontalScroll() throws {
        let item = configuredItem(block: Self.longCodeBlock())
        let scrollView = try XCTUnwrap(item.testingTextScrollView)

        scrollView.contentView.scroll(to: NSPoint(x: 180, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        item.view.layoutSubtreeIfNeeded()

        let viewport = item.visibleTextViewportInItemCoordinates
        XCTAssertGreaterThanOrEqual(
            viewport.minX - item.testingCodeBackgroundView.frame.minX,
            -1
        )
        XCTAssertLessThanOrEqual(
            viewport.maxX,
            item.testingCodeBackgroundView.frame.maxX + 1
        )
    }

    func testPartialSelectionChromeClipsToVisibleCodeViewportAfterHorizontalScroll() throws {
        let item = configuredItem(block: Self.longCodeBlock())
        let scrollView = try XCTUnwrap(item.testingTextScrollView)
        scrollView.contentView.scroll(to: NSPoint(x: 180, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        item.setSelectionHighlightRange(NSRange(location: 10, length: 80))
        item.view.layoutSubtreeIfNeeded()

        let viewport = item.visibleTextViewportInItemCoordinates
        for frame in item.testingSelectionBackgroundSegmentFrames {
            XCTAssertGreaterThanOrEqual(frame.minX, viewport.minX - 1)
            XCTAssertLessThanOrEqual(frame.maxX, viewport.maxX + 1)
        }
    }

    func testWindowPointResolvesScrolledCodeTextOffset() throws {
        let mounted = makeMountedBlockInputView(blocks: [Self.longCodeBlock()])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let scrollView = try XCTUnwrap(item.testingTextScrollView)
        scrollView.contentView.scroll(to: NSPoint(x: 160, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        let localPoint = NSPoint(
            x: scrollView.contentView.bounds.origin.x + textView.textContainerOrigin.x + 40,
            y: textView.textContainerOrigin.y + 8
        )
        let windowPoint = textView.convert(localPoint, to: nil)
        let offset = item.utf16Offset(atWindowLocation: windowPoint)

        XCTAssertGreaterThan(offset, 0)
    }

    func testHorizontalScrollerReserveKeepsFinalCodeLineAboveScrollerOverlay() throws {
        let item = configuredItem(block: Self.longCodeBlock())
        let scrollView = try XCTUnwrap(item.testingTextScrollView)
        let textView = try XCTUnwrap(item.testingTextView)

        XCTAssertEqual(scrollView.scrollerStyle, .overlay)
        XCTAssertGreaterThanOrEqual(scrollView.contentView.bounds.height - textView.frame.height, -0.5)
        XCTAssertGreaterThanOrEqual(
            textView.frame.height,
            textView.textContainerInset.height * 2 + BlockInputBlockItem.codeHorizontalScrollerReserve
        )
    }

    private func configuredItem(
        block: BlockInputBlock,
        embeddedInVerticalScrollView: Bool = false
    ) -> BlockInputBlockItem {
        let item = BlockInputBlockItem.configuredForTesting(
            block: block,
            allowsReordering: true,
            delegate: BlockInputView()
        )
        item.view.frame = NSRect(
            x: 0,
            y: 0,
            width: 320,
            height: BlockInputBlockItem.height(for: block, textWidth: 240)
        )
        item.view.layoutSubtreeIfNeeded()
        if embeddedInVerticalScrollView {
            let parentScrollView = RecordingScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 160))
            parentScrollView.hasVerticalScroller = true
            let documentView = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 400))
            parentScrollView.documentView = documentView
            documentView.addSubview(item.view)
            item.view.layoutSubtreeIfNeeded()
        }
        return item
    }

    private static func longCodeBlock() -> BlockInputBlock {
        BlockInputBlock(id: "code", kind: .code(language: "swift"), text: "let value = \"\(Self.longText())\"")
    }

    private static func longText() -> String {
        Array(repeating: "scrollable", count: 40).joined(separator: " ")
    }

    private static func scrollEvent(
        deltaY: Int32,
        deltaX: Int32,
        modifierFlags: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        let cgEvent = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: deltaY,
            wheel2: deltaX,
            wheel3: 0
        ))
        cgEvent.flags = CGEventFlags(rawValue: UInt64(modifierFlags.rawValue))
        return try XCTUnwrap(NSEvent(cgEvent: cgEvent))
    }

    private static func preciseScrollEvent(deltaY: Int32, deltaX: Int32) throws -> NSEvent {
        let cgEvent = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: deltaY,
            wheel2: deltaX,
            wheel3: 0
        ))
        return try XCTUnwrap(NSEvent(cgEvent: cgEvent))
    }
}

private final class RecordingScrollView: NSScrollView {
    var verticalScrollCount = 0

    override func scrollWheel(with event: NSEvent) {
        verticalScrollCount += 1
    }
}

private extension BlockInputView {
    var testingOuterScrollView: NSScrollView? {
        descendants(of: NSScrollView.self).first { scrollView in
            scrollView.documentView === collectionView
        }
    }
}

private extension NSView {
    func descendants<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
        subviews.flatMap { child -> [ViewType] in
            var matches = child.descendants(of: type)
            if let typed = child as? ViewType {
                matches.insert(typed, at: 0)
            }
            return matches
        }
    }
}
