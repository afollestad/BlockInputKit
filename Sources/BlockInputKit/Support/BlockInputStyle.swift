import AppKit

/// Visual styling used by AppKit block editor surfaces.
public struct BlockInputStyle: @unchecked Sendable {
    /// Current built-in visual style.
    public static var `default`: BlockInputStyle { BlockInputStyle() }

    /// Base text styling for paragraphs, lists, quotes, and scaled block typography.
    public var baseText: BlockInputTextStyle
    /// Background color used for editor-owned block and text selection chrome.
    public var selectionBackgroundColor: NSColor
    /// Styling for inline single-line code spans.
    public var inlineCode: BlockInputInlineCodeStyle
    /// Styling for fenced code block surfaces.
    public var codeBlock: BlockInputCodeBlockStyle
    /// Styling for image block surfaces.
    public var imageBlock: BlockInputImageBlockStyle
    /// Styling for editor-owned background surfaces.
    public var editorSurface: BlockInputEditorSurfaceStyle
    /// Styling for inline file-link chips.
    public var fileChip: BlockInputInlineChipStyle
    /// Styling for link-backed slash-command chips.
    public var slashCommandChip: BlockInputInlineChipStyle
    /// Styling for raw `/command` visual chips.
    public var rawSlashCommandChip: BlockInputInlineChipStyle

    /// Creates editor styling with optional overrides for built-in visual defaults.
    public init(
        baseText: BlockInputTextStyle = BlockInputTextStyle(),
        selectionBackgroundColor: NSColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.72),
        inlineCode: BlockInputInlineCodeStyle = BlockInputInlineCodeStyle(),
        codeBlock: BlockInputCodeBlockStyle = BlockInputCodeBlockStyle(),
        imageBlock: BlockInputImageBlockStyle = BlockInputImageBlockStyle(),
        editorSurface: BlockInputEditorSurfaceStyle = BlockInputEditorSurfaceStyle(),
        fileChip: BlockInputInlineChipStyle = BlockInputInlineChipStyle(),
        slashCommandChip: BlockInputInlineChipStyle = BlockInputInlineChipStyle(),
        rawSlashCommandChip: BlockInputInlineChipStyle = BlockInputInlineChipStyle()
    ) {
        self.baseText = baseText
        self.selectionBackgroundColor = selectionBackgroundColor
        self.inlineCode = inlineCode
        self.codeBlock = codeBlock
        self.imageBlock = imageBlock
        self.editorSurface = editorSurface
        self.fileChip = fileChip
        self.slashCommandChip = slashCommandChip
        self.rawSlashCommandChip = rawSlashCommandChip
    }
}

/// Background styling for editor-owned AppKit surfaces.
///
/// Each color defaults to `NSColor.textBackgroundColor`. Set a color to nil when the host should draw that surface.
public struct BlockInputEditorSurfaceStyle: @unchecked Sendable {
    /// Root editor view background color. When nil, the root view layer is transparent.
    public var editorBackgroundColor: NSColor?
    /// Document scroll view background color. When nil, the scroll and clip views do not draw their backgrounds.
    public var scrollBackgroundColor: NSColor?
    /// Collection view background color. When nil, the collection view uses an empty `backgroundColors` array.
    public var collectionBackgroundColor: NSColor?
    /// Optional rounded editor chrome drawn by the root editor view.
    public var chrome: BlockInputEditorChromeStyle?

    /// Creates editor surface styling overrides.
    public init(
        editorBackgroundColor: NSColor? = .textBackgroundColor,
        scrollBackgroundColor: NSColor? = .textBackgroundColor,
        collectionBackgroundColor: NSColor? = .textBackgroundColor,
        chrome: BlockInputEditorChromeStyle? = nil
    ) {
        self.editorBackgroundColor = editorBackgroundColor
        self.scrollBackgroundColor = scrollBackgroundColor
        self.collectionBackgroundColor = collectionBackgroundColor
        self.chrome = chrome
    }
}

