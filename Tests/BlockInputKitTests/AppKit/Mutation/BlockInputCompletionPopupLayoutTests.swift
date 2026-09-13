import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputCompletionPopupLayoutTests: XCTestCase {
    func testPopupRowGivesDetailTextEnoughWidth() async throws {
        let provider = PopupCompletionProvider(suggestions: [
            .slashCommand(
                id: "heading",
                title: "Heading",
                uri: "demo://heading",
                label: "heading",
                detailText: "Command"
            )
        ])
        let mounted = try await startCompletion(text: "/", provider: provider)
        let popup = try XCTUnwrap(mounted.view.completionPopupView)
        popup.layoutSubtreeIfNeeded()

        let row = try rowView(label: "Heading, Command", in: popup)
        let detailField = try textField(label: "Command", in: row)

        XCTAssertGreaterThanOrEqual(detailField.frame.width, ceil(detailField.intrinsicContentSize.width) + 4)
        XCTAssertEqual(detailField.lineBreakMode, .byTruncatingTail)
    }

    func testPopupUsesConfiguredStyle() async throws {
        let provider = PopupCompletionProvider(suggestions: [
            .fileLink(label: "README.md", fileURL: URL(fileURLWithPath: "/tmp/README.md"))
        ])
        let style = BlockInputCompletionPopupStyle(
            backgroundColor: .systemRed,
            borderColor: .systemBlue,
            highlightedRowBackgroundColor: .systemGreen,
            highlightedRowCornerRadius: 9,
            cornerRadius: 14,
            borderWidth: 2
        )
        let mounted = try await startCompletion(text: "@read", provider: provider, popupStyle: style)
        let popup = try XCTUnwrap(mounted.view.completionPopupView)

        XCTAssertEqual(popup.popupStyleForTesting.backgroundColor, .systemRed)
        XCTAssertEqual(popup.popupStyleForTesting.borderColor, .systemBlue)
        XCTAssertEqual(popup.popupStyleForTesting.highlightedRowBackgroundColor, .systemGreen)
        XCTAssertEqual(popup.popupStyleForTesting.highlightedRowCornerRadius, 9)
        XCTAssertEqual(popup.popupStyleForTesting.cornerRadius, 14)
        XCTAssertEqual(popup.popupStyleForTesting.borderWidth, 2)
    }

    func testPopupRowUsesDefaultHighlightedRowCornerRadiusFromPopupRadius() async throws {
        let provider = PopupCompletionProvider(suggestions: [
            .fileLink(label: "README.md", fileURL: URL(fileURLWithPath: "/tmp/README.md"))
        ])
        let style = BlockInputCompletionPopupStyle(cornerRadius: 13)
        let mounted = try await startCompletion(text: "@read", provider: provider, popupStyle: style)
        let popup = try XCTUnwrap(mounted.view.completionPopupView)
        popup.layoutSubtreeIfNeeded()

        let row = try XCTUnwrap(rowView(label: "README.md", in: popup) as? BlockInputCompletionPopupRowView)

        XCTAssertEqual(row.highlightedRowCornerRadiusForTesting, 13)
    }

    func testPopupRowUsesConfiguredHighlightedRowCornerRadius() async throws {
        let provider = PopupCompletionProvider(suggestions: [
            .fileLink(label: "README.md", fileURL: URL(fileURLWithPath: "/tmp/README.md"))
        ])
        let style = BlockInputCompletionPopupStyle(highlightedRowCornerRadius: 4, cornerRadius: 13)
        let mounted = try await startCompletion(text: "@read", provider: provider, popupStyle: style)
        let popup = try XCTUnwrap(mounted.view.completionPopupView)
        popup.layoutSubtreeIfNeeded()

        let row = try XCTUnwrap(rowView(label: "README.md", in: popup) as? BlockInputCompletionPopupRowView)

        XCTAssertEqual(row.highlightedRowCornerRadiusForTesting, 4)
    }

    func testPopupUpdatesStyleWithoutRebuildingRowsWhenStateIsUnchanged() throws {
        let state = BlockInputCompletionPopupState(
            suggestions: [.fileLink(label: "README.md", fileURL: URL(fileURLWithPath: "/tmp/README.md"))],
            highlightedIndex: 0,
            isLoading: false
        )
        let popup = BlockInputCompletionPopupView(frame: NSRect(x: 0, y: 0, width: 320, height: 80))
        popup.configure(
            state: BlockInputCompletionPopupState(suggestions: [], highlightedIndex: 0, isLoading: false),
            style: .default,
            onSelect: { _ in },
            onHighlight: { _ in }
        )
        let visibleLabels = popup.subviews.compactMap { $0 as? NSTextField }.filter { !$0.isHidden }.map(\.stringValue)
        XCTAssertEqual(visibleLabels, ["No matches"])
        let indicator = try XCTUnwrap(popup.subviews.compactMap { $0 as? NSProgressIndicator }.first)
        XCTAssertTrue(indicator.isHidden)

        popup.configure(state: state, style: .default, onSelect: { _ in }, onHighlight: { _ in })
        popup.layoutSubtreeIfNeeded()
        let originalRow = try rowView(label: "README.md", in: popup)

        popup.configure(
            state: state,
            style: BlockInputCompletionPopupStyle(backgroundColor: .systemRed),
            onSelect: { _ in },
            onHighlight: { _ in }
        )

        XCTAssertTrue(try rowView(label: "README.md", in: popup) === originalRow)
        XCTAssertEqual(popup.popupStyleForTesting.backgroundColor, .systemRed)
    }

    private func startCompletion(
        text: String,
        provider: any BlockInputCompletionProvider,
        popupStyle: BlockInputCompletionPopupStyle = .default
    ) async throws -> (view: BlockInputView, window: NSWindow) {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: text)
            ]),
            completionProvider: provider,
            completionPopupConfiguration: BlockInputCompletionPopupConfiguration(style: popupStyle)
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        mounted.view.refreshCompletionSession(item: item, blockID: "block")
        await mounted.view.completionRequestTask?.value
        mounted.view.layoutSubtreeIfNeeded()
        return mounted
    }

    private func rowView(label: String, in popup: NSView) throws -> NSView {
        try XCTUnwrap(popup.subviews.first { $0.accessibilityLabel() == label })
    }

    private func textField(label: String, in row: NSView) throws -> NSTextField {
        try XCTUnwrap(row.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue == label })
    }
}
