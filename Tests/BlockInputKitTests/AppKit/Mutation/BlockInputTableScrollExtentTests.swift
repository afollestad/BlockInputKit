import AppKit
import XCTest
@testable import BlockInputKit

/// Granular block replacements that change a block's measured height must refresh
/// the flow layout's delegate metrics; otherwise `collectionViewContentSize` keeps
/// the old height and the scroll range clips the block (tables were the reported
/// case: the mounted item frame grows, but the user cannot scroll to its bottom).
@MainActor
final class BlockInputTableScrollExtentTests: XCTestCase {
    func testInsertTableGrowsScrollableContentSizeToCoverTable() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "empty", text: "")
        ])
        let layout = try XCTUnwrap(mounted.view.collectionView.collectionViewLayout)
        let heightBefore = layout.collectionViewContentSize.height

        XCTAssertTrue(mounted.view.insertTable(after: "empty"))
        mounted.view.collectionView.layoutSubtreeIfNeeded()

        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let contentHeight = layout.collectionViewContentSize.height
        XCTAssertGreaterThan(contentHeight, heightBefore)
        XCTAssertGreaterThanOrEqual(contentHeight, item.view.frame.maxY - 0.5)
    }

    func testAppendTableBodyRowGrowsScrollableContentSize() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(
                id: "table",
                kind: .table,
                text: BlockInputTable.normalized(
                    header: ["H1", "H2"],
                    bodyRows: [["one", "two"]],
                    alignments: [.left, .left]
                ).markdown
            )
        ])
        let layout = try XCTUnwrap(mounted.view.collectionView.collectionViewLayout)
        _ = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let heightBefore = layout.collectionViewContentSize.height

        XCTAssertTrue(mounted.view.appendTableBodyRow(blockID: "table"))
        mounted.view.collectionView.layoutSubtreeIfNeeded()

        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let contentHeight = layout.collectionViewContentSize.height
        XCTAssertGreaterThan(contentHeight, heightBefore)
        XCTAssertGreaterThanOrEqual(contentHeight, item.view.frame.maxY - 0.5)
    }
}
