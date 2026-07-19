import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class SlashCommandChipSpacingTests: XCTestCase {
    func testSlashCommandsDoNotAddTrailingKern() throws {
        for testCase in unspacedCases + spacedCases {
            let item = BlockInputBlockItem.configuredForTesting(
                block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: testCase.text),
                allowsReordering: true,
                rawSlashCommandChips: testCase.rawSlashCommandChips,
                slashCommandAvailability: .anywhere,
                delegate: BlockInputView()
            )
            let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)
            let commandRange = (testCase.text as NSString).range(of: testCase.visibleCommandSource)

            XCTAssertNil(
                textStorage.attribute(.kern, at: NSMaxRange(commandRange) - 1, effectiveRange: nil),
                testCase.text
            )
            for location in 0..<textStorage.length {
                XCTAssertNil(textStorage.attribute(.kern, at: location, effectiveRange: nil), testCase.text)
            }
        }
    }

    func testLeadingWhitespaceKeepsItsSpacingWhileTrailingWhitespaceDoesNot() throws {
        for testCase in [
            SlashCommandSpacingCase(text: " /review ", visibleCommandSource: "/review", rawSlashCommandChips: true),
            SlashCommandSpacingCase(
                text: " [/review](host-app://commands/review) ",
                visibleCommandSource: "/review",
                rawSlashCommandChips: false
            )
        ] {
            let item = BlockInputBlockItem.configuredForTesting(
                block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: testCase.text),
                allowsReordering: true,
                rawSlashCommandChips: testCase.rawSlashCommandChips,
                slashCommandAvailability: .anywhere,
                delegate: BlockInputView()
            )
            let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)
            let markdownRange = try XCTUnwrap(BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
                in: testCase.text,
                rawSlashCommandChips: testCase.rawSlashCommandChips,
                slashCommandAvailability: .anywhere,
                isDocumentStartBlock: true
            ).first { $0.inlineChipKind(in: testCase.text) != nil })

            XCTAssertEqual(
                textStorage.attribute(.kern, at: markdownRange.fullRange.location - 1, effectiveRange: nil) as? CGFloat,
                5,
                testCase.text
            )
            XCTAssertNil(
                textStorage.attribute(.kern, at: NSMaxRange(markdownRange.fullRange), effectiveRange: nil),
                testCase.text
            )
        }
    }

    func testTrailingSpaceDoesNotAlterComposedCommandEndings() throws {
        for command in ["/go👩‍💻", "/cafe\u{301}"] {
            let text = "\(command) "
            let item = BlockInputBlockItem.configuredForTesting(
                block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: text),
                allowsReordering: true,
                rawSlashCommandChips: true,
                isDocumentStartBlock: true,
                delegate: BlockInputView()
            )
            let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)
            let nsCommand = command as NSString
            let finalCharacterRange = nsCommand.rangeOfComposedCharacterSequence(at: nsCommand.length - 1)

            for location in finalCharacterRange.location..<NSMaxRange(finalCharacterRange) {
                XCTAssertNil(textStorage.attribute(.kern, at: location, effectiveRange: nil), command)
            }
        }
    }

    func testLinkBackedSpacingDoesNotKernVisibleOrHiddenEscapedSource() throws {
        let text = #"Run [/review\]](host-app://commands/review\(x\)) "#
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: text),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)
        let visibleClosingBracket = (text as NSString).range(of: #"\]]"#).location + 1
        let destinationOffset = (text as NSString).range(of: "host-app://").location
        let trailingSpaceOffset = (text as NSString).length - 1

        XCTAssertNil(textStorage.attribute(.kern, at: visibleClosingBracket, effectiveRange: nil))
        XCTAssertNil(textStorage.attribute(.kern, at: visibleClosingBracket - 1, effectiveRange: nil))
        XCTAssertNil(textStorage.attribute(.kern, at: destinationOffset, effectiveRange: nil))
        XCTAssertNil(textStorage.attribute(.kern, at: trailingSpaceOffset, effectiveRange: nil))
    }

    func testLinkBackedLiteralSeparatorStaysOutsideChipHitGeometry() throws {
        let text = "[/review](host-app://commands/review) "
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "paragraph", kind: .paragraph, text: text)
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let backgroundRect = try XCTUnwrap(textView.inlineChipBackgroundRectsForTesting().only)
        let separatorEndX = try XCTUnwrap(item.textContainerX(forUTF16Offset: (text as NSString).length))
        let separatorPoint = NSPoint(
            x: textView.textContainerOrigin.x + separatorEndX - 0.25,
            y: backgroundRect.midY
        )
        let windowPoint = textView.convert(separatorPoint, to: nil)

        XCTAssertNil(textView.inlineChipRange(atWindowLocation: windowPoint))
    }

    func testLiteralSeparatorDoesNotExpandSlashCommandGeometry() throws {
        for testCase in [
            SlashCommandGeometryCase(
                bareText: "/review",
                spacedText: "/review ",
                rawSlashCommandChips: true
            ),
            SlashCommandGeometryCase(
                bareText: "[/review](host-app://commands/review)",
                spacedText: "[/review](host-app://commands/review) ",
                rawSlashCommandChips: false
            )
        ] {
            let bareRect = try slashCommandRect(
                text: testCase.bareText,
                rawSlashCommandChips: testCase.rawSlashCommandChips
            )
            let spacedRect = try slashCommandRect(
                text: testCase.spacedText,
                rawSlashCommandChips: testCase.rawSlashCommandChips
            )

            XCTAssertEqual(spacedRect, bareRect, testCase.bareText)
        }
    }

    func testReconfiguringSlashCommandClearsStaleTrailingFileChipKern() throws {
        let fileSource = "[file](file:///tmp/demo.md)"
        let fileText = "\(fileSource) "
        let rawCommand = "/" + String(repeating: "r", count: (fileSource as NSString).length - 1)
        let rawText = "\(rawCommand) "
        XCTAssertEqual((rawText as NSString).length, (fileText as NSString).length)

        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: fileText),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        var textStorage = try XCTUnwrap(item.testingTextView?.textStorage)
        let trailingSpaceOffset = textStorage.length - 1
        XCTAssertEqual(textStorage.attribute(.kern, at: trailingSpaceOffset, effectiveRange: nil) as? CGFloat, 5)

        item.configure(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: rawText),
            allowsReordering: true,
            rawSlashCommandChips: true,
            slashCommandAvailability: .anywhere,
            delegate: BlockInputView()
        )

        textStorage = try XCTUnwrap(item.testingTextView?.textStorage)
        XCTAssertNotNil(textStorage.attribute(.blockInputInlineChip, at: 0, effectiveRange: nil))
        XCTAssertNil(textStorage.attribute(.kern, at: trailingSpaceOffset, effectiveRange: nil))
    }

    func testFileChipWhitespaceSpacingRemainsUnchanged() throws {
        let text = " [README.md](file:///tmp/README.md) "
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: text),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)

        XCTAssertEqual(textStorage.attribute(.kern, at: 0, effectiveRange: nil) as? CGFloat, 5)
        XCTAssertEqual(textStorage.attribute(.kern, at: textStorage.length - 1, effectiveRange: nil) as? CGFloat, 5)
    }

    private func slashCommandRect(text: String, rawSlashCommandChips: Bool) throws -> NSRect {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "paragraph", kind: .paragraph, text: text)
            ]),
            rawSlashCommandChips: rawSlashCommandChips,
            slashCommandAvailability: .anywhere
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        return try XCTUnwrap(textView.inlineChipBackgroundRectsForTesting().only)
    }

    private var unspacedCases: [SlashCommandSpacingCase] {
        [
            SlashCommandSpacingCase(text: "/effo", visibleCommandSource: "/effo", rawSlashCommandChips: true),
            SlashCommandSpacingCase(text: "/review", visibleCommandSource: "/review", rawSlashCommandChips: true),
            SlashCommandSpacingCase(
                text: "[/effo](host-app://commands/effo)",
                visibleCommandSource: "/effo",
                rawSlashCommandChips: false
            ),
            SlashCommandSpacingCase(
                text: "[/review](host-app://commands/review)",
                visibleCommandSource: "/review",
                rawSlashCommandChips: false
            )
        ]
    }

    private var spacedCases: [SlashCommandSpacingCase] {
        [
            SlashCommandSpacingCase(text: "/review ", visibleCommandSource: "/review", rawSlashCommandChips: true),
            SlashCommandSpacingCase(text: "/review   ", visibleCommandSource: "/review", rawSlashCommandChips: true),
            SlashCommandSpacingCase(
                text: "[/review](host-app://commands/review) ",
                visibleCommandSource: "/review",
                rawSlashCommandChips: false
            )
        ]
    }
}

private struct SlashCommandSpacingCase {
    let text: String
    let visibleCommandSource: String
    let rawSlashCommandChips: Bool
}

private struct SlashCommandGeometryCase {
    let bareText: String
    let spacedText: String
    let rawSlashCommandChips: Bool
}

private extension Array {
    var only: Element? {
        count == 1 ? first : nil
    }
}
