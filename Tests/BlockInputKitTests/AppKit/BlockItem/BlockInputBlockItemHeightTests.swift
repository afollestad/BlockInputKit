import XCTest
@testable import BlockInputKit

final class BlockInputBlockItemHeightTests: XCTestCase {
    @MainActor
    func testHeightMeasurementCollapsesInlineMarkdownDelimiters() {
        let plainBlock = BlockInputBlock(kind: .paragraph, text: "underlined text")
        let underlinedBlock = BlockInputBlock(kind: .paragraph, text: "<ins>underlined text</ins>")

        XCTAssertEqual(
            BlockInputBlockItem.height(for: underlinedBlock, textWidth: 120),
            BlockInputBlockItem.height(for: plainBlock, textWidth: 120),
            accuracy: 0.5
        )
    }

    @MainActor
    func testHeightMeasurementCollapsesRelativeFileLinkDelimitersWhenBaseURLIsConfigured() {
        let plainBlock = BlockInputBlock(kind: .paragraph, text: "Read docs")
        let linkBlock = BlockInputBlock(kind: .paragraph, text: "Read [docs](assets/README.md)")
        let baseURL = URL(fileURLWithPath: "/tmp/project", isDirectory: true)

        XCTAssertEqual(
            BlockInputBlockItem.height(for: linkBlock, textWidth: 120, fileBaseURL: baseURL),
            BlockInputBlockItem.height(for: plainBlock, textWidth: 120),
            accuracy: 0.5
        )
    }

    @MainActor
    func testHeightMeasurementMatchesMountedSlashCommandChipMetricsNearWrapBoundary() throws {
        try assertSlashCommandHeightParity(
            text: "/review-github-pr ",
            rawSlashCommandChips: true
        )
        try assertSlashCommandHeightParity(
            text: "[/review-github-pr](host-app://commands/review-github-pr) ",
            rawSlashCommandChips: false
        )
    }

    @MainActor
    private func assertSlashCommandHeightParity(
        text: String,
        rawSlashCommandChips: Bool
    ) throws {
        let block = BlockInputBlock(kind: .paragraph, text: text)
        let narrowWidth: CGFloat = 120
        let measuredHeight = BlockInputBlockItem.height(
            for: block,
            textWidth: narrowWidth,
            rawSlashCommandChips: rawSlashCommandChips,
            isDocumentStartBlock: true
        )
        let item = BlockInputBlockItem.configuredForTesting(
            block: block,
            allowsReordering: false,
            rawSlashCommandChips: rawSlashCommandChips,
            isDocumentStartBlock: true,
            delegate: BlockInputView()
        )
        let textView = try XCTUnwrap(item.testingTextView)
        let textContainer = try XCTUnwrap(textView.textContainer)
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        textContainer.widthTracksTextView = false
        textContainer.containerSize.width = narrowWidth
        textContainer.lineFragmentPadding = 0
        layoutManager.invalidateLayout(
            forCharacterRange: NSRange(location: 0, length: (textView.string as NSString).length),
            actualCharacterRange: nil
        )
        layoutManager.ensureLayout(for: textContainer)
        let renderedTextHeight = ceil(layoutManager.usedRect(for: textContainer).height)
        let requiredRowHeight = renderedTextHeight + (textView.textContainerInset.height * 2) + 2

        XCTAssertGreaterThan(renderedTextHeight, 20)
        XCTAssertGreaterThanOrEqual(measuredHeight, requiredRowHeight, text)
    }

    /// The mounted text container has to wrap exactly where the offscreen measurement
    /// said it would. Only some widths resize the text view during layout, so a container
    /// that disagreed with the measurement stayed hidden until a row landed in that band
    /// and rendered a line the measured height had no room for.
    @MainActor
    func testMeasuredHeightCoversMountedRenderingAcrossWrapBoundaries() throws {
        let block = BlockInputBlock(
            kind: .numberedListItem(start: 3),
            text: "Call `read_diff` to read the diff, paging with offset until every file has been read. "
                + "Judge the change as a whole before commenting on any one of them."
        )
        let metrics = BlockInputBlockItem.verticalMetrics(for: block)

        // Rows narrower than roughly 180 measure against `height(for:textWidth:)`'s 120-point
        // floor rather than their real viewport, so they under-report by design; sweep the
        // widths an editor actually renders at.
        for itemWidth in stride(from: 320.0, through: 720.0, by: 2.0) {
            let measuredHeight = BlockInputBlockItem.height(
                for: block,
                textWidth: BlockInputBlockItem.measuredTextWidth(
                    for: itemWidth,
                    block: block,
                    allowsReordering: false
                )
            )
            let item = BlockInputBlockItem.configuredForTesting(
                block: block,
                allowsReordering: false,
                delegate: BlockInputView()
            )
            item.view.frame = NSRect(x: 0, y: 0, width: itemWidth, height: measuredHeight)
            item.view.layoutSubtreeIfNeeded()
            let textView = try XCTUnwrap(item.testingTextView)
            let textContainer = try XCTUnwrap(textView.textContainer)
            let layoutManager = try XCTUnwrap(textView.layoutManager)
            layoutManager.ensureLayout(for: textContainer)
            let renderedHeight = ceil(layoutManager.usedRect(for: textContainer).maxY)
                + metrics.topContentInset
                + metrics.bottomContentInset

            XCTAssertLessThanOrEqual(renderedHeight, measuredHeight, "item width \(itemWidth)")
        }
    }

