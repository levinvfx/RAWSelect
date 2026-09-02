import Foundation

/// Recursively scans a folder for supported images, groups RAW+JPG siblings, and
/// attaches matching XMP sidecar files. Runs off the main thread.
struct PhotoScanner {

    /// Camera folders preferred by the "fast / camera folders only" scan mode.
    private static let cameraFolders: Set<String> = ["dcim", "private", "misc", "mp_root", "clips", "avf_info"]

    static func scan(root: URL,
                     allowedExtensions: Set<String> = PhotoTypes.all,
                     recursive: Bool = true,
                     groupPairs: Bool = true,
                     ignoreHidden: Bool = true,
                     cameraFoldersOnly: Bool = false,
                     isCancelled: () -> Bool = { false },
                     onProgress: (Int) -> Void = { _ in },
                     onBatch: (([PhotoGroup]) -> Void)? = nil) -> [PhotoGroup] {

        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if ignoreHidden { options.insert(.skipsHiddenFiles) }
        guard let enumerator = fm.enumerator(
            at: root, includingPropertiesForKeys: keys, options: options
        ) else { return [] }

        // Restrict to camera folders only if requested and such folders exist here.
        let restrictToCamera = cameraFoldersOnly && hasCameraFolders(root)

        var buckets: [String: [URL]] = [:]
        var sidecars: [String: [URL]] = [:]
        var seen = 0

        for case let fileURL as URL in enumerator {
            if isCancelled() { return [] }
            let ext = fileURL.pathExtension.lowercased()
            let relativeDir = relativePath(of: fileURL.deletingLastPathComponent(), from: root)

            // Non-recursive: only files directly inside the root.
            if !recursive && !relativeDir.isEmpty { continue }
            // Camera-folders-only: first path component must be a camera folder.
            if restrictToCamera {
                let first = relativeDir.split(separator: "/").first.map(String.init)?.lowercased() ?? ""
                if !cameraFolders.contains(first) { continue }
            }

            if ext == "xmp" {
                for base in sidecarBaseNames(for: fileURL) {
                    let key = (relativeDir + "/" + base).lowercased()
                    sidecars[key, default: []].append(fileURL)
                }
                continue
            }

            guard allowedExtensions.contains(ext) else { continue }
            let base = fileURL.deletingPathExtension().lastPathComponent
            // When pairing is off, keep each file separate by including the ext.
            let key = groupPairs ? (relativeDir + "/" + base).lowercased()
                                 : (relativeDir + "/" + base + "." + ext).lowercased()
            buckets[key, default: []].append(fileURL)

            seen += 1
            if seen % 100 == 0 { onProgress(seen) }
        }
        onProgress(seen)

        var groups: [PhotoGroup] = []
        groups.reserveCapacity(buckets.count)

        // Ungrouped mode: a plain "IMG_0001.xmp" is filed under the base name, but the bucket
        // keys carry the extension — so it matched neither the ARW nor the JPG and was dropped.
        // Give it to the RAW of that base (or the first file if there is none), never to both:
        // a copy would otherwise write the same sidecar twice.
        func baseKey(_ key: String, _ files: [URL]) -> String {
            let ext = files[0].pathExtension.lowercased()
            return groupPairs ? key : String(key.dropLast(ext.count + 1))
        }
        var plainSidecarOwner: [String: String] = [:]
        if !groupPairs {
            for (key, files) in buckets {
                let bk = baseKey(key, files)
                if plainSidecarOwner[bk] == nil || PhotoTypes.isRaw(files[0]) { plainSidecarOwner[bk] = key }
            }
        }

        // Name order so progressive batches grow the grid at the END instead of reshuffling it.
        let orderedKeys = buckets.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        var batch: [PhotoGroup] = []
        for key in orderedKeys {
            if isCancelled() { break }   // the stat phase is the slow part on a card — must be stoppable too
            let files = buckets[key]!
            let sorted = files.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            let base = sorted[0].deletingPathExtension().lastPathComponent
            var candidates = sidecars[key] ?? []
            if !groupPairs, plainSidecarOwner[baseKey(key, sorted)] == key {
                candidates += sidecars[baseKey(key, sorted)] ?? []
            }
            let matchedSidecars = candidates
                .reduce(into: [URL]()) { acc, url in if !acc.contains(url) { acc.append(url) } }

            var totalSize = 0
            for f in sorted + matchedSidecars {
                if let v = try? f.resourceValues(forKeys: [.fileSizeKey]) { totalSize += v.fileSize ?? 0 }
            }
            var date = Date.distantPast
            if let v = try? sorted[0].resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey]) {
                date = v.creationDate ?? v.contentModificationDate ?? .distantPast
            }

            var group = PhotoGroup(
                id: key,
                directory: sorted[0].deletingLastPathComponent(),
                baseName: base,
                files: sorted,
                sidecars: matchedSidecars,
                previewURL: preferredPreview(from: sorted),
                displayName: preferredDisplayName(from: sorted)
            )
            group.fileSize = totalSize
            group.fileDate = date
            groups.append(group)
            if let onBatch {
                batch.append(group)
                if batch.count >= 200 { onBatch(batch); batch.removeAll(keepingCapacity: true) }
            }
        }
        if let onBatch, !batch.isEmpty { onBatch(batch) }

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

    private static func hasCameraFolders(_ root: URL) -> Bool {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return false }
        return items.contains { cameraFolders.contains($0.lastPathComponent.lowercased()) }
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