/// Root editor chrome drawn behind the editor's scrollable document surface.
public struct BlockInputEditorChromeStyle: @unchecked Sendable {
    /// Chrome fill color. When nil, the root editor background color is used.
    public var fillColor: NSColor?
    /// Optional chrome stroke color. When nil, no stroke is drawn.
    public var strokeColor: NSColor?
    /// Chrome stroke width. Negative values are clamped to zero.
    public var borderWidth: CGFloat {
        didSet {
            borderWidth = Self.validNonNegative(borderWidth)
        }
    }
    /// Chrome corner radius. Negative values are clamped to zero.
    public var cornerRadius: CGFloat {
        didSet {
            cornerRadius = Self.validNonNegative(cornerRadius)
        }
    }
    /// Corners that should use `cornerRadius`.
    public var roundedCorners: BlockInputEditorChromeCorners
    /// Edges that should draw a stroke.
    public var strokedEdges: BlockInputEditorChromeEdges
    /// Whether editor content should be clipped to the rounded chrome shape.
    public var clipsContentToShape: Bool

    /// Creates rounded editor chrome styling.
    public init(
        fillColor: NSColor? = nil,
        strokeColor: NSColor? = nil,
        borderWidth: CGFloat = 0,
        cornerRadius: CGFloat = 0,
        roundedCorners: BlockInputEditorChromeCorners = .all,
        strokedEdges: BlockInputEditorChromeEdges = .all,
        clipsContentToShape: Bool = false
    ) {
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.borderWidth = Self.validNonNegative(borderWidth)
        self.cornerRadius = Self.validNonNegative(cornerRadius)
        self.roundedCorners = roundedCorners
        self.strokedEdges = strokedEdges
        self.clipsContentToShape = clipsContentToShape
    }

    private static func validNonNegative(_ value: CGFloat) -> CGFloat {
        max(0, value)
    }
}

/// Corners that can be rounded by `BlockInputEditorChromeStyle`.
public struct BlockInputEditorChromeCorners: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let topLeft = BlockInputEditorChromeCorners(rawValue: 1 << 0)
    public static let topRight = BlockInputEditorChromeCorners(rawValue: 1 << 1)
    public static let bottomLeft = BlockInputEditorChromeCorners(rawValue: 1 << 2)
    public static let bottomRight = BlockInputEditorChromeCorners(rawValue: 1 << 3)

    public static let top: BlockInputEditorChromeCorners = [.topLeft, .topRight]
    public static let bottom: BlockInputEditorChromeCorners = [.bottomLeft, .bottomRight]
    public static let all: BlockInputEditorChromeCorners = [.top, .bottom]
}

/// Edges that can be stroked by `BlockInputEditorChromeStyle`.
public struct BlockInputEditorChromeEdges: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let top = BlockInputEditorChromeEdges(rawValue: 1 << 0)
    public static let left = BlockInputEditorChromeEdges(rawValue: 1 << 1)
    public static let bottom = BlockInputEditorChromeEdges(rawValue: 1 << 2)
    public static let right = BlockInputEditorChromeEdges(rawValue: 1 << 3)

    public static let horizontal: BlockInputEditorChromeEdges = [.top, .bottom]
    public static let vertical: BlockInputEditorChromeEdges = [.left, .right]
    public static let all: BlockInputEditorChromeEdges = [.top, .left, .bottom, .right]
}

/// Fill, stroke, foreground, and rounding styling for inline chips.
///
/// This is visual-only styling for file, link-backed slash-command, and raw slash-command chips. Regular Markdown links
/// keep the editor's normal link styling unless they resolve to a chip kind.
public struct BlockInputInlineChipStyle: @unchecked Sendable {
    /// Chip fill color. When nil, the chip fill is not drawn.
    public var fillColor: NSColor?
    /// Chip stroke color. When nil, the chip stroke is not drawn.
    public var strokeColor: NSColor?
    /// Chip text foreground color, including for link-backed chips that would otherwise use the system link color.
    public var foregroundColor: NSColor
    /// Chip corner radius. Negative values are clamped to zero.
    public var cornerRadius: CGFloat {
        didSet {
            cornerRadius = Self.validCornerRadius(cornerRadius)
        }
    }

    /// Creates inline chip styling overrides.
    public init(
        fillColor: NSColor? = NSColor.controlAccentColor.withAlphaComponent(0.11),
        strokeColor: NSColor? = NSColor.controlAccentColor.withAlphaComponent(0.18),
        foregroundColor: NSColor = .labelColor,
        cornerRadius: CGFloat = 6
    ) {
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.foregroundColor = foregroundColor
        self.cornerRadius = Self.validCornerRadius(cornerRadius)
    }