    @MainActor
    func testListHeightAccountsForIndentedTextWidth() {
        let text = Array(repeating: "Wrapped list content", count: 8).joined(separator: " ")
        let itemWidth: CGFloat = 260
        let rootBlock = BlockInputBlock(kind: .bulletedListItem, text: text)
        let indentedBlock = BlockInputBlock(kind: .bulletedListItem, text: text, indentationLevel: 3)
        let rootTextWidth = BlockInputBlockItem.measuredTextWidth(
            for: itemWidth,
            block: rootBlock,
            allowsReordering: true
        )
        let indentedTextWidth = BlockInputBlockItem.measuredTextWidth(
            for: itemWidth,
            block: indentedBlock,
            allowsReordering: true
        )
        let rootHeight = BlockInputBlockItem.height(for: rootBlock, textWidth: rootTextWidth)
        let indentedHeight = BlockInputBlockItem.height(for: indentedBlock, textWidth: indentedTextWidth)

        XCTAssertGreaterThan(indentedHeight, rootHeight)
    }

    @MainActor
    func testListHeightAccountsForPerLineIndentedTextWidth() {
        let text = "Short\n" + Array(repeating: "Wrapped list content", count: 12).joined(separator: " ")
        let itemWidth: CGFloat = 320
        let rootBlock = BlockInputBlock(kind: .bulletedListItem, text: text)
        let indentedBlock = BlockInputBlock(
            kind: .bulletedListItem,
            text: text,
            lineIndentationLevels: [0, 3, 1]
        )
        let rootTextWidth = BlockInputBlockItem.measuredTextWidth(
            for: itemWidth,
            block: rootBlock,
            allowsReordering: true
        )
        let indentedTextWidth = BlockInputBlockItem.measuredTextWidth(
            for: itemWidth,
            block: indentedBlock,
            allowsReordering: true
        )
        let rootHeight = BlockInputBlockItem.height(for: rootBlock, textWidth: rootTextWidth)
        let indentedHeight = BlockInputBlockItem.height(for: indentedBlock, textWidth: indentedTextWidth)

        XCTAssertGreaterThan(indentedHeight, rootHeight)
    }

    @MainActor
    func testBlockVerticalInsetMultiplierReducesAllBlockFamiliesWithoutChangingDefault() {
        let blocks: [BlockInputBlock] = [
            BlockInputBlock(kind: .paragraph, text: "Paragraph"),
            BlockInputBlock(kind: .heading(level: 2), text: "Heading"),
            BlockInputBlock(kind: .code(language: nil), text: "let value = 1"),
            BlockInputBlock(kind: .horizontalRule),
            BlockInputBlock(kind: .frontMatter, text: "title: Test"),
            BlockInputBlock(kind: .quote, text: "Quote"),
            BlockInputBlock(kind: .bulletedListItem, text: "List"),
            BlockInputBlock(kind: .numberedListItem(start: 1), text: "List"),
            BlockInputBlock(kind: .checklistItem(isChecked: false), text: "Task"),
            BlockInputBlock(kind: .table, text: """
            | A | B |
            | --- | --- |
            | 1 | 2 |
            """),
            BlockInputBlock(kind: .image(BlockInputImage(source: "image.png", width: 200, height: 100))),
            BlockInputBlock(kind: .rawMarkdown, text: "<div>Raw</div>")
        ]

        for block in blocks {
            let defaultHeight = BlockInputBlockItem.height(for: block, textWidth: 360)
            let explicitDefaultHeight = BlockInputBlockItem.height(
                for: block,
                textWidth: 360,
                blockVerticalInsetMultiplier: 1
            )
            let compactHeight = BlockInputBlockItem.height(
                for: block,
                textWidth: 360,
                blockVerticalInsetMultiplier: 0.5
            )
            let zeroHeight = BlockInputBlockItem.height(
                for: block,
                textWidth: 360,
                blockVerticalInsetMultiplier: 0
            )

            XCTAssertEqual(explicitDefaultHeight, defaultHeight, accuracy: 0.5, "Default changed for \(block.kind)")
            XCTAssertLessThan(compactHeight, defaultHeight, "Compact multiplier did not reduce \(block.kind)")
            XCTAssertGreaterThan(zeroHeight, 0, "Zero multiplier collapsed \(block.kind)")
        }
    }

    @MainActor
    func testMountedTextViewReceivesScaledVerticalInsetWithoutChangingHorizontalInset() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(kind: .paragraph, text: "Paragraph"),
            allowsReordering: true,
            blockVerticalInsetMultiplier: 0.5,
            delegate: BlockInputView()
        )
        let textView = try XCTUnwrap(item.testingTextView)

        XCTAssertEqual(textView.textContainerInset.width, BlockInputBlockItem.textBlockTextContainerInset.width)
        XCTAssertEqual(textView.textContainerInset.height, BlockInputBlockItem.textBlockTextContainerInset.height * 0.5)
    }
}
