import AppKit
import XCTest
@testable import BlockInputKit

extension BlockInputViewNarrowResizeTests {
    func testWrappedRowsStaySeparatedAfterOpeningScrollingAndResizing() async throws {
        for scrollerStyle in [NSScroller.Style.legacy, .overlay] {
            let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 572, height: 480))
            view.scrollView.scrollerStyle = scrollerStyle
            view.configure(BlockInputConfiguration(document: Self.reflowDocument, allowsBlockReordering: false))
            let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = view
            defer { window.contentView = nil }

            for width in [CGFloat(572), 672, 572] {
                if window.contentView?.bounds.width != width {
                    window.setContentSize(NSSize(width: width, height: 480))
                }
                await settleReflow(view, window: window)
                let maximumOffset = max(0, view.collectionView.frame.height - view.scrollView.contentView.bounds.height)
                let offsets = Array(stride(from: 0.0, through: maximumOffset, by: 120)) + [maximumOffset, 0]
                for offset in offsets {
                    view.scrollView.contentView.scroll(to: NSPoint(x: 0, y: offset))
                    view.scrollView.reflectScrolledClipView(view.scrollView.contentView)
                    await settleReflow(view, window: window)
                    try assertVisibleRowsFit(view, context: "width \(width), scroller \(scrollerStyle), offset \(offset)")
                }
            }
        }
    }

    func testWidthReflowPreservesMountedSelectionAndScrollOffset() async throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: Self.reflowDocument,
            allowsBlockReordering: false
        ), size: NSSize(width: 572, height: 480))
        defer { mounted.window.contentView = nil }
        await settleReflow(mounted.view, window: mounted.window)
        mounted.view.scrollView.contentView.scroll(to: NSPoint(x: 0, y: 80))
        await settleReflow(mounted.view, window: mounted.window)
        let item = try XCTUnwrap(mounted.view.collectionView.item(at: IndexPath(item: 2, section: 0)) as? BlockInputBlockItem)
        let selection = NSRange(location: 5, length: 8)
        XCTAssertTrue(mounted.window.makeFirstResponder(item.textView))
        item.textView.setSelectedRange(selection)
        let offset = mounted.view.scrollView.contentView.bounds.origin

        // Only the final width should reach the deferred reconciliation.
        mounted.window.setContentSize(NSSize(width: 672, height: 480))
        mounted.view.layoutSubtreeIfNeeded()
        mounted.window.setContentSize(NSSize(width: 620, height: 480))
        await settleReflow(mounted.view, window: mounted.window)

        XCTAssertTrue(mounted.view.collectionView.item(at: IndexPath(item: 2, section: 0)) === item)
        XCTAssertTrue(mounted.window.firstResponder === item.textView)
        XCTAssertEqual(item.textView.selectedRange(), selection)
        XCTAssertEqual(mounted.view.scrollView.contentView.bounds.origin, offset)
        try assertVisibleRowsFit(mounted.view, context: "Coalesced width changes")
    }

    private func settleReflow(_ view: BlockInputView, window: NSWindow) async {
        // Width reconciliation can schedule another pass when a legacy scrollbar appears.
        for _ in 0..<4 {
            view.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    private func assertVisibleRowsFit(_ view: BlockInputView, context: String) throws {
        let items = view.collectionView.visibleItems().compactMap { $0 as? BlockInputBlockItem }.sorted {
            $0.view.frame.minY < $1.view.frame.minY
        }
        XCTAssertFalse(items.isEmpty, context)
        for item in items {
            let indexPath = try XCTUnwrap(view.collectionView.indexPath(for: item))
            let attributes = try XCTUnwrap(view.layout.layoutAttributesForItem(at: indexPath))
            XCTAssertEqual(attributes.frame.width, item.view.frame.width, accuracy: 0.5, context)
            let block = try XCTUnwrap(item.renderedBlock)
            let textContainer = try XCTUnwrap(item.textView.textContainer)
            let layoutManager = try XCTUnwrap(item.textView.layoutManager)
            layoutManager.ensureLayout(for: textContainer)
            let metrics = BlockInputBlockItem.verticalMetrics(for: block)
            let renderedHeight = ceil(layoutManager.usedRect(for: textContainer).maxY)
                + metrics.topContentInset + metrics.bottomContentInset
            XCTAssertLessThanOrEqual(renderedHeight, item.view.frame.height + 0.5, context)
        }
        for (previous, next) in zip(items, items.dropFirst()) {
            XCTAssertLessThanOrEqual(previous.view.frame.maxY, next.view.frame.minY + 0.5, context)
        }
    }

    private static var reflowDocument: BlockInputDocument {
        let bullets = [
            "Check correctness, security, performance, readability, and maintainability. Comment on the changed lines, "
                + "not pre-existing code, unless the change breaks it.",
            "Only include actionable findings that point at a specific problem or concrete suggestion, framed as a question "
                + "where that reads naturally. No praise, no \"looks good\" filler: a comment that is not actionable is omitted "
                + "entirely, not softened.",
            "Decide deliberately whether each minor finding earns a comment; note in your reply any you considered and "
                + "left out rather than dropping them silently."
        ]
        return BlockInputDocument(blocks: (0..<6).flatMap { section in
            [BlockInputBlock(kind: .heading(level: 2), text: "Section \(section)")]
                + bullets.map { BlockInputBlock(kind: .bulletedListItem, text: $0) }
        })
    }
}
