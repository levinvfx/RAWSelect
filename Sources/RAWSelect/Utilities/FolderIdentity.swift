import Foundation

/// Identifies a scan source in a way that survives ejecting and re-inserting an
/// SD card. Marks are stored per **volume UUID** and keyed by the path relative
/// to the volume's mount point, so the app "remembers" a card no matter where it
/// re-mounts – without ever writing anything onto the card.
struct FolderIdentity {
    /// Stable id used for the session file name.
    let id: String
    /// Base used to compute per-photo persist keys (the volume root when known).
    let keyBase: URL

    init(root: URL) {
        let keys: Set<URLResourceKey> = [.volumeUUIDStringKey, .volumeURLKey]
        if let values = try? root.resourceValues(forKeys: keys),
           let uuid = values.volumeUUIDString,
           let volumeURL = values.volume {
            self.id = "vol-" + uuid
            self.keyBase = volumeURL
        } else {
            // Fallback: identify by absolute path.
            self.id = "path-" + root.standardizedFileURL.path
            self.keyBase = root
        }
    }

    /// Stable key for a photo group (directory + base name), relative to the
    /// volume root and lowercased.
    func persistKey(directory: URL, baseName: String) -> String {
        let relDir = relativePath(of: directory, from: keyBase)
        return (relDir + "/" + baseName).lowercased()
    }

    private func relativePath(of url: URL, from base: URL) -> String {
        let baseComponents = base.standardizedFileURL.pathComponents
        let urlComponents = url.standardizedFileURL.pathComponents
        if urlComponents.count >= baseComponents.count,
           Array(urlComponents.prefix(baseComponents.count)) == baseComponents {
            return urlComponents.dropFirst(baseComponents.count).joined(separator: "/")
        }
        return url.path
    }
}
