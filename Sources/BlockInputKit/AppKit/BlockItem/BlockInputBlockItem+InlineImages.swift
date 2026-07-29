import AppKit

/// Attribute payload for one image rendered inline within a text line.
///
/// The payload is attached to the single visible anchor character of the image
/// source span; the draw pass and the line-fragment growth delegate both read
/// geometry from here so layout and drawing cannot disagree.
final class BlockInputInlineImageRun: NSObject {
    let image: BlockInputImage
    let displaySize: NSSize
    /// How far the image bottom extends below the text baseline. Images center
    /// on the cap-height midline like GitHub's `vertical-align: middle`, so
    /// anything taller than the cap height dips under the baseline by half the
    /// difference instead of riding high on top of it.
    let baselineDrop: CGFloat
    /// False until the store has natural dimensions; placeholder chrome renders instead.
    let isLoaded: Bool

    init(image: BlockInputImage, displaySize: NSSize, baselineDrop: CGFloat, isLoaded: Bool) {
        self.image = image
        self.displaySize = displaySize
        self.baselineDrop = baselineDrop
        self.isLoaded = isLoaded
    }

    /// Vertical space the image needs above the baseline.
    var ascent: CGFloat {
        displaySize.height - baselineDrop
    }
}

extension NSAttributedString.Key {
    /// Marks the anchor character of an inline image span; value is `BlockInputInlineImageRun`.
    static let blockInputInlineImage = NSAttributedString.Key("BlockInputInlineImage")
}

extension BlockInputBlockItem {
    static let minimumInlineImageDimension: CGFloat = 4

    static func applyInlineImageAttributes(
        for markdownRange: BlockInputInlineMarkdownRange,
        fullRange: NSRange,
        textStorage: NSTextStorage,
        baseFont: NSFont,
        inlineImageSizes: BlockInputInlineImageSizes,
        inlineImageMaximumWidth: CGFloat
    ) {
        guard let image = markdownRange.image else {
            return
        }
        let anchorRange = NSIntersectionRange(markdownRange.contentRange, fullRange)
        guard anchorRange.length > 0 else {
            return
        }
        let naturalSize = inlineImageSizes.size(forSource: image.source)
        let displaySize = inlineImageDisplaySize(
            for: image,
            naturalSize: naturalSize,
            baseFont: baseFont,
            maximumWidth: inlineImageMaximumWidth
        )
        let anchorText = (textStorage.string as NSString).substring(with: anchorRange)
        let anchorWidth = (anchorText as NSString).size(withAttributes: [.font: baseFont]).width
        let reservedWidth = max(displaySize.width, anchorWidth + 1)
        textStorage.addAttributes(
            [
                .font: baseFont,
                .foregroundColor: NSColor.clear,
                .kern: reservedWidth - anchorWidth,
                .blockInputInlineImage: BlockInputInlineImageRun(
                    image: image,
                    displaySize: NSSize(width: reservedWidth, height: displaySize.height),
                    baselineDrop: max(0, (displaySize.height - baseFont.capHeight) / 2),
                    isLoaded: naturalSize != nil
                )
            ],
            range: anchorRange
        )
        if !image.altText.isEmpty {
            textStorage.addAttribute(.toolTip, value: image.altText, range: anchorRange)
        }
        for delimiterRange in markdownRange.delimiterRanges {
            let clampedDelimiterRange = NSIntersectionRange(delimiterRange, fullRange)
            guard clampedDelimiterRange.length > 0 else {
                continue
            }
            textStorage.addAttributes(
                [
                    .font: inlineImageHiddenSourceFont(for: baseFont),
                    .foregroundColor: NSColor.clear,
                    .blockInputHiddenDelimiter: true
                ],
                range: clampedDelimiterRange
            )
        }
    }

    /// Natural size wins (GitHub parity); declared `<img>` dimensions apply pre-load,
    /// and an unloaded image reserves a line-height square so text barely shifts.
    static func inlineImageDisplaySize(
        for image: BlockInputImage,
        naturalSize: NSSize?,
        baseFont: NSFont,
        maximumWidth: CGFloat
    ) -> NSSize {
        let declaredWidth = image.width.map(CGFloat.init)
        let declaredHeight = image.height.map(CGFloat.init)
        var size: NSSize
        switch (declaredWidth, declaredHeight) {
        case let (width?, height?):
            size = NSSize(width: width, height: height)
        case let (width?, nil):
            let aspectRatio = naturalSize.map { $0.width / max($0.height, 1) } ?? 1
            size = NSSize(width: width, height: width / max(aspectRatio, 0.01))
        case let (nil, height?):
            let aspectRatio = naturalSize.map { $0.width / max($0.height, 1) } ?? 1
            size = NSSize(width: height * aspectRatio, height: height)
        case (nil, nil):
            if let naturalSize {
                size = naturalSize
            } else {
                let lineHeight = inlineImagePlaceholderHeight(for: baseFont)
                size = NSSize(width: lineHeight, height: lineHeight)
            }
        }
        size.width = max(size.width, minimumInlineImageDimension)
        size.height = max(size.height, minimumInlineImageDimension)
        if maximumWidth > 0, size.width > maximumWidth {
            let scale = maximumWidth / size.width
            size = NSSize(width: maximumWidth, height: max(size.height * scale, minimumInlineImageDimension))
        }
        return NSSize(width: ceil(size.width), height: ceil(size.height))
    }

    static func inlineImagePlaceholderHeight(for font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    private static func inlineImageHiddenSourceFont(for font: NSFont) -> NSFont {
        .systemFont(ofSize: max(font.pointSize * 0.1, 1), weight: .regular)
    }
}

extension BlockInputBlockItem {
    /// Kicks store loads for every inline image the row just styled. The store
    /// dedupes by source, so repeated applications are cheap.
    func startInlineImageLoads(in textStorage: NSTextStorage) {
        guard let inlineImageStore else {
            return
        }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        textStorage.enumerateAttribute(.blockInputInlineImage, in: fullRange) { value, _, _ in
            guard let run = value as? BlockInputInlineImageRun else {
                return
            }
            inlineImageStore.ensureLoad(for: run.image, context: imageLoadingContext)
        }
    }

    /// Width available to one text line, used to cap inline image advances so a
    /// wide image cannot overflow the container.
    var inlineImageMaximumTextWidth: CGFloat {
        guard let textContainer = textView.textContainer,
              textContainer.size.width > 0,
              textContainer.size.width < .greatestFiniteMagnitude else {
            return .greatestFiniteMagnitude
        }
        return max(textContainer.size.width - textContainer.lineFragmentPadding * 2, 24)
    }
}
