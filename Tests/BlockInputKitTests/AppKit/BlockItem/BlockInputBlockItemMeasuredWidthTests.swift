import XCTest
@testable import BlockInputKit

final class BlockInputBlockItemMeasuredWidthTests: XCTestCase {
    @MainActor
    func testMeasuredTextWidthMatchesMountedScrollWidthForRowsWithChrome() throws {
        for allowsReordering in [true, false] {
            for block in Self.wrappingBlocks {
                let item = configuredItem(block: block, allowsReordering: allowsReordering)
                let scrollView = try XCTUnwrap(item.testingTextScrollView)
                let expectedScrollWidth = BlockInputBlockItem.textScrollViewWidth(
                    for: item.view.bounds.width,
                    block: block,
                    allowsReordering: allowsReordering
                )
                let expectedMeasuredWidth = expectedScrollWidth - 2 * BlockInputBlockItem.textContainerContentLeading

                XCTAssertEqual(scrollView.frame.width, expectedScrollWidth, accuracy: 0.5, "\(block.kind)")
                XCTAssertEqual(
                    BlockInputBlockItem.measuredTextWidth(
                        for: item.view.bounds.width,
                        block: block,
                        allowsReordering: allowsReordering
                    ),
                    expectedMeasuredWidth,
                    accuracy: 0.5,
                    "\(block.kind)"
                )
            }
        }
    }

    @MainActor
    func testMeasuredTextWidthMatchesMountedTextContainerLineFragmentWidth() throws {
        for allowsReordering in [true, false] {
            for block in Self.wrappingBlocks {
                let item = configuredItem(block: block, allowsReordering: allowsReordering)
                let textView = try XCTUnwrap(item.testingTextView)
                let textContainer = try XCTUnwrap(textView.textContainer)
                let mountedLineFragmentWidth = max(
                    textContainer.containerSize.width - 2 * textContainer.lineFragmentPadding,
                    1
                )

                XCTAssertEqual(
                    BlockInputBlockItem.measuredTextWidth(
                        for: item.view.bounds.width,
                        block: block,
                        allowsReordering: allowsReordering
                    ),
                    mountedLineFragmentWidth,
                    accuracy: 0.5,
                    "\(block.kind)"
                )
            }
        }
    }

    @MainActor
    func testNarrowWrappingRowsKeepTextViewportInsideItemBounds() throws {
        for block in Self.wrappingBlocks {
            let item = configuredItem(block: block, allowsReordering: true, width: 32)
            let scrollView = try XCTUnwrap(item.testingTextScrollView)
            let textView = try XCTUnwrap(item.testingTextView)
            let textContainer = try XCTUnwrap(textView.textContainer)
            let mountedLineFragmentWidth = max(
                textContainer.containerSize.width - 2 * textContainer.lineFragmentPadding,
                1
            )

            XCTAssertGreaterThanOrEqual(scrollView.frame.minX, item.view.bounds.minX - 0.5, "\(block.kind)")
            XCTAssertLessThanOrEqual(scrollView.frame.maxX, item.view.bounds.maxX + 0.5, "\(block.kind)")
            XCTAssertGreaterThan(mountedLineFragmentWidth, 0, "\(block.kind)")
            XCTAssertGreaterThan(
                BlockInputBlockItem.measuredTextWidth(
                    for: item.view.bounds.width,
                    block: block,
                    allowsReordering: true
                ),
                0,
                "\(block.kind)"
            )
        }
    }

    @MainActor
    func testReusedNarrowWrappingRowsDoNotKeepWideGutterConstraints() throws {
        let item = configuredItem(block: Self.wrappingBlocks[0], allowsReordering: true, width: 420)
        item.prepareForReuse()
        item.configure(
            block: Self.wrappingBlocks[1],
            allowsReordering: true,
            delegate: BlockInputView()
        )
        item.view.frame = NSRect(x: 0, y: 0, width: 32, height: 60)
        item.view.layoutSubtreeIfNeeded()
        let scrollView = try XCTUnwrap(item.testingTextScrollView)

        XCTAssertGreaterThanOrEqual(scrollView.frame.minX, item.view.bounds.minX - 0.5)
        XCTAssertLessThanOrEqual(scrollView.frame.maxX, item.view.bounds.maxX + 0.5)
    }

    private static let wrappingBlocks = [
        BlockInputBlock(id: "paragraph", kind: .paragraph, text: "Plain"),
        BlockInputBlock(id: "heading", kind: .heading(level: 2), text: "Heading"),
        BlockInputBlock(id: "bullet", kind: .bulletedListItem, text: "Bullet"),
        BlockInputBlock(id: "indentedBullet", kind: .bulletedListItem, text: "Indented", indentationLevel: 2),
        BlockInputBlock(id: "checklist", kind: .checklistItem(isChecked: false), text: "Task"),
        BlockInputBlock(id: "quote", kind: .quote, text: "Quoted")
    ]

    @MainActor
    private func configuredItem(
        block: BlockInputBlock,
        allowsReordering: Bool,
        width: CGFloat = 420
    ) -> BlockInputBlockItem {
        let item = BlockInputBlockItem.configuredForTesting(
            block: block,
            allowsReordering: allowsReordering,
            delegate: BlockInputView()
        )
        item.view.frame = NSRect(x: 0, y: 0, width: width, height: 60)
        item.view.layoutSubtreeIfNeeded()
        return item
    }
}
