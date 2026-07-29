import AppKit
import Foundation
import ImageIO

/// Natural pixel dimensions resolved for an image source.
public struct BlockInputImageDimensions: Equatable, Codable, Sendable {
    /// Pixel width after honoring image orientation metadata.
    public var width: Int
    /// Pixel height after honoring image orientation metadata.
    public var height: Int

    /// Creates positive image dimensions.
    public init(width: Int, height: Int) {
        self.width = max(1, width)
        self.height = max(1, height)
    }
}

/// Loaded image bytes and metadata returned by an image loader.
public struct BlockInputLoadedImage: Equatable, Sendable {
    /// Original image bytes.
    public var data: Data
    /// Natural pixel dimensions from image metadata.
    public var dimensions: BlockInputImageDimensions

    /// Creates loaded image data with resolved dimensions.
    public init(data: Data, dimensions: BlockInputImageDimensions) {
        self.data = data
        self.dimensions = dimensions
    }
}

/// Request passed to a host or built-in image loader.
public struct BlockInputImageLoadRequest: Sendable {
    /// Image block payload requesting a load.
    public var image: BlockInputImage
    /// Absolute URL used for loading.
    public var resolvedURL: URL
    /// Cache key normalized for this source and size policy.
    public var cacheKey: String
    /// Largest source payload accepted by the default loader.
    public var maxSourceBytes: Int
    /// Largest decoded width or height accepted by the default loader.
    public var maxPixelDimension: Int
    /// Optional disk cache. The default loader uses it only for remote URLs.
    public var diskCache: (any BlockInputImageDiskCaching)?

    /// Creates an image load request.
    public init(
        image: BlockInputImage,
        resolvedURL: URL,
        cacheKey: String,
        maxSourceBytes: Int,
        maxPixelDimension: Int,
        diskCache: (any BlockInputImageDiskCaching)?
    ) {
        self.image = image
        self.resolvedURL = resolvedURL
        self.cacheKey = cacheKey
        self.maxSourceBytes = maxSourceBytes
        self.maxPixelDimension = maxPixelDimension
        self.diskCache = diskCache
    }
}

/// Host-customizable image loading behavior.
public protocol BlockInputImageLoading: Sendable {
    /// Loads image bytes and natural dimensions for a block image request.
    func loadImage(_ request: BlockInputImageLoadRequest) async throws -> BlockInputLoadedImage
}

/// Disk cache entry for remote image bytes and dimensions.
public struct BlockInputImageDiskCacheEntry: Equatable, Codable, Sendable {
    /// Cached image bytes.
    public var data: Data
    /// Cached natural image dimensions.
    public var dimensions: BlockInputImageDimensions

    /// Creates a disk cache entry.
    public init(data: Data, dimensions: BlockInputImageDimensions) {
        self.data = data
        self.dimensions = dimensions
    }
}

/// Host-customizable disk cache for remote image loads.
public protocol BlockInputImageDiskCaching: Sendable {
    /// Returns a cached remote image entry for a normalized cache key.
    func cachedImage(forKey key: String) async throws -> BlockInputImageDiskCacheEntry?
    /// Stores a remote image entry for a normalized cache key.
    func storeImage(_ entry: BlockInputImageDiskCacheEntry, forKey key: String) async throws
    /// Performs best-effort cleanup according to the cache implementation's limits.
    func cleanup() async throws
}

/// Built-in async image loader with memory caching, request dedupe, and optional remote disk caching.
public actor BlockInputDefaultImageLoader: BlockInputImageLoading {
    private var memoryCache: [String: BlockInputLoadedImage] = [:]
    private var inFlightLoads: [String: Task<BlockInputLoadedImage, Error>] = [:]

    /// Creates the default image loader.
    public init() {}

    /// Loads image bytes and dimensions, reusing in-flight and memory-cached work for matching requests.
    public func loadImage(_ request: BlockInputImageLoadRequest) async throws -> BlockInputLoadedImage {
        if let cached = memoryCache[request.cacheKey] {
            return cached
        }
        if let inFlightLoad = inFlightLoads[request.cacheKey] {
            return try await inFlightLoad.value
        }
        let task = Task {
            try await Self.loadUncached(request)
        }
        inFlightLoads[request.cacheKey] = task
        do {
            let loaded = try await task.value
            memoryCache[request.cacheKey] = loaded
            inFlightLoads[request.cacheKey] = nil
            return loaded
        } catch {
            inFlightLoads[request.cacheKey] = nil
            throw error
        }
    }

    private static func loadUncached(_ request: BlockInputImageLoadRequest) async throws -> BlockInputLoadedImage {
        if request.resolvedURL.isFileURL {
            return try loadedImage(from: Data(contentsOf: request.resolvedURL), request: request)
        }
        if let diskCache = request.diskCache,
           let cached = try await diskCache.cachedImage(forKey: request.cacheKey) {
            return BlockInputLoadedImage(data: cached.data, dimensions: cached.dimensions)
        }
        let (data, _) = try await URLSession.shared.data(from: request.resolvedURL)
        let loaded = try loadedImage(from: data, request: request)
        if let diskCache = request.diskCache {
            try await diskCache.storeImage(
                BlockInputImageDiskCacheEntry(data: loaded.data, dimensions: loaded.dimensions),
                forKey: request.cacheKey
            )
        }
        return loaded
    }

    private static func loadedImage(from data: Data, request: BlockInputImageLoadRequest) throws -> BlockInputLoadedImage {
        guard data.count <= request.maxSourceBytes else {
            throw BlockInputImageLoadingError.sourceTooLarge
        }
        let dimensions = try imageDimensions(from: data)
        guard max(dimensions.width, dimensions.height) <= request.maxPixelDimension else {
            throw BlockInputImageLoadingError.imageTooLarge
        }
        return BlockInputLoadedImage(data: data, dimensions: dimensions)
    }

    private static func imageDimensions(from data: Data) throws -> BlockInputImageDimensions {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return try vectorImageDimensions(from: data)
        }
        let orientation = properties[kCGImagePropertyOrientation] as? Int
        if orientation == 5 || orientation == 6 || orientation == 7 || orientation == 8 {
            return BlockInputImageDimensions(width: height, height: width)
        }
        return BlockInputImageDimensions(width: width, height: height)
    }

    /// ImageIO cannot read vector formats like SVG (common for remote badges), but
    /// `NSImage` can; fall back to its decoded point size for dimension probing.
    private static func vectorImageDimensions(from data: Data) throws -> BlockInputImageDimensions {
        guard let image = NSImage(data: data),
              image.size.width > 0,
              image.size.height > 0 else {
            throw BlockInputImageLoadingError.unsupportedImage
        }
        return BlockInputImageDimensions(
            width: Int(image.size.width.rounded()),
            height: Int(image.size.height.rounded())
        )
    }
}

