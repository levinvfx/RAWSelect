import Foundation

/// One logical photo. A RAW file and its JPG sibling (same base name in the same
/// directory) are grouped into a single entry, so they share one mark and are
/// copied/moved together.
struct PhotoGroup: Identifiable, Hashable {
    /// Stable identifier: lowercased path of the group relative to the scan root
    /// (directory + base name, without extension). Survives re-scans so that
    /// saved marks re-attach to the same photo.
    let id: String

    let directory: URL
    let baseName: String

    /// All image files belonging to this photo (e.g. the .ARW and the .JPG).
    var files: [URL]

    /// XMP sidecar files that belong to this photo (matched by base name).
    var sidecars: [URL] = []

    /// File used for on-screen thumbnail/preview (prefers a quick-preview format).
    let previewURL: URL

    /// File whose name we show to the user (prefers the RAW file if present).
    let displayName: String

    /// Stable key used to persist the state, independent of where the folder is
    /// mounted (see FolderIdentity). Filled in by AppState after scanning.
    var persistKey: String = ""

    /// 0 = unmarked, 1…9 = colour mark.
    var mark: Int = 0

    /// Capture/modification date and total byte size, gathered during scanning
    /// (used for sorting and the status bar).
    var fileDate: Date = .distantPast
    var fileSize: Int = 0

    var isRaw: Bool { files.contains(where: { PhotoTypes.isRaw($0) }) }
    var hasState: Bool { mark != 0 }

    static func == (lhs: PhotoGroup, rhs: PhotoGroup) -> Bool {
        lhs.id == rhs.id && lhs.mark == rhs.mark && lhs.files == rhs.files
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(mark)
    }
}

/// Photo-Mechanic-style tag filter. Every bucket is shown by default; clicking a
/// chip hides that bucket. Bucket 0 = untagged ("Alle"), 1…9 = colour marks.
struct TagFilter: Equatable {
    /// Buckets that are currently hidden (empty = show everything).
    var hidden: Set<Int> = []

    static let allBuckets = Set(0...9)   // 0 = untagged, 1…9 = marks

    var isActive: Bool { !hidden.isEmpty }
    var allShown: Bool { hidden.isEmpty }

    func matches(_ group: PhotoGroup) -> Bool {
        !hidden.contains(group.mark)
    }

    func isShown(_ bucket: Int) -> Bool { !hidden.contains(bucket) }

    mutating func toggle(_ bucket: Int) {
        if hidden.contains(bucket) { hidden.remove(bucket) } else { hidden.insert(bucket) }
    }

    mutating func setAll(shown: Bool) {
        hidden = shown ? [] : TagFilter.allBuckets
    }

    mutating func reset() { hidden.removeAll() }
}

