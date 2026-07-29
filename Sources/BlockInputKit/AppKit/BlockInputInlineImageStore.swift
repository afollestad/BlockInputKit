import AppKit

/// Value snapshot of loaded inline-image sizes, keyed by raw source string.
///
/// Attribute application and offscreen height measurement both consume this
/// snapshot so mounted layout and measured layout reserve identical geometry.
struct BlockInputInlineImageSizes {
    static let empty = BlockInputInlineImageSizes(sizes: [:])

    private let sizes: [String: NSSize]

    init(sizes: [String: NSSize]) {
        self.sizes = sizes
    }

    func size(forSource source: String) -> NSSize? {
        sizes[source]
    }
}

/// Editor-scoped cache and loader for images rendered inline within text lines.
///
/// One store serves every block item in a `BlockInputView` so repeated sources
/// load once, and its change callback lets the editor refresh mounted rows and
/// invalidate heights when dimensions arrive.
@MainActor
final class BlockInputInlineImageStore {
    enum ImageState {
        case loading
        case loaded(NSImage, NSSize)
        case failed
    }

    /// Called with the raw source string after a load finishes (or fails).
    var onImageStateChange: ((String) -> Void)?

    private var states: [String: ImageState] = [:]
    private var loadTasks: [String: Task<Void, Never>] = [:]

    func sizesSnapshot() -> BlockInputInlineImageSizes {
        var sizes: [String: NSSize] = [:]
        for (source, state) in states {
            if case let .loaded(_, size) = state {
                sizes[source] = size
            }
        }
        return BlockInputInlineImageSizes(sizes: sizes)
    }

    func image(forSource source: String) -> NSImage? {
        guard case let .loaded(image, _) = states[source] else {
            return nil
        }
        return image
    }

    func hasFailed(source: String) -> Bool {
        guard case .failed = states[source] else {
            return false
        }
        return true
    }

    /// Starts a load for the source unless one already finished or is in flight.
    func ensureLoad(for image: BlockInputImage, context: BlockInputImageBlockLoadingContext) {
        let source = image.source
        guard states[source] == nil else {
            return
        }
        guard let resolvedURL = image.resolvedURL(relativeTo: context.baseURL),
              allowsLoading(resolvedURL, context: context) else {
            states[source] = .failed
            return
        }
        states[source] = .loading
        let request = BlockInputImageLoadRequest(
            image: image,
            resolvedURL: resolvedURL,
            cacheKey: image.cacheKey(resolvedURL: resolvedURL, maximumPixelDimension: context.maximumPixelDimension),
            maxSourceBytes: context.maximumSourceBytes,
            maxPixelDimension: context.maximumPixelDimension,
            diskCache: context.diskCache
        )
        let loader = context.loader
        loadTasks[source] = Task { [weak self] in
            do {
                let loaded = try await loader.loadImage(request)
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run {
                    self?.finishLoad(loaded, source: source)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run {
                    self?.finishLoadFailure(source: source)
                }
            }
        }
    }

    private func finishLoad(_ loaded: BlockInputLoadedImage, source: String) {
        loadTasks[source] = nil
        guard let nsImage = NSImage(data: loaded.data), nsImage.size.width > 0, nsImage.size.height > 0 else {
            states[source] = .failed
            onImageStateChange?(source)
            return
        }
        // NSImage.size already honors DPI metadata, matching how points render on screen.
        states[source] = .loaded(nsImage, nsImage.size)
        onImageStateChange?(source)
    }

    private func finishLoadFailure(source: String) {
        loadTasks[source] = nil
        states[source] = .failed
        onImageStateChange?(source)
    }

    private func allowsLoading(_ url: URL, context: BlockInputImageBlockLoadingContext) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return true
        }
        return context.allowsRemoteLoading
    }
}
