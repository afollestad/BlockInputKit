import AppKit
import XCTest
@testable import BlockInputKit

final class BlockInputInlineMarkdownFormattingTests: XCTestCase {
    @MainActor
    func testInlineMarkdownStylesSupportedTextBlocks() throws {
        let supportedKinds: [BlockInputBlockKind] = [
            .paragraph,
            .heading(level: 2),
            .quote,
            .bulletedListItem,
            .numberedListItem(start: 1),
            .checklistItem(isChecked: false)
        ]

        for kind in supportedKinds {
            let item = BlockInputBlockItem.configuredForTesting(
                block: BlockInputBlock(id: BlockInputBlockID(rawValue: "\(kind)"), kind: kind, text: "*some text*"),
                allowsReordering: true,
                delegate: BlockInputView()
            )
            let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)
            let styledFont = try font(at: 1, in: textStorage)
            let delimiterFont = try font(at: 0, in: textStorage)

            XCTAssertTrue(styledFont.fontDescriptor.symbolicTraits.contains(.italic), "Expected italic styling for \(kind).")
            XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .clear)
            XCTAssertLessThan(delimiterFont.pointSize, styledFont.pointSize)
            XCTAssertEqual(item.testingTextView?.string, "*some text*")
        }
    }

    @MainActor
    func testInlineMarkdownAppliesEachSupportedStyle() throws {
        let text = "*italic text* **bold text** <u>underlined text</u> <ins>inserted text</ins> ~~struck text~~"
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: text),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)

        XCTAssertTrue(try font(at: contentLocation("italic text", in: text), in: textStorage).fontDescriptor.symbolicTraits.contains(.italic))
        XCTAssertTrue(try font(at: contentLocation("bold text", in: text), in: textStorage).fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertEqual(
            textStorage.attribute(.underlineStyle, at: contentLocation("underlined text", in: text), effectiveRange: nil) as? Int,
            NSUnderlineStyle.single.rawValue
        )
        XCTAssertEqual(
            textStorage.attribute(.underlineStyle, at: contentLocation("inserted text", in: text), effectiveRange: nil) as? Int,
            NSUnderlineStyle.single.rawValue
        )
        XCTAssertEqual(
            textStorage.attribute(.strikethroughStyle, at: contentLocation("struck text", in: text), effectiveRange: nil) as? Int,
            NSUnderlineStyle.single.rawValue
        )
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .clear)
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 14, effectiveRange: nil) as? NSColor, .clear)
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 28, effectiveRange: nil) as? NSColor, .clear)
        XCTAssertEqual(
            textStorage.attribute(.foregroundColor, at: (text as NSString).range(of: "<ins>").location, effectiveRange: nil) as? NSColor,
            .clear
        )
        XCTAssertEqual(
            textStorage.attribute(.foregroundColor, at: (text as NSString).range(of: "~~").location, effectiveRange: nil) as? NSColor,
            .clear
        )
    }

    @MainActor
    func testInlineMarkdownStylesLinksAndHidesSourceChrome() throws {
        let text = "Open [docs](https://example.com)"
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: text),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)
        let contentOffset = contentLocation("docs", in: text)

        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: contentOffset, effectiveRange: nil) as? NSColor, .linkColor)
        XCTAssertEqual(textStorage.attribute(.underlineStyle, at: contentOffset, effectiveRange: nil) as? Int, NSUnderlineStyle.single.rawValue)
        XCTAssertEqual((textStorage.attribute(.link, at: contentOffset, effectiveRange: nil) as? URL)?.absoluteString, "https://example.com")
        XCTAssertEqual(textStorage.attribute(.toolTip, at: contentOffset, effectiveRange: nil) as? String, "https://example.com")
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 5, effectiveRange: nil) as? NSColor, .clear)
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 11, effectiveRange: nil) as? NSColor, .clear)
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 12, effectiveRange: nil) as? NSColor, .clear)
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 31, effectiveRange: nil) as? NSColor, .clear)
    }

    @MainActor
    func testSingleUnderscoreInlineMarkdownIsItalicWhileDoubleUnderscoreStaysLiteral() throws {
        let text = "_italic text_ __bold text__"
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: text),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)

        XCTAssertTrue(try font(at: contentLocation("italic text", in: text), in: textStorage).fontDescriptor.symbolicTraits.contains(.italic))
        XCTAssertFalse(try font(at: contentLocation("bold text", in: text), in: textStorage).fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .clear)
        XCTAssertNotEqual(textStorage.attribute(.foregroundColor, at: 14, effectiveRange: nil) as? NSColor, .clear)
        XCTAssertEqual(item.testingTextView?.string, text)
    }

    @MainActor
    func testInlineMarkdownDelimitersDoNotReserveLayoutWidth() throws {
        let cases = [
            InlineMarkdownDelimiterLayoutCase(text: "**bold text**", contentStart: 2, closingStart: 11),
            InlineMarkdownDelimiterLayoutCase(text: "***bold and italic***", contentStart: 3, closingStart: 18),
            InlineMarkdownDelimiterLayoutCase(text: "_italic text_", contentStart: 1, closingStart: 12),
            InlineMarkdownDelimiterLayoutCase(text: "<u>underlined text</u>", contentStart: 3, closingStart: 18),
            InlineMarkdownDelimiterLayoutCase(text: "<ins>inserted text</ins>", contentStart: 5, closingStart: 18)
        ]

        for testCase in cases {
            let item = BlockInputBlockItem.configuredForTesting(
                block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: testCase.text),
                allowsReordering: true,
                delegate: BlockInputView()
            )
            let textView = try XCTUnwrap(item.testingTextView)
            let layout = try layoutMetrics(for: textView)

            XCTAssertEqual(
                try glyphX(at: testCase.contentStart, layout: layout),
                layout.visibleMinX,
                accuracy: 0.5,
                "Opening delimiter in \(testCase.text) should collapse out of layout."
            )
            XCTAssertEqual(
                layout.visibleMaxX,
                try glyphX(at: testCase.closingStart, layout: layout),
                accuracy: 0.5,
                "Closing delimiter in \(testCase.text) should collapse out of layout."
            )
            XCTAssertEqual(textView.string, testCase.text)
        }
    }

    @MainActor
    func testInlineMarkdownStylesComposedRanges() throws {
        let text = "*some **bold** text*"
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: text),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)
        let composedFont = try font(at: contentLocation("bold", in: text), in: textStorage)

        XCTAssertTrue(composedFont.fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertTrue(composedFont.fontDescriptor.symbolicTraits.contains(.italic))
    }

    @MainActor
    func testInlineMarkdownStylesNestedExamples() throws {
        let cases: [InlineMarkdownNestedStyleCase] = [
            InlineMarkdownNestedStyleCase(
                text: "***bold and italic***",
                content: "bold and italic",
                styles: [.bold, .italic]
            ),
            InlineMarkdownNestedStyleCase(
                text: "**_bold and italic_**",
                content: "bold and italic",
                styles: [.bold, .italic]
            ),
            InlineMarkdownNestedStyleCase(
                text: "**<u>bold and underlined</u>**",
                content: "bold and underlined",
                styles: [.bold, .underline]
            ),
            InlineMarkdownNestedStyleCase(
                text: "~~*strikethrough and italic*~~",
                content: "strikethrough and italic",
                styles: [.italic, .strikethrough]
            )
        ]

        for testCase in cases {
            let item = BlockInputBlockItem.configuredForTesting(
                block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: testCase.text),
                allowsReordering: true,
                delegate: BlockInputView()
            )
            let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)
            let contentOffset = contentLocation(testCase.content, in: testCase.text)
            let contentFont = try font(at: contentOffset, in: textStorage)
            let traits = contentFont.fontDescriptor.symbolicTraits

            XCTAssertEqual(traits.contains(.bold), testCase.styles.contains(.bold), "Unexpected bold trait for \(testCase.text).")
            XCTAssertEqual(traits.contains(.italic), testCase.styles.contains(.italic), "Unexpected italic trait for \(testCase.text).")
            XCTAssertEqual(
                textStorage.attribute(.underlineStyle, at: contentOffset, effectiveRange: nil) as? Int,
                testCase.styles.contains(.underline) ? NSUnderlineStyle.single.rawValue : nil,
                "Unexpected underline style for \(testCase.text)."
            )
            XCTAssertEqual(
                textStorage.attribute(.strikethroughStyle, at: contentOffset, effectiveRange: nil) as? Int,
                testCase.styles.contains(.strikethrough) ? NSUnderlineStyle.single.rawValue : nil,
                "Unexpected strikethrough style for \(testCase.text)."
            )
            XCTAssertEqual(item.testingTextView?.string, testCase.text)
        }
    }

    @MainActor
    func testInlineMarkdownIgnoresInlineCodeRanges() throws {
        let text = "Use `*code*` and *text*"
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: text),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)

        XCTAssertFalse(try font(at: contentLocation("code", in: text), in: textStorage)
            .fontDescriptor.symbolicTraits.contains(.italic))
        XCTAssertTrue(try font(at: contentLocation("text", in: text), in: textStorage)
            .fontDescriptor.symbolicTraits.contains(.italic))
        XCTAssertEqual(
            textStorage.attribute(.blockInputInlineCodeBackground, at: contentLocation("code", in: text), effectiveRange: nil) as? NSColor,
            BlockInputBlockItem.inlineCodeBackgroundColor
        )
    }

    @MainActor
    func testOuterInlineMarkdownSkipsInlineCodeContentOnly() throws {
        let text = "<u>some `code` text</u>"
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: text),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)

        XCTAssertEqual(
            textStorage.attribute(.underlineStyle, at: contentLocation("some", in: text), effectiveRange: nil) as? Int,
            NSUnderlineStyle.single.rawValue
        )
        XCTAssertNil(textStorage.attribute(.underlineStyle, at: contentLocation("code", in: text), effectiveRange: nil))
        XCTAssertEqual(
            textStorage.attribute(.underlineStyle, at: contentLocation("text", in: text), effectiveRange: nil) as? Int,
            NSUnderlineStyle.single.rawValue
        )
        XCTAssertEqual(
            textStorage.attribute(.blockInputInlineCodeBackground, at: contentLocation("code", in: text), effectiveRange: nil) as? NSColor,
            BlockInputBlockItem.inlineCodeBackgroundColor
        )
    }

    @MainActor
    func testInlineMarkdownIsIgnoredInLiteralBlocks() throws {
        let literalBlocks: [BlockInputBlock] = [
            BlockInputBlock(id: "code", kind: .code(language: nil), text: "*some text*"),
            BlockInputBlock(id: "frontmatter", kind: .frontMatter, text: "title: *some text*"),
            BlockInputBlock(id: "raw", kind: .rawMarkdown, text: "*some text*"),
            BlockInputBlock(id: "rule", kind: .horizontalRule, text: "*some text*")
        ]

        for block in literalBlocks {
            let item = BlockInputBlockItem.configuredForTesting(
                block: block,
                allowsReordering: true,
                delegate: BlockInputView()
            )
            let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)
            guard textStorage.length > 0 else {
                continue
            }

            XCTAssertNotEqual(textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .clear)
            XCTAssertNil(textStorage.attribute(.underlineStyle, at: 1, effectiveRange: nil))
            XCTAssertNil(textStorage.attribute(.strikethroughStyle, at: 1, effectiveRange: nil))
        }
    }

    @MainActor
    func testInlineMarkdownAttributesAreClearedWhenItemIsReused() throws {
        let view = BlockInputView()
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: "<u>some text</u> and ~~gone~~"),
            allowsReordering: true,
            delegate: view
        )

        item.configure(
            block: BlockInputBlock(id: "plain", kind: .paragraph, text: "Plain text now"),
            allowsReordering: true,
            delegate: view
        )

        let textStorage = try XCTUnwrap(item.testingTextView?.textStorage)
        XCTAssertNil(textStorage.attribute(.underlineStyle, at: 0, effectiveRange: nil))
        XCTAssertNil(textStorage.attribute(.strikethroughStyle, at: 0, effectiveRange: nil))
        XCTAssertNil(textStorage.attribute(.blockInputHiddenDelimiter, at: 0, effectiveRange: nil))
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .labelColor)
    }

    @MainActor
    func testInlineMarkdownTypingAttributesFollowSelection() throws {
        let text = "*some text* **bold text** <u>underlined text</u> ~~struck text~~ and plain"
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: text),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let textView = try XCTUnwrap(item.testingTextView)

        item.setSelectedRange(NSRange(location: 3, length: 0))
        XCTAssertTrue(try XCTUnwrap(textView.typingAttributes[.font] as? NSFont).fontDescriptor.symbolicTraits.contains(.italic))

        item.setSelectedRange(NSRange(location: 10, length: 0))
        XCTAssertTrue(try XCTUnwrap(textView.typingAttributes[.font] as? NSFont).fontDescriptor.symbolicTraits.contains(.italic))

        item.setSelectedRange(NSRange(location: contentLocation("bold text", in: text), length: 0))
        XCTAssertTrue(try XCTUnwrap(textView.typingAttributes[.font] as? NSFont).fontDescriptor.symbolicTraits.contains(.bold))

        item.setSelectedRange(NSRange(location: contentLocation("underlined text", in: text), length: 0))
        XCTAssertEqual(textView.typingAttributes[.underlineStyle] as? Int, NSUnderlineStyle.single.rawValue)

        item.setSelectedRange(NSRange(location: contentLocation("struck text", in: text), length: 0))
        XCTAssertEqual(textView.typingAttributes[.strikethroughStyle] as? Int, NSUnderlineStyle.single.rawValue)

        item.setSelectedRange(NSRange(location: contentLocation("plain", in: text), length: 0))
        XCTAssertFalse(try XCTUnwrap(textView.typingAttributes[.font] as? NSFont).fontDescriptor.symbolicTraits.contains(.italic))
        XCTAssertFalse(try XCTUnwrap(textView.typingAttributes[.font] as? NSFont).fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertNil(textView.typingAttributes[.underlineStyle])
        XCTAssertNil(textView.typingAttributes[.strikethroughStyle])
    }

    @MainActor
    func testInlineMarkdownTypingAttributesFollowNestedSelection() throws {
        let cases: [InlineMarkdownNestedStyleCase] = [
            InlineMarkdownNestedStyleCase(
                text: "***bold and italic***",
                content: "bold and italic",
                styles: [.bold, .italic]
            ),
            InlineMarkdownNestedStyleCase(
                text: "**_bold and italic_**",
                content: "bold and italic",
                styles: [.bold, .italic]
            ),
            InlineMarkdownNestedStyleCase(
                text: "**<u>bold and underlined</u>**",
                content: "bold and underlined",
                styles: [.bold, .underline]
            ),
            InlineMarkdownNestedStyleCase(
                text: "~~*strikethrough and italic*~~",
                content: "strikethrough and italic",
                styles: [.italic, .strikethrough]
            )
        ]

        for testCase in cases {
            let item = BlockInputBlockItem.configuredForTesting(
                block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: testCase.text),
                allowsReordering: true,
                delegate: BlockInputView()
            )
            let textView = try XCTUnwrap(item.testingTextView)

            item.setSelectedRange(NSRange(location: contentLocation(testCase.content, in: testCase.text), length: 0))

            let typingFont = try XCTUnwrap(textView.typingAttributes[.font] as? NSFont)
            let traits = typingFont.fontDescriptor.symbolicTraits
            XCTAssertEqual(traits.contains(.bold), testCase.styles.contains(.bold), "Unexpected bold typing trait for \(testCase.text).")
            XCTAssertEqual(traits.contains(.italic), testCase.styles.contains(.italic), "Unexpected italic typing trait for \(testCase.text).")
            XCTAssertEqual(
                textView.typingAttributes[.underlineStyle] as? Int,
                testCase.styles.contains(.underline) ? NSUnderlineStyle.single.rawValue : nil,
                "Unexpected underline typing style for \(testCase.text)."
            )
            XCTAssertEqual(
                textView.typingAttributes[.strikethroughStyle] as? Int,
                testCase.styles.contains(.strikethrough) ? NSUnderlineStyle.single.rawValue : nil,
                "Unexpected strikethrough typing style for \(testCase.text)."
            )
        }
    }

    @MainActor
    func testInlineCodeTypingAttributesWinAtBoundaryInsideInlineMarkdown() throws {
        let item = BlockInputBlockItem.configuredForTesting(
            block: BlockInputBlock(id: "paragraph", kind: .paragraph, text: "*some `code` text*"),
            allowsReordering: true,
            delegate: BlockInputView()
        )
        let textView = try XCTUnwrap(item.testingTextView)

        item.setSelectedRange(NSRange(location: 11, length: 0))

        let typingFont = try XCTUnwrap(textView.typingAttributes[.font] as? NSFont)
        XCTAssertTrue(typingFont.fontDescriptor.symbolicTraits.contains(.monoSpace))
        XCTAssertFalse(typingFont.fontDescriptor.symbolicTraits.contains(.italic))
        XCTAssertEqual(textView.typingAttributes[.blockInputInlineCodeBackground] as? NSColor, BlockInputBlockItem.inlineCodeBackgroundColor)
    }

    @MainActor
    func testKeyboardTypedInlineMarkdownRestylesEditedRow() throws {
        let (view, _) = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "paragraph", kind: .paragraph, text: "Plain")
        ])
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)

        textView.string = "*some text*"
        textView.setSelectedRange(NSRange(location: 11, length: 0))
        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        let textStorage = try XCTUnwrap(textView.textStorage)
        XCTAssertTrue(try font(at: 1, in: textStorage).fontDescriptor.symbolicTraits.contains(.italic))
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .clear)
        XCTAssertEqual(view.document.blocks[0].text, "*some text*")
    }

    @MainActor
    func testKeyboardTypedInlineMarkdownLinkRestylesEditedRow() throws {
        let text = "Open [docs](https://example.com)"
        let (view, _) = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "paragraph", kind: .paragraph, text: "Plain")
        ])
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)

        textView.string = text
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        let textStorage = try XCTUnwrap(textView.textStorage)
        let contentOffset = contentLocation("docs", in: text)
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: contentOffset, effectiveRange: nil) as? NSColor, .linkColor)
        XCTAssertEqual((textStorage.attribute(.link, at: contentOffset, effectiveRange: nil) as? URL)?.absoluteString, "https://example.com")
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 5, effectiveRange: nil) as? NSColor, .clear)
        XCTAssertEqual(view.document.blocks[0].text, text)
    }
}

