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
        let keys: Set<URLResourceKey> = [.volumeUUIDStringKey, .volumeURLKey,
                                         .volumeNameKey, .volumeTotalCapacityKey,
                                         .volumeCreationDateKey]
        let values = try? root.resourceValues(forKeys: keys)
        if let volumeURL = values?.volume {
            if let uuid = values?.volumeUUIDString, !uuid.isEmpty {
                // Best case: a real volume UUID – survives re-mounting at any path.
                self.id = "vol-" + uuid
            } else {
                // SD/exFAT/FAT cards frequently expose NO volume UUID. Instead of keying on
                // the mount path (which becomes "Untitled 1" on re-insert and loses the
                // marks), build a fingerprint from traits that survive ejecting.
                //
                // The creation date is what makes it a fingerprint at all: name + capacity
                // alone are identical on two factory-formatted cards — both "Untitled", both
                // 64 GB — so the second card showed the first one's marks on its own photos,
                // and the first mark on it wiped the other's. Formatting a card changes the
                // date, which is right: a reformatted card is a new card.
                // Nothing is ever written to the card.
                let name = values?.volumeName ?? volumeURL.lastPathComponent
                let capacity = values?.volumeTotalCapacity ?? 0
                let born = values?.volumeCreationDate.map { Int($0.timeIntervalSince1970) } ?? 0
                self.id = "fp-\(name)-\(capacity)-\(born)"
            }
            self.keyBase = volumeURL
        } else {
            // Not a distinct volume (e.g. a plain folder on the internal disk).
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
