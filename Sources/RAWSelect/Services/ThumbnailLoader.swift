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

    private init() {
        cache.countLimit = 800
        cache.totalCostLimit = 640 * 1024 * 1024   // ~640 MB, keeps full-res previews in check
    }

    private func key(_ url: URL, _ maxPixel: Int, _ fullQuality: Bool) -> NSString {
        "\(url.path)|\(maxPixel)|\(fullQuality ? "F" : "T")" as NSString
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