    private static func validCornerRadius(_ value: CGFloat) -> CGFloat {
        max(0, value)
    }
}

/// Background, border, and corner styling for image block surfaces.
public struct BlockInputImageBlockStyle: @unchecked Sendable {
    /// Placeholder aspect ratio used for image blocks whose width and height are still unknown.
    public var placeholderAspectRatio: CGFloat? {
        didSet {
            placeholderAspectRatio = placeholderAspectRatio.flatMap(Self.validAspectRatio)
        }
    }
    /// Placeholder fill color shown before an image has loaded.
    public var placeholderColor: NSColor?
    /// Optional border color for placeholder, loaded, and failed image surfaces.
    ///
    /// When nil, image surfaces do not draw a border.
    public var borderColor: NSColor?
    /// Surface corner radius. When nil, images use the built-in radius.
    public var cornerRadius: CGFloat?

    /// Creates image block styling overrides.
    public init(
        placeholderAspectRatio: CGFloat? = nil,
        placeholderColor: NSColor? = nil,
        borderColor: NSColor? = nil,
        cornerRadius: CGFloat? = nil
    ) {
        self.placeholderAspectRatio = placeholderAspectRatio.flatMap(Self.validAspectRatio)
        self.placeholderColor = placeholderColor
        self.borderColor = borderColor
        self.cornerRadius = cornerRadius
    }

    private static func validAspectRatio(_ value: CGFloat) -> CGFloat? {
        value > 0 ? value : nil
    }
}

/// Font and foreground color styling for normal editor text.
public struct BlockInputTextStyle: @unchecked Sendable {
    /// Base font for body text. When nil, the editor uses its built-in body font.
    public var font: NSFont?
    /// Base foreground color. When nil, the editor uses the system label color.
    public var foregroundColor: NSColor?
    /// Extra space TextKit puts in the gaps *between* the line fragments of a wrapping text block.
    ///
    /// Nothing is added after the last line, so a one-line row and the empty document keep their
    /// heights and an editor sized in visible lines keeps its resting height; only wrapped or
    /// multi-line blocks grow, by slightly less than this value per gap. Code and table blocks are
    /// excluded so their metrics keep matching the measurement paths that never see this style;
    /// `BlockInputBlockItem.lineSpacing(for:style:)` owns that split.
    public var lineSpacing: CGFloat

    /// Creates normal text styling overrides.
    public init(font: NSFont? = nil, foregroundColor: NSColor? = nil, lineSpacing: CGFloat = 0) {
        self.font = font
        self.foregroundColor = foregroundColor
        self.lineSpacing = max(0, lineSpacing)
    }
}

/// Font, foreground, and background styling for inline code spans.
public struct BlockInputInlineCodeStyle: @unchecked Sendable {
    /// Inline code font. When nil, inline code uses a scaled monospaced variant of the surrounding text font.
    public var font: NSFont?
    /// Inline code foreground color. When nil, inline code inherits the base text foreground color.
    public var foregroundColor: NSColor?
    /// Inline code background color. When nil, inline code uses the built-in subtle background color.
    public var backgroundColor: NSColor?

    /// Creates inline code styling overrides.
    public init(font: NSFont? = nil, foregroundColor: NSColor? = nil, backgroundColor: NSColor? = nil) {
        self.font = font
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
    }
}

/// Font, foreground, background, and rounding styling for fenced code block surfaces.
public struct BlockInputCodeBlockStyle: @unchecked Sendable {
    /// Fenced code block font. When nil, code blocks use the built-in monospaced font.
    public var font: NSFont?
    /// Fenced code block foreground color. When nil, code text uses syntax highlighting with the base text color fallback.
    public var foregroundColor: NSColor?
    /// Fenced code block background color. When nil, code blocks use the built-in appearance-aware surface color.
    public var backgroundColor: NSColor?
    /// Fenced code block corner radius. When nil, code blocks use the built-in radius.
    public var cornerRadius: CGFloat?

    /// Creates fenced code block styling overrides.
    public init(
        font: NSFont? = nil,
        foregroundColor: NSColor? = nil,
        backgroundColor: NSColor? = nil,
        cornerRadius: CGFloat? = nil
    ) {
        self.font = font
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
        self.cornerRadius = cornerRadius
    }
}
