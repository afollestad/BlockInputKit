import AppKit
import QuartzCore
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewSurfaceStyleTests: XCTestCase {
    func testMountedEditorAppliesConfiguredSurfaceStyle() throws {
        let style = BlockInputStyle(editorSurface: BlockInputEditorSurfaceStyle(
            editorBackgroundColor: .systemRed,
            scrollBackgroundColor: .systemGreen,
            collectionBackgroundColor: .systemBlue
        ))
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "paragraph", text: "Surface")]),
            style: style
        ))

        XCTAssertEqual(mounted.view.layer?.backgroundColor, NSColor.systemRed.cgColor)
        XCTAssertEqual(mounted.view.scrollView.contentView.backgroundColor, .systemGreen)
        XCTAssertEqual(mounted.view.collectionView.backgroundColors, [.systemBlue])
    }

    func testMountedEditorAppliesTransparentSurfaceStyle() {
        let style = BlockInputStyle(editorSurface: BlockInputEditorSurfaceStyle(
            editorBackgroundColor: nil,
            scrollBackgroundColor: nil,
            collectionBackgroundColor: nil
        ))
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "paragraph", text: "Surface")]),
            style: style
        ))

        XCTAssertNil(mounted.view.layer?.backgroundColor)
        XCTAssertFalse(mounted.view.scrollView.isOpaque)
        XCTAssertEqual(mounted.view.scrollView.contentView.backgroundColor, .clear)
        XCTAssertFalse(mounted.view.collectionView.isOpaque)
        XCTAssertTrue(mounted.view.collectionView.backgroundColors.isEmpty)
    }

    func testMountedEditorReconfiguresSurfaceStyle() throws {
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(style: BlockInputStyle(editorSurface: BlockInputEditorSurfaceStyle(
            editorBackgroundColor: .systemRed,
            scrollBackgroundColor: .systemGreen,
            collectionBackgroundColor: .systemBlue
        ))))

        view.configure(BlockInputConfiguration(style: BlockInputStyle(editorSurface: BlockInputEditorSurfaceStyle(
            editorBackgroundColor: nil,
            scrollBackgroundColor: nil,
            collectionBackgroundColor: nil
        ))))

        XCTAssertNil(view.layer?.backgroundColor)
        XCTAssertEqual(view.scrollView.contentView.backgroundColor, .clear)
        XCTAssertTrue(view.collectionView.backgroundColors.isEmpty)
    }

    func testMountedEditorUpdatesDynamicSurfaceStyleForAppearanceChange() throws {
        let dynamicColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .systemGreen : .systemRed
        }
        let view = BlockInputView()
        view.appearance = NSAppearance(named: .aqua)
        view.configure(BlockInputConfiguration(style: BlockInputStyle(editorSurface: BlockInputEditorSurfaceStyle(
            editorBackgroundColor: dynamicColor,
            scrollBackgroundColor: nil,
            collectionBackgroundColor: nil
        ))))
        let lightColor = try XCTUnwrap(NSColor(cgColor: try XCTUnwrap(view.layer?.backgroundColor)))

        view.appearance = NSAppearance(named: .darkAqua)
        view.viewDidChangeEffectiveAppearance()
        let darkColor = try XCTUnwrap(NSColor(cgColor: try XCTUnwrap(view.layer?.backgroundColor)))

        XCTAssertNotEqual(lightColor, darkColor)
    }

    func testProgressiveLoadingRowUsesCollectionSurfaceStyle() throws {
        let store = BlockInputProgressiveMemoryDocumentStore(
            blocks: [
                BlockInputBlock(id: "first", text: "Loaded"),
                BlockInputBlock(id: "second", text: "Unloaded")
            ],
            initialLimit: 1
        )
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
        view.configure(BlockInputConfiguration(
            documentStore: store,
            style: BlockInputStyle(editorSurface: BlockInputEditorSurfaceStyle(collectionBackgroundColor: .systemBlue))
        ))

        let item = try XCTUnwrap(view.collectionView(
            view.collectionView,
            itemForRepresentedObjectAt: IndexPath(item: 1, section: 0)
        ) as? BlockInputLoadingItem)

        XCTAssertEqual(item.view.layer?.backgroundColor, NSColor.systemBlue.cgColor)
    }

    func testMountedEditorAppliesChromeStyle() {
        let style = BlockInputStyle(editorSurface: BlockInputEditorSurfaceStyle(
            editorBackgroundColor: nil,
            scrollBackgroundColor: nil,
            collectionBackgroundColor: nil,
            chrome: BlockInputEditorChromeStyle(
                fillColor: .systemRed,
                strokeColor: .systemGreen,
                borderWidth: 2,
                cornerRadius: 18,
                roundedCorners: .bottom,
                clipsContentToShape: true
            )
        ))
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: "paragraph", text: "Surface")]),
            style: style
        ))

        XCTAssertNil(mounted.view.layer?.backgroundColor)
        XCTAssertNil(mounted.view.layer?.borderColor)
        XCTAssertEqual(mounted.view.layer?.borderWidth, 0)
        XCTAssertEqual(mounted.view.editorChromeFillLayer.fillColor, NSColor.systemRed.cgColor)
        XCTAssertNil(mounted.view.editorChromeStrokeLayer.strokeColor)
        XCTAssertEqual(mounted.view.editorChromeStrokeLayer.lineWidth, 0)
        XCTAssertTrue(mounted.view.editorChromeFillLayer.superlayer === mounted.view.layer)
        XCTAssertNil(mounted.view.editorChromeStrokeLayer.superlayer)
        XCTAssertTrue(mounted.view.layer?.mask === mounted.view.editorChromeMaskLayer)
        XCTAssertNotNil(mounted.view.editorChromeFillLayer.path)
        XCTAssertNil(mounted.view.editorChromeStrokeLayer.path)
        XCTAssertNotNil(mounted.view.editorChromeMaskLayer.path)
        XCTAssertTrue(mounted.view.editorChromeView.drawsFill)
        XCTAssertFalse(mounted.view.editorChromeView.drawsStroke)
        XCTAssertFalse(mounted.view.editorChromeStrokeOverlayView.drawsFill)
        XCTAssertTrue(mounted.view.editorChromeStrokeOverlayView.drawsStroke)
        XCTAssertEqual(mounted.view.editorChromeStrokeOverlayView.strokePassCount, 2)
    }

    func testMountedEditorRendersBottomChromeCornersAtVisualBottom() throws {
        let samples = try cachedDisplayChromeCornerSamples(roundedCorners: .bottom)

        assertFilled(samples.topLeft, "top-left", roundedCorners: ".bottom")
        assertFilled(samples.topRight, "top-right", roundedCorners: ".bottom")
        assertClipped(samples.bottomLeft, "bottom-left", roundedCorners: ".bottom")
        assertClipped(samples.bottomRight, "bottom-right", roundedCorners: ".bottom")
    }

    func testMountedEditorRendersTopChromeCornersAtVisualTop() throws {
        let samples = try cachedDisplayChromeCornerSamples(roundedCorners: .top)

        assertClipped(samples.topLeft, "top-left", roundedCorners: ".top")
        assertClipped(samples.topRight, "top-right", roundedCorners: ".top")
        assertFilled(samples.bottomLeft, "bottom-left", roundedCorners: ".top")
        assertFilled(samples.bottomRight, "bottom-right", roundedCorners: ".top")
    }

    func testMountedEditorRendersAllChromeCorners() throws {
        let samples = try cachedDisplayChromeCornerSamples(roundedCorners: .all)

        assertClipped(samples.topLeft, "top-left", roundedCorners: ".all")
        assertClipped(samples.topRight, "top-right", roundedCorners: ".all")
        assertClipped(samples.bottomLeft, "bottom-left", roundedCorners: ".all")
        assertClipped(samples.bottomRight, "bottom-right", roundedCorners: ".all")
    }

    func testMountedEditorChromeFillAndStrokeRenderThroughViewSnapshots() throws {
        let samples = try cachedDisplayChromeInteriorSamples(roundedCorners: .bottom)

        assertFilled(samples.fill, "interior fill", roundedCorners: ".bottom")
        assertFilled(samples.leftStroke, "left stroke", roundedCorners: ".bottom")
        assertFilled(samples.bottomStroke, "bottom stroke", roundedCorners: ".bottom")
    }

    func testMountedEditorTranslucentChromeDrawsOverLightBackground() throws {
        let size = NSSize(width: 80, height: 40)
        let mounted = makeMountedBlockInputView(
            configuration: BlockInputConfiguration(style: BlockInputStyle(editorSurface: BlockInputEditorSurfaceStyle(
                editorBackgroundColor: nil,
                scrollBackgroundColor: nil,
                collectionBackgroundColor: nil,
                chrome: BlockInputEditorChromeStyle(
                    fillColor: NSColor.black.withAlphaComponent(0.08),
                    strokeColor: NSColor.black.withAlphaComponent(0.18),
                    borderWidth: 1,
                    cornerRadius: 18,
                    roundedCorners: .bottom,
                    clipsContentToShape: true
                )
            ))),
            size: size,
            styleMask: [.borderless]
        )
        mounted.view.displayIfNeeded()
        mounted.view.layoutSubtreeIfNeeded()

        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(size.width),
                pixelsHigh: Int(size.height),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        bitmap.size = size
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        mounted.view.editorChromeView.draw(mounted.view.editorChromeView.bounds)
        NSGraphicsContext.restoreGraphicsState()

        let background = try XCTUnwrap(bitmap.colorAt(x: 2, y: 38)?.usingColorSpace(.deviceRGB))
        let fill = try XCTUnwrap(bitmap.colorAt(x: 40, y: 20)?.usingColorSpace(.deviceRGB))
        XCTAssertLessThan(fill.redComponent, background.redComponent - 0.03)
    }

    func testMountedEditorChromeOverlayDoesNotCaptureHitTests() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            style: BlockInputStyle(editorSurface: BlockInputEditorSurfaceStyle(
                editorBackgroundColor: nil,
                scrollBackgroundColor: nil,
                collectionBackgroundColor: nil,
                chrome: BlockInputEditorChromeStyle(
                    fillColor: .systemRed,
                    strokeColor: .systemGreen,
                    borderWidth: 1,
                    cornerRadius: 12,
                    clipsContentToShape: true
                )
            ))
        ))
        mounted.view.displayIfNeeded()
        mounted.view.layoutSubtreeIfNeeded()

        let hitView = try XCTUnwrap(mounted.view.hitTest(NSPoint(x: mounted.view.bounds.midX, y: mounted.view.bounds.midY)))
        XCTAssertFalse(hitView === mounted.view.editorChromeView)
        XCTAssertFalse(hitView === mounted.view.editorChromeStrokeOverlayView)
    }

    func testMountedEditorReconfiguresChromeStyle() throws {
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(style: BlockInputStyle(editorSurface: BlockInputEditorSurfaceStyle(
            editorBackgroundColor: .systemBlue,
            chrome: BlockInputEditorChromeStyle(
                fillColor: .systemRed,
                strokeColor: .systemGreen,
                borderWidth: 2,
                cornerRadius: 18,
                clipsContentToShape: true
            )
        ))))

        view.configure(BlockInputConfiguration(style: BlockInputStyle(editorSurface: BlockInputEditorSurfaceStyle(
            editorBackgroundColor: .systemBlue,
            scrollBackgroundColor: nil,
            collectionBackgroundColor: nil
        ))))

        XCTAssertEqual(view.layer?.backgroundColor, NSColor.systemBlue.cgColor)
        XCTAssertNil(view.layer?.borderColor)
        XCTAssertEqual(view.layer?.borderWidth, 0)
        XCTAssertEqual(view.layer?.cornerRadius, 0)
        XCTAssertEqual(view.layer?.maskedCorners, [
            .layerMinXMinYCorner,
            .layerMaxXMinYCorner,
            .layerMinXMaxYCorner,
            .layerMaxXMaxYCorner
        ])
        XCTAssertEqual(view.layer?.masksToBounds, false)
        XCTAssertNil(view.layer?.mask)
        XCTAssertNil(view.editorChromeFillLayer.superlayer)
        XCTAssertNil(view.editorChromeStrokeLayer.superlayer)
        XCTAssertNil(view.editorChromeFillLayer.path)
        XCTAssertNil(view.editorChromeStrokeLayer.path)
        XCTAssertNil(view.editorChromeMaskLayer.path)
    }

    func testMountedEditorUpdatesChromePathForFrameSizeChange() throws {
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 80, height: 40))
        view.configure(BlockInputConfiguration(style: BlockInputStyle(editorSurface: BlockInputEditorSurfaceStyle(
            editorBackgroundColor: nil,
            scrollBackgroundColor: nil,
            collectionBackgroundColor: nil,
            chrome: BlockInputEditorChromeStyle(
                fillColor: .systemRed,
                strokeColor: .systemGreen,
                borderWidth: 2,
                cornerRadius: 12
            )
        ))))
        let initialPath = try XCTUnwrap(view.editorChromeFillLayer.path)
        XCTAssertEqual(initialPath.boundingBox.width, 78)
        XCTAssertEqual(initialPath.boundingBox.height, 38)

        view.setFrameSize(NSSize(width: 120, height: 60))

        let resizedPath = try XCTUnwrap(view.editorChromeFillLayer.path)
        XCTAssertEqual(resizedPath.boundingBox.width, 118)
        XCTAssertEqual(resizedPath.boundingBox.height, 58)
    }

    func testMountedEditorReconfiguresChromeClipping() {
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(style: BlockInputStyle(editorSurface: BlockInputEditorSurfaceStyle(
            editorBackgroundColor: nil,
            scrollBackgroundColor: nil,
            collectionBackgroundColor: nil,
            chrome: BlockInputEditorChromeStyle(
                fillColor: .systemRed,
                cornerRadius: 12,
                clipsContentToShape: true
            )
        ))))
        XCTAssertTrue(view.layer?.mask === view.editorChromeMaskLayer)

        view.configure(BlockInputConfiguration(style: BlockInputStyle(editorSurface: BlockInputEditorSurfaceStyle(
            editorBackgroundColor: nil,
            scrollBackgroundColor: nil,
            collectionBackgroundColor: nil,
            chrome: BlockInputEditorChromeStyle(
                fillColor: .systemRed,
                cornerRadius: 12,
                clipsContentToShape: false
            )
        ))))

        XCTAssertNil(view.layer?.mask)
        XCTAssertTrue(view.editorChromeFillLayer.superlayer === view.layer)
    }

    func testMountedEditorUpdatesDynamicChromeStyleForAppearanceChange() throws {
        let dynamicFill = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .systemGreen : .systemRed
        }
        let view = BlockInputView()
        view.appearance = NSAppearance(named: .aqua)
        view.configure(BlockInputConfiguration(style: BlockInputStyle(editorSurface: BlockInputEditorSurfaceStyle(
            editorBackgroundColor: nil,
            scrollBackgroundColor: nil,
            collectionBackgroundColor: nil,
            chrome: BlockInputEditorChromeStyle(fillColor: dynamicFill)
        ))))
        let lightColor = try XCTUnwrap(NSColor(cgColor: try XCTUnwrap(view.editorChromeFillLayer.fillColor)))

        view.appearance = NSAppearance(named: .darkAqua)
        view.viewDidChangeEffectiveAppearance()
        let darkColor = try XCTUnwrap(NSColor(cgColor: try XCTUnwrap(view.editorChromeFillLayer.fillColor)))

        XCTAssertNotEqual(lightColor, darkColor)
    }
}

