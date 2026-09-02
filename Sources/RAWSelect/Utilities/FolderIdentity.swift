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
                if let born = values?.volumeCreationDate.map({ Int($0.timeIntervalSince1970) }) {
                    self.id = "fp-\(name)-\(capacity)-\(born)"
                } else {
                    // No creation date either (some FAT/exFAT cards). Falling back to 0 here
                    // merged two factory-formatted cards into ONE session — exactly the bug the
                    // date was meant to prevent. Fingerprint the card's own content instead:
                    // stable across re-inserts, different per card, new after a format.
                    self.id = "fp-\(name)-\(capacity)-c\(FolderIdentity.contentSample(of: volumeURL))"
                }
            }
            self.keyBase = volumeURL
        } else {
            // Not a distinct volume (e.g. a plain folder on the internal disk).
            self.id = "path-" + root.standardizedFileURL.path
            self.keyBase = root
        }
    }

    /// Persist key for a scanned group. In ungrouped mode the runtime id keeps RAW and JPG
    /// apart, so the key must carry the extension too — otherwise IMG_0001.ARW and
    /// IMG_0001.JPG share one saved mark and overwrite each other on every save.
    func persistKey(for group: PhotoGroup, groupPairs: Bool) -> String {
        let name = groupPairs ? group.baseName
            : group.baseName + "." + (group.files.first?.pathExtension.lowercased() ?? "")
        return persistKey(directory: group.directory, baseName: name)
    }

    /// Hash over a sample of photo files on the volume (path relative to the mount point +
    /// size, in stable name order). A camera appends new shots at the END of its numbering,
    /// so the first files stay the same for a card in use; a format or a different card
    /// changes them. Read-only, bounded, cheap.
    private static func contentSample(of volume: URL) -> String {
        let fm = FileManager.default
        let base = volume.standardizedFileURL.path
        var entries: [String] = []
        if let en = fm.enumerator(at: volume, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                  options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let url as URL in en {
                guard PhotoTypes.isSupported(url),
                      let v = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                      v.isRegularFile == true else { continue }
                let rel = String(url.standardizedFileURL.path.dropFirst(base.count)).lowercased()
                entries.append(rel + ":" + String(v.fileSize ?? 0))
                if entries.count >= 200 { break }
            }
        }
        let sample = entries.sorted().prefix(40).joined(separator: "|")
        var h: UInt64 = 14_695_981_039_346_656_037            // FNV-1a
        for b in sample.utf8 { h ^= UInt64(b); h = h &* 1_099_511_628_211 }
        return String(h, radix: 16)
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
