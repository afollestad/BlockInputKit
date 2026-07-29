import Foundation
import XCTest
@testable import BlockInputKit

final class BlockInputImageLoadingTests: XCTestCase {
    func testConfigurationProvidesDefaultImageLoadingSettings() {
        let configuration = BlockInputConfiguration()

        XCTAssertTrue(configuration.allowsRemoteImageLoading)
        XCTAssertEqual(configuration.maximumImageSourceBytes, 20 * 1024 * 1024)
        XCTAssertEqual(configuration.maximumImagePixelDimension, 8_192)
        XCTAssertNotNil(configuration.imageDiskCache)
    }

    func testImageResolvesRelativeURLAndBuildsCacheKey() throws {
        let image = BlockInputImage(source: "assets/image.png")
        let baseURL = try XCTUnwrap(URL(string: "https://example.com/docs/"))
        let resolvedURL = try XCTUnwrap(image.resolvedURL(relativeTo: baseURL))

        XCTAssertEqual(resolvedURL.absoluteString, "https://example.com/docs/assets/image.png")
        XCTAssertEqual(
            image.cacheKey(resolvedURL: resolvedURL, loaderVersion: "test", maximumPixelDimension: 1200),
            "test|https://example.com/docs/assets/image.png|1200"
        )
    }

    func testDefaultLoaderReadsLocalImageDimensions() async throws {
        let imageURL = try temporaryPNGURL()
        let image = BlockInputImage(source: imageURL.absoluteString)
        let request = BlockInputImageLoadRequest(
            image: image,
            resolvedURL: imageURL,
            cacheKey: "local",
            maxSourceBytes: 1024 * 1024,
            maxPixelDimension: 100,
            diskCache: nil
        )

        let loaded = try await BlockInputDefaultImageLoader().loadImage(request)

        XCTAssertEqual(loaded.dimensions, BlockInputImageDimensions(width: 1, height: 1))
        XCTAssertFalse(loaded.data.isEmpty)
    }

    func testDefaultLoaderUsesMemoryCacheForRepeatedLoads() async throws {
        let imageURL = try temporaryPNGURL()
        let request = BlockInputImageLoadRequest(
            image: BlockInputImage(source: imageURL.absoluteString),
            resolvedURL: imageURL,
            cacheKey: "memory",
            maxSourceBytes: 1024 * 1024,
            maxPixelDimension: 100,
            diskCache: nil
        )
        let loader = BlockInputDefaultImageLoader()

        let firstLoad = try await loader.loadImage(request)
        try FileManager.default.removeItem(at: imageURL)
        let secondLoad = try await loader.loadImage(request)

        XCTAssertEqual(secondLoad, firstLoad)
    }

    func testDefaultLoaderRejectsOversizedSourceBytes() async throws {
        let imageURL = try temporaryPNGURL()
        let request = BlockInputImageLoadRequest(
            image: BlockInputImage(source: imageURL.absoluteString),
            resolvedURL: imageURL,
            cacheKey: "oversized",
            maxSourceBytes: 1,
            maxPixelDimension: 100,
            diskCache: nil
        )

        do {
            _ = try await BlockInputDefaultImageLoader().loadImage(request)
            XCTFail("Expected oversized source to fail.")
        } catch BlockInputImageLoadingError.sourceTooLarge {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDefaultLoaderUsesDiskCacheForRemoteImageWithoutNetwork() async throws {
        let cache = RecordingImageDiskCache()
        let imageData = try Self.pngData()
        let dimensions = BlockInputImageDimensions(width: 1, height: 1)
        try await cache.storeImage(
            BlockInputImageDiskCacheEntry(data: imageData, dimensions: dimensions),
            forKey: "remote"
        )
        let url = try XCTUnwrap(URL(string: "https://example.com/image.png"))
        let request = BlockInputImageLoadRequest(
            image: BlockInputImage(source: url.absoluteString),
            resolvedURL: url,
            cacheKey: "remote",
            maxSourceBytes: 1024 * 1024,
            maxPixelDimension: 100,
            diskCache: cache
        )

        let loaded = try await BlockInputDefaultImageLoader().loadImage(request)

        XCTAssertEqual(loaded.data, imageData)
        XCTAssertEqual(loaded.dimensions, dimensions)
        let cachedKeys = await cache.cachedKeys
        XCTAssertEqual(cachedKeys, ["remote"])
    }

    func testDefaultLoaderReadsSVGDimensionsThroughNSImageFallback() async throws {
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="23" height="20"><rect width="23" height="20" fill="orange"/></svg>"#
        let svgURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("svg")
        try XCTUnwrap(svg.data(using: .utf8)).write(to: svgURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: svgURL)
        }
        let request = BlockInputImageLoadRequest(
            image: BlockInputImage(source: svgURL.absoluteString),
            resolvedURL: svgURL,
            cacheKey: "svg",
            maxSourceBytes: 1024 * 1024,
            maxPixelDimension: 100,
            diskCache: nil
        )

        let loaded = try await BlockInputDefaultImageLoader().loadImage(request)

        XCTAssertEqual(loaded.dimensions, BlockInputImageDimensions(width: 23, height: 20))
    }

    private func temporaryPNGURL() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try Self.pngData().write(to: url)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private static func pngData() throws -> Data {
        try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/lC6x4wAAAABJRU5ErkJggg=="))
    }
}

private actor RecordingImageDiskCache: BlockInputImageDiskCaching {
    private var entries: [String: BlockInputImageDiskCacheEntry] = [:]
    private(set) var cachedKeys: [String] = []

    func cachedImage(forKey key: String) async throws -> BlockInputImageDiskCacheEntry? {
        cachedKeys.append(key)
        return entries[key]
    }

    func storeImage(_ entry: BlockInputImageDiskCacheEntry, forKey key: String) async throws {
        entries[key] = entry
    }

    func cleanup() async throws {}
}