/// Built-in file-backed disk cache for remote images.
public actor BlockInputDefaultImageDiskCache: BlockInputImageDiskCaching {
    private let directoryURL: URL
    private let maximumBytes: Int
    private let fileManager: FileManager

    /// Creates a remote image disk cache.
    public init(
        directoryURL: URL? = nil,
        maximumBytes: Int = 256 * 1024 * 1024,
        fileManager: FileManager = .default
    ) {
        self.directoryURL = directoryURL ?? Self.defaultDirectoryURL()
        self.maximumBytes = max(0, maximumBytes)
        self.fileManager = fileManager
    }

    /// Returns a cached remote image entry for a normalized cache key.
    public func cachedImage(forKey key: String) async throws -> BlockInputImageDiskCacheEntry? {
        let dataURL = dataFileURL(forKey: key)
        let metadataURL = metadataFileURL(forKey: key)
        guard fileManager.fileExists(atPath: dataURL.path),
              fileManager.fileExists(atPath: metadataURL.path) else {
            return nil
        }
        let metadata = try JSONDecoder().decode(CacheMetadata.self, from: Data(contentsOf: metadataURL))
        try touch(dataURL)
        try touch(metadataURL)
        return BlockInputImageDiskCacheEntry(
            data: try Data(contentsOf: dataURL),
            dimensions: metadata.dimensions
        )
    }

    /// Stores a remote image entry for a normalized cache key.
    public func storeImage(_ entry: BlockInputImageDiskCacheEntry, forKey key: String) async throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try entry.data.write(to: dataFileURL(forKey: key), options: [.atomic])
        let metadata = CacheMetadata(dimensions: entry.dimensions)
        try JSONEncoder().encode(metadata).write(to: metadataFileURL(forKey: key), options: [.atomic])
        try await cleanup()
    }

    /// Removes least-recently-used files until the cache is under its byte limit.
    public func cleanup() async throws {
        guard maximumBytes > 0,
              let files = try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
              ) else {
            return
        }
        let entries = files.compactMap { url -> CacheFile? in
            guard let resourceValues = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else {
                return nil
            }
            return CacheFile(
                url: url,
                modifiedAt: resourceValues.contentModificationDate ?? .distantPast,
                byteCount: resourceValues.fileSize ?? 0
            )
        }
        var totalBytes = entries.reduce(0) { $0 + $1.byteCount }
        for entry in entries.sorted(by: { $0.modifiedAt < $1.modifiedAt }) where totalBytes > maximumBytes {
            try? fileManager.removeItem(at: entry.url)
            totalBytes -= entry.byteCount
        }
    }

    /// Default cache directory under the user caches folder.
    public static func defaultDirectoryURL() -> URL {
        let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return cachesURL.appendingPathComponent("BlockInputKit/RemoteImages", isDirectory: true)
    }

    private func dataFileURL(forKey key: String) -> URL {
        directoryURL.appendingPathComponent(cacheFilename(forKey: key, extension: "img"), isDirectory: false)
    }

    private func metadataFileURL(forKey key: String) -> URL {
        directoryURL.appendingPathComponent(cacheFilename(forKey: key, extension: "json"), isDirectory: false)
    }

    private func cacheFilename(forKey key: String, extension pathExtension: String) -> String {
        Data(key.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .appending(".\(pathExtension)")
    }

    private func touch(_ url: URL) throws {
        try fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }
}

/// Error thrown by the default image loader.
public enum BlockInputImageLoadingError: Error, Equatable, Sendable {
    /// Source bytes exceed the configured limit.
    case sourceTooLarge
    /// Decoded dimensions exceed the configured limit.
    case imageTooLarge
    /// Image metadata could not be decoded.
    case unsupportedImage
}

private struct CacheMetadata: Codable {
    var dimensions: BlockInputImageDimensions
}

private struct CacheFile {
    var url: URL
    var modifiedAt: Date
    var byteCount: Int
}
