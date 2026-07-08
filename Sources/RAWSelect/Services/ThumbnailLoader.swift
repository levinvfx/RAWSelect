import AppKit
import ImageIO
import CoreGraphics

/// Loads thumbnails/previews via ImageIO. For RAW files this reads the embedded
/// JPEG preview instead of developing the file, which keeps it fast. Results are
/// cached in memory and work is limited to a background queue.
final class ThumbnailLoader {
    static let shared = ThumbnailLoader()

    private let cache = NSCache<NSString, NSImage>()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = max(2, ProcessInfo.processInfo.activeProcessorCount - 1)
        q.qualityOfService = .userInitiated
        return q
    }()

    private let lock = NSLock()
    private var inFlight = Set<String>()

    private init() {
        cache.countLimit = 1200
        cache.totalCostLimit = 1024 * 1024 * 1024   // ~1 GB, keeps many HD previews warm
    }

    private func key(_ url: URL, _ maxPixel: Int, _ fullQuality: Bool) -> NSString {
        "\(url.path)|\(maxPixel)|\(fullQuality ? "F" : "T")" as NSString
    }

    /// Warms the cache for an image without waiting for the result. Skips work if
    /// the image is already cached or currently being decoded.
    func prefetch(for url: URL, maxPixel: Int, fullQuality: Bool) {
        let cacheKey = key(url, maxPixel, fullQuality)
        if cache.object(forKey: cacheKey) != nil { return }
        let keyString = cacheKey as String
        lock.lock()
        if inFlight.contains(keyString) { lock.unlock(); return }
        inFlight.insert(keyString)
        lock.unlock()

        let operation = ThumbnailOperation(url: url, maxPixel: maxPixel, fullQuality: fullQuality)
        operation.queuePriority = .low
        operation.completionBlock = { [weak self] in
            guard let self else { return }
            if let image = operation.result { self.cache.setObject(image, forKey: cacheKey, cost: operation.cost) }
            self.lock.lock(); self.inFlight.remove(keyString); self.lock.unlock()
        }
        queue.addOperation(operation)
    }

    /// Returns the already-cached image for this exact request, or nil. Never
    /// decodes — used to paint a frame *synchronously* while fast-browsing, so
    /// the image shows before any `await` suspension point (and therefore even
    /// when the surrounding task is cancelled a moment later).
    func cached(for url: URL, maxPixel: Int, fullQuality: Bool = false) -> NSImage? {
        cache.object(forKey: key(url, maxPixel, fullQuality))
    }

    /// How a preview should be rendered for a file.
    struct PreviewPlan: Equatable { let maxPixel: Int; let fullQuality: Bool }

    /// Chooses how to render a preview. Deliberately does NO disk I/O so it is safe
    /// to call on the main thread for every frame while fast-browsing:
    ///  - RAW → the embedded camera preview, downscaled to the target (fast/light).
    ///  - everything else → rendered from the actual image (`fullQuality`). Small
    ///    files stay native & razor-sharp because ImageIO never upscales past the
    ///    source; big files are downsampled to the target. No per-file header read.
    func previewPlan(for url: URL, targetLongEdge: Int) -> PreviewPlan {
        PreviewPlan(maxPixel: targetLongEdge, fullQuality: !PhotoTypes.isRaw(url))
    }

    /// Warms tiny thumbnails for a whole folder at very low priority.
    func warmTiny(_ urls: [URL], maxPixel: Int) {
        for url in urls { prefetch(for: url, maxPixel: maxPixel, fullQuality: false) }
    }

    /// Empties the in-memory cache (used by Settings → Cache jetzt leeren).
    func clearCache() {
        cache.removeAllObjects()
        lock.lock(); inFlight.removeAll(); lock.unlock()
    }

    /// Sets the maximum number of concurrent decode jobs (Settings).
    func setMaxConcurrent(_ n: Int) {
        queue.maxConcurrentOperationCount = max(1, n)
    }

    /// Async thumbnail/preview. Returns a cached image immediately if present;
    /// otherwise decodes on the background queue. Cancels if the Task is cancelled.
    ///
    /// - Parameter fullQuality: when true the image is rendered from the full
    ///   image (sharp at any size – used for the large loupe preview). When false
    ///   the embedded preview is used if present (fast – used for grid thumbnails).
    func thumbnail(for url: URL, maxPixel: Int, fullQuality: Bool = false) async -> NSImage? {
        let cacheKey = key(url, maxPixel, fullQuality)
        if let cached = cache.object(forKey: cacheKey) { return cached }

        let operation = ThumbnailOperation(url: url, maxPixel: maxPixel, fullQuality: fullQuality)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<NSImage?, Never>) in
                operation.completionBlock = { [weak self] in
                    if let image = operation.result {
                        self?.cache.setObject(image, forKey: cacheKey, cost: operation.cost)
                    }
                    continuation.resume(returning: operation.isCancelled ? nil : operation.result)
                }
                queue.addOperation(operation)
            }
        } onCancel: {
            operation.cancel()
        }
    }

    static func makeThumbnail(url: URL, maxPixel: Int, fullQuality: Bool = false) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            (fullQuality ? kCGImageSourceCreateThumbnailFromImageAlways
                         : kCGImageSourceCreateThumbnailFromImageIfAbsent): true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Convenience returning an NSImage (used by the self-test).
    static func makeThumbnail(url: URL, maxPixel: Int) -> NSImage? {
        guard let cg = makeThumbnail(url: url, maxPixel: maxPixel, fullQuality: false) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

private final class ThumbnailOperation: Operation, @unchecked Sendable {
    let url: URL
    let maxPixel: Int
    let fullQuality: Bool
    var result: NSImage?
    var cost: Int = 0

    init(url: URL, maxPixel: Int, fullQuality: Bool) {
        self.url = url
        self.maxPixel = maxPixel
        self.fullQuality = fullQuality
    }

    override func main() {
        if isCancelled { return }
        guard let cg = ThumbnailLoader.makeThumbnail(url: url, maxPixel: maxPixel, fullQuality: fullQuality) else { return }
        cost = cg.width * cg.height * 4
        result = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
