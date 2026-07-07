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
        cache.countLimit = 600
    }

    private func key(_ url: URL, _ maxPixel: Int) -> NSString {
        "\(url.path)|\(maxPixel)" as NSString
    }

    /// Async thumbnail. Returns cached image immediately if present; otherwise
    /// decodes on the background queue. Cancels the decode if the Task is cancelled.
    func thumbnail(for url: URL, maxPixel: Int) async -> NSImage? {
        let cacheKey = key(url, maxPixel)
        if let cached = cache.object(forKey: cacheKey) { return cached }

        let operation = ThumbnailOperation(url: url, maxPixel: maxPixel)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<NSImage?, Never>) in
                operation.completionBlock = { [weak self] in
                    let image = operation.result
                    if let image { self?.cache.setObject(image, forKey: cacheKey) }
                    continuation.resume(returning: operation.isCancelled ? nil : image)
                }
                queue.addOperation(operation)
            }
        } onCancel: {
            operation.cancel()
        }
    }

    static func makeThumbnail(url: URL, maxPixel: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

private final class ThumbnailOperation: Operation, @unchecked Sendable {
    let url: URL
    let maxPixel: Int
    var result: NSImage?

    init(url: URL, maxPixel: Int) {
        self.url = url
        self.maxPixel = maxPixel
    }

    override func main() {
        if isCancelled { return }
        result = ThumbnailLoader.makeThumbnail(url: url, maxPixel: maxPixel)
    }
}
