import Foundation

/// Recursively scans a folder for supported images and groups RAW+JPG siblings.
/// Runs off the main thread; reports progress via a callback.
struct PhotoScanner {

    /// Scans `root` recursively. `onProgress` is called periodically with the
    /// number of files seen so far. Returns groups sorted by path.
    static func scan(root: URL,
                     isCancelled: () -> Bool = { false },
                     onProgress: (Int) -> Void = { _ in }) -> [PhotoGroup] {

        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        // Bucket files by "<relative dir>/<basename>" (lowercased) so that
        // IMG_0001.ARW and IMG_0001.JPG land in the same bucket.
        var buckets: [String: [URL]] = [:]
        var seen = 0

        for case let fileURL as URL in enumerator {
            if isCancelled() { return [] }
            guard PhotoTypes.isSupported(fileURL) else { continue }

            let base = fileURL.deletingPathExtension().lastPathComponent
            let relativeDir = relativePath(of: fileURL.deletingLastPathComponent(), from: root)
            let key = (relativeDir + "/" + base).lowercased()
            buckets[key, default: []].append(fileURL)

            seen += 1
            if seen % 100 == 0 { onProgress(seen) }
        }
        onProgress(seen)

        var groups: [PhotoGroup] = []
        groups.reserveCapacity(buckets.count)

        for (key, files) in buckets {
            let sorted = files.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            let preview = preferredPreview(from: sorted)
            let display = preferredDisplayName(from: sorted)
            let base = sorted[0].deletingPathExtension().lastPathComponent
            groups.append(PhotoGroup(
                id: key,
                directory: sorted[0].deletingLastPathComponent(),
                baseName: base,
                files: sorted,
                previewURL: preview,
                displayName: display
            ))
        }

        groups.sort { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        return groups
    }

    /// Prefer a quick-preview format (JPG/HEIC/PNG) for display; fall back to RAW.
    private static func preferredPreview(from files: [URL]) -> URL {
        files.first(where: { PhotoTypes.quickPreview.contains($0.pathExtension.lowercased()) }) ?? files[0]
    }

    /// Prefer the RAW file name so the user sees their "real" file.
    private static func preferredDisplayName(from files: [URL]) -> String {
        (files.first(where: { PhotoTypes.isRaw($0) }) ?? files[0]).lastPathComponent
    }

    private static func relativePath(of url: URL, from root: URL) -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let urlComponents = url.standardizedFileURL.pathComponents
        if urlComponents.count >= rootComponents.count,
           Array(urlComponents.prefix(rootComponents.count)) == rootComponents {
            return urlComponents.dropFirst(rootComponents.count).joined(separator: "/")
        }
        return url.path
    }
}
