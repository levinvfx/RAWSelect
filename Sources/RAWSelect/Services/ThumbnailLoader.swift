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
    // Coalescing registry (guarded by `lock`): one running decode per key, with every waiter
    // attached to it. A prefetch and a visible request for the SAME image now share ONE decode
    // instead of two. `prefetchWanted` keeps a shared op alive when only a prefetch wants it.
    private var ops: [String: ThumbnailOperation] = [:]
    private var waiters: [String: [UUID: CheckedContinuation<NSImage?, Never>]] = [:]
    private var prefetchWanted = Set<String>()
    /// Total decodes actually started — lets the self-test prove requests are coalesced.
    private(set) var decodeCount = 0

    private init() {
        cache.countLimit = 1200
        cache.totalCostLimit = 1024 * 1024 * 1024   // ~1 GB, keeps many HD previews warm
    }

    private func key(_ url: URL, _ maxPixel: Int, _ fullQuality: Bool) -> NSString {
        "\(url.path)|\(maxPixel)|\(fullQuality ? "F" : "T")" as NSString
    }

    /// Warms the cache for an image without waiting for the result. Skips work if
    /// the image is already cached or currently being decoded (shares that decode).
    func prefetch(for url: URL, maxPixel: Int, fullQuality: Bool) {
        let cacheKey = key(url, maxPixel, fullQuality)
        if cache.object(forKey: cacheKey) != nil { return }
        let k = cacheKey as String
        lock.lock()
        prefetchWanted.insert(k)
        if ops[k] == nil {
            startOp(key: k, url: url, maxPixel: maxPixel, fullQuality: fullQuality, priority: .low)
        }
        lock.unlock()
    }

    /// Starts one shared decode for `key` and wires its completion to fan the result out to
    /// every waiter. MUST be called with `lock` held.
    private func startOp(key k: String, url: URL, maxPixel: Int, fullQuality: Bool,
                         priority: Operation.QueuePriority) {
        let operation = ThumbnailOperation(url: url, maxPixel: maxPixel, fullQuality: fullQuality)
        operation.queuePriority = priority
        ops[k] = operation
        decodeCount += 1
        let cacheKey = k as NSString
        operation.completionBlock = { [weak self] in
            guard let self else { return }
            if let image = operation.result { self.cache.setObject(image, forKey: cacheKey, cost: operation.cost) }
            let result = operation.isCancelled ? nil : operation.result
            self.lock.lock()
            let conts = self.waiters.removeValue(forKey: k) ?? [:]
            self.ops[k] = nil
            self.prefetchWanted.remove(k)
            self.lock.unlock()
            for cont in conts.values { cont.resume(returning: result) }
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

    /// Empties the in-memory cache (used by Settings → Cache jetzt leeren). Running decodes are
    /// left alone — they finish and resume their waiters; dropping them would hang the awaiters.
    func clearCache() {
        cache.removeAllObjects()
        lock.lock(); prefetchWanted.removeAll(); lock.unlock()
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
        let k = cacheKey as String
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<NSImage?, Never>) in
                lock.lock()
                if let cached = cache.object(forKey: cacheKey) {   // filled in while we set up
                    lock.unlock(); continuation.resume(returning: cached); return
                }
                waiters[k, default: [:]][id] = continuation
                if let existing = ops[k] {
                    existing.queuePriority = .normal               // a visible request now waits on it
                } else {
                    startOp(key: k, url: url, maxPixel: maxPixel, fullQuality: fullQuality, priority: .normal)
                }
                lock.unlock()
            }
        } onCancel: {
            // Drop only THIS waiter. Cancel the shared decode only when nobody else waits and no
            // prefetch still wants it — otherwise a disappearing grid cell would kill a decode a
            // visible photo (or a prefetch) still needs.
            lock.lock()
            let cont = waiters[k]?.removeValue(forKey: id)
            if waiters[k]?.isEmpty == true { waiters[k] = nil }
            if (waiters[k]?.isEmpty ?? true), !prefetchWanted.contains(k), let op = ops[k] {
                op.cancel(); ops[k] = nil
            }
            lock.unlock()
            cont?.resume(returning: nil)
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
        guard let cg = largestEmbeddedJPEGCG(url: url, maxPixel: maxPixel) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    /// The decoded, correctly-oriented CGImage of the largest embedded JPEG (true
    /// pixel dimensions — used by the diagnosis so it reports honest sizes, not the
    /// backing-scaled NSImage representation).
    static func largestEmbeddedJPEGCG(url: URL, maxPixel: Int) -> CGImage? {
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
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        // The extracted JPEG usually has NO orientation tag, but the RAW container does
        // (e.g. A7 V portrait shots = orientation 8). Prefer the container orientation;
        // if it has none, fall back to the JPEG's own tag (other brands may set it).
        // Apply it so the sharp zoom matches the (correctly rotated) preview.
        if let orientation = containerOrientation(url) ?? imageOrientation(src), orientation != 1,
           let rotated = reoriented(cg, exifOrientation: orientation) {
            return rotated
        }
        return cg
    }

    private static let ciContext = CIContext(options: nil)

    /// EXIF orientation of the RAW container (nil if unknown / normal).
    private static func containerOrientation(_ url: URL) -> UInt32? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return imageOrientation(src)
    }

    /// EXIF orientation stored in an image source's primary image (nil if none).
    private static func imageOrientation(_ src: CGImageSource) -> UInt32? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let o = (props[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value else { return nil }
        return o
    }

    /// Applies an EXIF orientation to a CGImage (bakes the rotation into new pixels).
    private static func reoriented(_ cg: CGImage, exifOrientation o: UInt32) -> CGImage? {
        let ci = CIImage(cgImage: cg).oriented(forExifOrientation: Int32(o))
        return ciContext.createCGImage(ci, from: ci.extent)
    }

    /// Byte range (SOI…EOI) of the embedded JPEG with the largest pixel dimensions.
    /// Internal (not private) so the self-test can exercise this byte parser directly —
    /// it is the riskiest un-GUI-testable code (a bad SOI/EOI → wrong size or a crash).
    static func largestJPEGRange(_ p: UnsafeBufferPointer<UInt8>) -> Range<Int>? {
        let n = p.count
        // Collect all JPEG start-of-image markers (FF D8 FF).
        var sois: [Int] = []
        var i = 0
        while i + 2 < n {
            if p[i] == 0xFF, p[i + 1] == 0xD8, p[i + 2] == 0xFF { sois.append(i); i += 3 }
            else { i += 1 }
        }
        guard !sois.isEmpty else { return nil }
        // Pick the SOI whose SOF frame is the largest — but ignore tiny streams
        // (256×256 raw tiles, thumbnails) so a false positive can never be chosen as
        // the "preview". A real embedded preview is always well above this floor.
        let minLongEdge = 800
        var bestIdx = -1, bestArea = 0
        for (k, soi) in sois.enumerated() {
            guard let (w, h) = sofDimensions(p, from: soi), max(w, h) >= minLongEdge else { continue }
            if w * h > bestArea { bestArea = w * h; bestIdx = k }
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

    /// Convenience for tests/diagnostics: the pixel size of the largest embedded JPEG in a
    /// raw byte buffer, or nil if none qualifies. Mirrors the zoom fallback's own selection.
    static func embeddedJPEGDimensions(in bytes: [UInt8]) -> (Int, Int)? {
        bytes.withUnsafeBufferPointer { p in
            guard let range = largestJPEGRange(p) else { return nil }
            return sofDimensions(p, from: range.lowerBound)
        }
    }

    /// Reads a JPEG stream's frame dimensions (width, height) from its SOFn marker.
    static func sofDimensions(_ p: UnsafeBufferPointer<UInt8>, from soi: Int) -> (Int, Int)? {
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

    /// Human-readable diagnosis of which zoom-decode path a RAW would take (used by
    /// the `--rawcheck` CLI so any new camera/RAW can be verified without owning it).
    static func zoomDecodeReport(url: URL, maxPixel: Int = PreviewConfig.zoomMaxPixel) -> String {
        func dims(_ w: Int, _ h: Int) -> String {
            "\(w) × \(h) (\(String(format: "%.1f", Double(w * h) / 1_000_000)) MP)"
        }
        let develop = makeThumbnail(url: url, maxPixel: maxPixel, fullQuality: true)
        let embeddedCG = largestEmbeddedJPEGCG(url: url, maxPixel: maxPixel)
        let embDims = embeddedCG.map { ($0.width, $0.height) }
        let orientation = containerOrientation(url)

        var out = "\(url.lastPathComponent)\n"
        out += develop.map { "  • RAW-Entwicklung (ImageIO): OK  \(dims($0.width, $0.height))\n" }
            ?? "  • RAW-Entwicklung (ImageIO): nicht möglich (kein OS-Codec)\n"
        out += embDims.map { "  • Eingebettetes JPEG (Fallback): \(dims($0.0, $0.1))\n" }
            ?? "  • Eingebettetes JPEG (Fallback): keins gefunden\n"
        out += "  • Container-Orientierung: \(orientation.map(String.init) ?? "—")\n"

        if let d = develop {
            out += "  → Zoom nutzt: RAW nativ entwickeln  →  \(dims(d.width, d.height))\n"
        } else if let e = embDims {
            out += "  → Zoom nutzt: eingebettetes JPEG  →  \(dims(e.0, e.1))\n"
        } else {
            out += "  → Zoom nutzt: nur kleine ImageIO-Vorschau (Zoom bleibt weich)\n"
        }
        return out
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
