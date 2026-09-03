import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputTableCellSelectionTests: XCTestCase {
    func testTypingInCellClearsWholeTableSelectionChrome() throws {
        let emptyCellTable = Self.tableBlock(bodyRows: [["", "two"]])
        let mounted = makeMountedBlockInputView(blocks: [emptyCellTable])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        mounted.view.applySelection(.blocks(["table"]), notify: true)
        XCTAssertFalse(item.testingSelectionBackgroundView.isHidden)

        let cell = try bodyCell(in: item, row: 0, column: 0)
        XCTAssertTrue(mounted.window.makeFirstResponder(cell))
        cell.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertEqual(
            mounted.view.selection,
            emptyCellTable.blockInputTableSelection(
                position: .init(row: .body(0), column: 0),
                localRange: NSRange(location: 0, length: 0)
            )
        )
        cell.insertText("A", replacementRange: cell.selectedRange())

        XCTAssertEqual(
            mounted.view.selection,
            BlockInputTable.normalized(
                header: ["H1", "H2"],
                bodyRows: [["A", "two"]],
                alignments: [.left, .left]
            )
            .selection(blockID: "table", position: .init(row: .body(0), column: 0), localRange: NSRange(location: 1, length: 0))
        )
        waitForNextMainLoopTurn()
        XCTAssertTrue(item.testingSelectionBackgroundView.isHidden)
    }

    private func bodyCell(in item: BlockInputBlockItem, row: Int, column: Int) throws -> BlockInputTableCellTextView {
        let index = (row + 1) * 2 + column
        return try XCTUnwrap(item.testingTableCellTextViews.indices.contains(index) ? item.testingTableCellTextViews[index] : nil)
    }

    private static func tableBlock(bodyRows: [[String]]) -> BlockInputBlock {
        BlockInputBlock(
            id: "table",
            kind: .table,
            text: BlockInputTable.normalized(
                header: ["H1", "H2"],
                bodyRows: bodyRows,
                alignments: [.left, .left]
            ).markdown
        )
    }
}

private extension BlockInputBlock {
    func blockInputTableSelection(
        position: BlockInputTable.CellPosition,
        localRange: NSRange
    ) -> BlockInputSelection? {
        BlockInputTable(markdown: text)?.selection(blockID: id, position: position, localRange: localRange)
    }
}
