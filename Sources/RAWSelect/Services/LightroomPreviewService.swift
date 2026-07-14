import Foundation

/// Caches Lightroom-rendered, preset-applied preview JPEGs for the export crop step.
/// Each (RAW + preset + size) is rendered by Lightroom only ONCE; concurrent requests
/// for the same image share one render (dedup). Rendering happens via the bridge and
/// takes seconds, so callers pre-warm neighbours in the background.
actor LightroomPreviewService {
    static let shared = LightroomPreviewService()

    private let fm = FileManager.default
    private var inFlight: [String: Task<URL?, Never>] = [:]

    private var cacheDir: URL {
        let dir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("RAW Select/PresetPreview", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Stable cache key from paths + modification dates + size (survives across
    /// sessions; invalidates when the RAW or preset changes).
    private func key(_ rawURL: URL, _ presetURL: URL?, _ edit: ImageEdit, _ maxEdge: Int) -> String {
        func stamp(_ u: URL) -> String {
            let m = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?
                .timeIntervalSince1970 ?? 0
            return "\(u.path)#\(Int(m))"
        }
        let s = "\(stamp(rawURL))|\(presetURL.map(stamp) ?? "none")|\(edit.developSignature)|\(maxEdge)"
        return fnv1a(s)
    }

    private func fnv1a(_ s: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return String(h, radix: 16)
    }

    private func cacheFile(_ rawURL: URL, _ presetURL: URL?, _ edit: ImageEdit, _ maxEdge: Int) -> URL {
        cacheDir.appendingPathComponent(key(rawURL, presetURL, edit, maxEdge) + ".jpg")
    }

    /// Deletes all cached preset previews from disk. Called when the export wizard
    /// closes (previews only matter during the adjust session) and from Settings →
    /// „Cache leeren". In-flight renders are left to finish harmlessly.
    func clearCache() {
        if let files = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil) {
            for f in files { try? fm.removeItem(at: f) }
        }
    }

    /// The cached preview if already rendered, else nil (never triggers a render).
    func cached(rawURL: URL, presetURL: URL?, edit: ImageEdit = ImageEdit(), maxEdge: Int = 2048) -> URL? {
        let f = cacheFile(rawURL, presetURL, edit, maxEdge)
        return fm.fileExists(atPath: f.path) ? f : nil
    }

    /// Returns the cached preview or renders it via Lightroom (deduped). `edit` bakes
    /// exposure + Basic-panel develop into the render so it matches the export 1:1;
    /// pass an identity edit for the plain preset base. Returns nil on failure.
    func preview(rawURL: URL, presetURL: URL?, edit: ImageEdit = ImageEdit(),
                 maxEdge: Int = 2048, lightroomPath: String) async -> URL? {
        let dest = cacheFile(rawURL, presetURL, edit, maxEdge)
        if fm.fileExists(atPath: dest.path) { return dest }

        let k = key(rawURL, presetURL, edit, maxEdge)
        if let running = inFlight[k] { return await running.value }

        let task = Task<URL?, Never> { [fm] in
            guard let temp = await LightroomExportService.renderPreview(
                rawURL: rawURL, presetURL: presetURL, edit: edit, maxEdge: maxEdge, lightroomPath: lightroomPath)
            else { return nil }
            try? fm.removeItem(at: dest)
            try? fm.moveItem(at: temp, to: dest)
            return fm.fileExists(atPath: dest.path) ? dest : nil
        }
        inFlight[k] = task
        let result = await task.value
        inFlight[k] = nil
        return result
    }
}