private func font(at location: Int, in textStorage: NSTextStorage) throws -> NSFont {
    try XCTUnwrap(textStorage.attribute(.font, at: location, effectiveRange: nil) as? NSFont)
}

private func contentLocation(_ needle: String, in text: String) -> Int {
    (text as NSString).range(of: needle).location
}

@MainActor
private func layoutMetrics(
    for textView: NSTextView
) throws -> InlineMarkdownLayoutMetrics {
    textView.frame = NSRect(x: 0, y: 0, width: 320, height: 60)
    textView.textContainer?.containerSize = NSSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
    let layoutManager = try XCTUnwrap(textView.layoutManager)
    let textContainer = try XCTUnwrap(textView.textContainer)
    layoutManager.ensureLayout(for: textContainer)
    let usedRect = layoutManager.lineFragmentUsedRect(forGlyphAt: 0, effectiveRange: nil)
    let lineFragmentPadding = textContainer.lineFragmentPadding
    return InlineMarkdownLayoutMetrics(
        layoutManager: layoutManager,
        visibleMinX: usedRect.minX + lineFragmentPadding,
        visibleMaxX: usedRect.maxX - lineFragmentPadding
    )
}

private func glyphX(
    at utf16Offset: Int,
    layout: InlineMarkdownLayoutMetrics
) throws -> CGFloat {
    let glyphIndex = layout.layoutManager.glyphIndexForCharacter(at: utf16Offset)
    return layout.layoutManager.location(forGlyphAt: glyphIndex).x
}

private struct InlineMarkdownDelimiterLayoutCase {
    let text: String
    let contentStart: Int
    let closingStart: Int
}

private struct InlineMarkdownNestedStyleCase {
    let text: String
    let content: String
    let styles: Set<BlockInputInlineMarkdownStyle>
}

private struct InlineMarkdownLayoutMetrics {
    let layoutManager: NSLayoutManager
    let visibleMinX: CGFloat
    let visibleMaxX: CGFloat
}
