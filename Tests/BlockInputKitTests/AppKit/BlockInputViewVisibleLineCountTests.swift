import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewVisibleLineCountTests: XCTestCase {
    func testDefaultVisibleLineCountFitsThatManyRenderedLines() {
        let twoLineView = configuredView(text: "One\nTwo", defaultLines: 3, maxLines: 6, blockVerticalInsetMultiplier: 0.7)
        let threeLineView = configuredView(text: "One\nTwo\nThree", defaultLines: 3, maxLines: 6, blockVerticalInsetMultiplier: 0.7)

        XCTAssertEqual(
            threeLineView.preferredHeight(forWidth: 360),
            twoLineView.preferredHeight(forWidth: 360),
            accuracy: 0.5
        )
    }

    func testDefaultVisibleLineCountFitsThatManyParagraphRows() {
        let twoLineView = configuredView(
            blocks: [
                BlockInputBlock(id: "one", text: "One"),
                BlockInputBlock(id: "two", text: "Two")
            ],
            defaultLines: 3,
            maxLines: 6,
            blockVerticalInsetMultiplier: 0.7
        )
        let threeLineView = configuredView(
            blocks: [
                BlockInputBlock(id: "one", text: "One"),
                BlockInputBlock(id: "two", text: "Two"),
                BlockInputBlock(id: "three", text: "Three")
            ],
            defaultLines: 3,
            maxLines: 6,
            blockVerticalInsetMultiplier: 0.7
        )
        let fourLineView = configuredView(
            blocks: [
                BlockInputBlock(id: "one", text: "One"),
                BlockInputBlock(id: "two", text: "Two"),
                BlockInputBlock(id: "three", text: "Three"),
                BlockInputBlock(id: "four", text: "Four")
            ],
            defaultLines: 3,
            maxLines: 6,
            blockVerticalInsetMultiplier: 0.7
        )

        XCTAssertEqual(
            threeLineView.preferredHeight(forWidth: 360),
            twoLineView.preferredHeight(forWidth: 360),
            accuracy: 0.5
        )
        XCTAssertEqual(
            threeLineView.preferredHeight(forWidth: 360),
            expectedLineHeight(lines: 3, in: threeLineView),
            accuracy: 0.5
        )
        XCTAssertGreaterThan(
            fourLineView.preferredHeight(forWidth: 360),
            threeLineView.preferredHeight(forWidth: 360)
        )
    }

    func testLineSpacedParagraphRowsStillFitTheVisibleLineCount() {
        let spacedStyle = BlockInputStyle(baseText: BlockInputTextStyle(lineSpacing: 3))
        let blocks = (1...3).map { BlockInputBlock(id: BlockInputBlockID(rawValue: "\($0)"), text: "Line \($0)") }
        let view = configuredView(
            blocks: blocks,
            defaultLines: 3,
            maxLines: 6,
            blockVerticalInsetMultiplier: 0.7,
            style: spacedStyle
        )

        // One-line rows carry no spacing, so the reference row the visible-line height is built
        // from stays valid and three rows still fit exactly three visible lines.
        XCTAssertEqual(
            view.preferredHeight(forWidth: 360),
            expectedLineHeight(lines: 3, in: view),
            accuracy: 0.5
        )
    }

    private func configuredView(
        text: String,
        defaultLines: Int,
        maxLines: Int?,
        blockVerticalInsetMultiplier: CGFloat = 1
    ) -> BlockInputView {
        configuredView(
            blocks: [BlockInputBlock(id: "first", text: text)],
            defaultLines: defaultLines,
            maxLines: maxLines,
            blockVerticalInsetMultiplier: blockVerticalInsetMultiplier
        )
    }

    private func configuredView(
        blocks: [BlockInputBlock],
        defaultLines: Int,
        maxLines: Int?,
        blockVerticalInsetMultiplier: CGFloat = 1,
        style: BlockInputStyle = .default
    ) -> BlockInputView {
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 360, height: 200))
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: blocks),
            blockVerticalInsetMultiplier: blockVerticalInsetMultiplier,
            style: style,
            heightSizing: BlockInputEditorHeightSizing(
                defaultVisibleLineCount: defaultLines,
                maximumVisibleLineCount: maxLines
            )
        ))
        view.layoutSubtreeIfNeeded()
        return view
    }

    private func expectedLineHeight(lines: Int, in view: BlockInputView) -> CGFloat {
        let rowHeight = BlockInputBlockItem.height(
            for: BlockInputBlock(id: "expected", text: "x"),
            textWidth: 10_000,
            style: view.style,
            blockVerticalInsetMultiplier: view.blockVerticalInsetMultiplier
        )
        return ceil((rowHeight * CGFloat(lines)) + (view.editorVerticalInset * 2))
    }
}