private struct ChromeCornerSamples {
    let topLeft: NSColor
    let topRight: NSColor
    let bottomLeft: NSColor
    let bottomRight: NSColor
}

@MainActor
private func cachedDisplayChromeCornerSamples(
    roundedCorners: BlockInputEditorChromeCorners,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> ChromeCornerSamples {
    let bitmap = try cachedDisplayChromeBitmap(roundedCorners: roundedCorners, file: file, line: line)
    let size = NSSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)

    return ChromeCornerSamples(
        topLeft: try XCTUnwrap(bitmap.colorAt(x: 2, y: 2), file: file, line: line),
        topRight: try XCTUnwrap(bitmap.colorAt(x: Int(size.width) - 3, y: 2), file: file, line: line),
        bottomLeft: try XCTUnwrap(bitmap.colorAt(x: 2, y: Int(size.height) - 3), file: file, line: line),
        bottomRight: try XCTUnwrap(bitmap.colorAt(x: Int(size.width) - 3, y: Int(size.height) - 3), file: file, line: line)
    )
}

private struct ChromeInteriorSamples {
    let fill: NSColor
    let leftStroke: NSColor
    let bottomStroke: NSColor
}

@MainActor
private func cachedDisplayChromeInteriorSamples(
    roundedCorners: BlockInputEditorChromeCorners,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> ChromeInteriorSamples {
    let bitmap = try cachedDisplayChromeBitmap(roundedCorners: roundedCorners, file: file, line: line)
    return ChromeInteriorSamples(
        fill: try XCTUnwrap(bitmap.colorAt(x: 40, y: 20), file: file, line: line),
        leftStroke: try XCTUnwrap(bitmap.colorAt(x: 1, y: 20), file: file, line: line),
        bottomStroke: try XCTUnwrap(bitmap.colorAt(x: 40, y: 38), file: file, line: line)
    )
}

@MainActor
private func cachedDisplayChromeBitmap(
    roundedCorners: BlockInputEditorChromeCorners,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> NSBitmapImageRep {
    let size = NSSize(width: 80, height: 40)
    let mounted = makeMountedBlockInputView(
        configuration: BlockInputConfiguration(style: BlockInputStyle(editorSurface: BlockInputEditorSurfaceStyle(
            editorBackgroundColor: nil,
            scrollBackgroundColor: nil,
            collectionBackgroundColor: nil,
            chrome: BlockInputEditorChromeStyle(
                fillColor: .systemRed,
                cornerRadius: 18,
                roundedCorners: roundedCorners,
                clipsContentToShape: true
            )
        ))),
        size: size,
        styleMask: [.borderless]
    )
    mounted.view.displayIfNeeded()
    mounted.view.layoutSubtreeIfNeeded()

    let bitmap = try XCTUnwrap(
        NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ),
        file: file,
        line: line
    )
    bitmap.size = size
    mounted.view.cacheDisplay(in: mounted.view.bounds, to: bitmap)
    return bitmap
}

private func assertFilled(
    _ color: NSColor,
    _ corner: String,
    roundedCorners: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let resolved = color.usingColorSpace(.deviceRGB) ?? color
    XCTAssertGreaterThan(
        resolved.alphaComponent,
        0.8,
        "Expected \(corner) to be filled for \(roundedCorners), got alpha \(resolved.alphaComponent)",
        file: file,
        line: line
    )
}

private func assertClipped(
    _ color: NSColor,
    _ corner: String,
    roundedCorners: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let resolved = color.usingColorSpace(.deviceRGB) ?? color
    XCTAssertLessThan(
        resolved.alphaComponent,
        0.2,
        "Expected \(corner) to be clipped for \(roundedCorners), got alpha \(resolved.alphaComponent)",
        file: file,
        line: line
    )
}
