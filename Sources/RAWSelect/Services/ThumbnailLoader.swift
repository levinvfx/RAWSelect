import AppKit
import ImageIO
import CoreGraphics
import CoreImage

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

    /// Decodes a large, sharp image for the zoom loupe WITHOUT touching the shared
    /// preview cache. A full-res RAW is 200+ MB — caching it would evict every warm
    /// thumbnail and thrash. The caller holds the single result and frees it when
    /// leaving the zoom. Cancellable; returns nil if the Task is cancelled.
    func fullDecode(for url: URL, maxPixel: Int) async -> NSImage? {
        // 1) Sharpest: develop the RAW at native resolution.
        if let developed = await decodeOnce(url: url, maxPixel: maxPixel, fullQuality: true) {
            return developed
        }
        // 2) The OS has no codec for this RAW (e.g. Sony A7 V). ImageIO only surfaces a
        //    tiny embedded thumbnail, but the file usually still contains a full-res
        //    embedded JPEG — extract the largest one ourselves.
        if let embedded = await Task.detached(priority: .userInitiated, operation: {
            ThumbnailLoader.largestEmbeddedJPEG(url: url, maxPixel: maxPixel)
        }).value {
            return embedded
        }
        // 3) Last resort: whatever ImageIO offers as embedded preview.
        return await decodeOnce(url: url, maxPixel: maxPixel, fullQuality: false)
    }

    /// Recovers a full-resolution preview from a RAW the OS can't develop by scanning
    /// the raw bytes for embedded JPEG streams and decoding the largest one. Returns
    /// nil if the file has no usable embedded JPEG. Downsamples to `maxPixel` (never
    /// upscales). Only used on the zoom fallback path, never during fast browsing.
    static func largestEmbeddedJPEG(url: URL, maxPixel: Int) -> NSImage? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        guard let range = data.withUnsafeBytes({ (raw: UnsafeRawBufferPointer) -> Range<Int>? in
            largestJPEGRange(raw.bindMemory(to: UInt8.self))
        }) else { return nil }

        let jpeg = data.subdata(in: range)
        guard let src = CGImageSourceCreateWithData(jpeg as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard var cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        // The extracted JPEG carries NO orientation tag, but the RAW container does
        // (e.g. A7 V portrait shots = orientation 8). The normal preview applies the
        // container orientation, so apply it here too — otherwise the sharp zoom would
        // appear rotated relative to the preview.
        if let orientation = containerOrientation(url), orientation != 1,
           let rotated = reoriented(cg, exifOrientation: orientation) {
            cg = rotated
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private static let ciContext = CIContext(options: nil)

    /// EXIF orientation of the RAW container (nil if unknown / normal).
    private static func containerOrientation(_ url: URL) -> UInt32? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let o = (props[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value else { return nil }
        return o
    }

    /// Applies an EXIF orientation to a CGImage (bakes the rotation into new pixels).
    private static func reoriented(_ cg: CGImage, exifOrientation o: UInt32) -> CGImage? {
        let ci = CIImage(cgImage: cg).oriented(forExifOrientation: Int32(o))
        return ciContext.createCGImage(ci, from: ci.extent)
    }

    /// Byte range (SOI…EOI) of the embedded JPEG with the largest pixel dimensions.
    private static func largestJPEGRange(_ p: UnsafeBufferPointer<UInt8>) -> Range<Int>? {
        let n = p.count
        // Collect all JPEG start-of-image markers (FF D8 FF).
        var sois: [Int] = []
        var i = 0
        while i + 2 < n {
            if p[i] == 0xFF, p[i + 1] == 0xD8, p[i + 2] == 0xFF { sois.append(i); i += 3 }
            else { i += 1 }
        }
        guard !sois.isEmpty else { return nil }
        // Pick the SOI whose SOF frame is the largest.
        var bestIdx = -1, bestArea = 0
        for (k, soi) in sois.enumerated() {
            if let (w, h) = sofDimensions(p, from: soi), w * h > bestArea { bestArea = w * h; bestIdx = k }
        }
        guard bestIdx >= 0 else { return nil }
        let start = sois[bestIdx]
        let hardEnd = (bestIdx + 1 < sois.count) ? sois[bestIdx + 1] : n
        // Trim to the last EOI (FF D9) before the next stream.
        var end = hardEnd
        var j = hardEnd - 2
        while j > start {
            if p[j] == 0xFF, p[j + 1] == 0xD9 { end = j + 2; break }
            j -= 1
        }
        return start..<end
    }

    /// Reads a JPEG stream's frame dimensions (width, height) from its SOFn marker.
    private static func sofDimensions(_ p: UnsafeBufferPointer<UInt8>, from soi: Int) -> (Int, Int)? {
        let n = p.count
        var i = soi + 2
        while i + 9 < n {
            if p[i] != 0xFF { i += 1; continue }
            let marker = p[i + 1]
            if marker == 0xD8 || marker == 0xD9 || (0xD0...0xD7).contains(marker) { i += 2; continue }
            let seglen = (Int(p[i + 2]) << 8) | Int(p[i + 3])
            let isSOF = (0xC0...0xCF).contains(marker) && marker != 0xC4 && marker != 0xC8 && marker != 0xCC
            if isSOF {
                let h = (Int(p[i + 5]) << 8) | Int(p[i + 6])
                let w = (Int(p[i + 7]) << 8) | Int(p[i + 8])
                return (w, h)
            }
            if seglen <= 0 { break }
            i += 2 + seglen
        }
        return nil
    }

    /// One cancellable decode on the shared queue, uncached. Returns nil if the Task
    /// is cancelled or ImageIO cannot produce an image.
    private func decodeOnce(url: URL, maxPixel: Int, fullQuality: Bool) async -> NSImage? {
        let operation = ThumbnailOperation(url: url, maxPixel: maxPixel, fullQuality: fullQuality)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<NSImage?, Never>) in
                operation.completionBlock = {
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
