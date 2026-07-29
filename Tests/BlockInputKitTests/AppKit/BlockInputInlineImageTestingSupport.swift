import AppKit
@testable import BlockInputKit

/// Resolves configured sources to deterministic solid-color PNGs and suspends
/// for everything else, so inline-image tests can pin loaded and placeholder
/// states in one document.
struct SizedInlineImageLoader: BlockInputImageLoading {
    var sizesBySource: [String: BlockInputImageDimensions]

    init(sizesBySource: [String: BlockInputImageDimensions]) {
        self.sizesBySource = sizesBySource
    }

    init(source: String, width: Int, height: Int) {
        sizesBySource = [source: BlockInputImageDimensions(width: width, height: height)]
    }

    func loadImage(_ request: BlockInputImageLoadRequest) async throws -> BlockInputLoadedImage {
        guard let dimensions = sizesBySource[request.image.source] else {
            try await Task.sleep(nanoseconds: 60_000_000_000)
            throw CancellationError()
        }
        return try BlockInputLoadedImage(
            data: inlineImageTestPNGData(width: dimensions.width, height: dimensions.height),
            dimensions: dimensions
        )
    }
}

/// Builds a solid-color PNG whose pixel size equals its point size (72 DPI).
func inlineImageTestPNGData(width: Int, height: Int, color: NSColor = .systemTeal) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw InlineImageTestingError.invalidFixture
    }
    bitmap.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    if let context = NSGraphicsContext(bitmapImageRep: bitmap) {
        NSGraphicsContext.current = context
        color.setFill()
        NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)).fill()
        context.flushGraphics()
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw InlineImageTestingError.invalidFixture
    }
    return data
}

enum InlineImageTestingError: Error {
    case invalidFixture
}
