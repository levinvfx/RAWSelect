import Foundation

/// Recursively scans a folder for supported images, groups RAW+JPG siblings, and
/// attaches matching XMP sidecar files. Runs off the main thread.
struct PhotoScanner {

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

        // Bucket image files by "<relative dir>/<basename>" (lowercased) so that
        // IMG_0001.ARW and IMG_0001.JPG land in the same bucket.
        var buckets: [String: [URL]] = [:]
        // XMP sidecars keyed by every base name they could belong to.
        var sidecars: [String: [URL]] = [:]
        var seen = 0

        for case let fileURL as URL in enumerator {
            if isCancelled() { return [] }
            let ext = fileURL.pathExtension.lowercased()
            let relativeDir = relativePath(of: fileURL.deletingLastPathComponent(), from: root)

            if ext == "xmp" {
                for base in sidecarBaseNames(for: fileURL) {
                    let key = (relativeDir + "/" + base).lowercased()
                    sidecars[key, default: []].append(fileURL)
                }
                continue
            }

            guard PhotoTypes.all.contains(ext) else { continue }
            let base = fileURL.deletingPathExtension().lastPathComponent
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
            let base = sorted[0].deletingPathExtension().lastPathComponent
            let matchedSidecars = (sidecars[key] ?? [])
                .reduce(into: [URL]()) { acc, url in if !acc.contains(url) { acc.append(url) } }
            groups.append(PhotoGroup(
                id: key,
                directory: sorted[0].deletingLastPathComponent(),
                baseName: base,
                files: sorted,
                sidecars: matchedSidecars,
                previewURL: preferredPreview(from: sorted),
                displayName: preferredDisplayName(from: sorted)
            ))
        }

        groups.sort { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        return groups
    }

    /// An XMP sidecar can be named `IMG_0001.xmp` or `IMG_0001.ARW.xmp`. Return
    /// both possible base names so it attaches to the right photo either way.
    private static func sidecarBaseNames(for xmp: URL) -> [String] {
        let firstBase = xmp.deletingPathExtension().lastPathComponent   // "IMG_0001" or "IMG_0001.ARW"
        var names = [firstBase]
        let inner = (firstBase as NSString).pathExtension.lowercased()
        if PhotoTypes.all.contains(inner) {
            names.append((firstBase as NSString).deletingPathExtension)  // "IMG_0001"
        }
        return names
    }

    private static func preferredPreview(from files: [URL]) -> URL {
        files.first(where: { PhotoTypes.quickPreview.contains($0.pathExtension.lowercased()) }) ?? files[0]
    }

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
