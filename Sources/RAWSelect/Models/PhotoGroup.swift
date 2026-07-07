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
    /// Marked as rejected / to be sorted out.
    var reject: Bool = false

    /// Capture/modification date and total byte size, gathered during scanning
    /// (used for sorting and the status bar).
    var fileDate: Date = .distantPast
    var fileSize: Int = 0

    var isRaw: Bool { files.contains(where: { PhotoTypes.isRaw($0) }) }
    var hasState: Bool { mark != 0 || reject }

    static func == (lhs: PhotoGroup, rhs: PhotoGroup) -> Bool {
        lhs.id == rhs.id && lhs.mark == rhs.mark && lhs.reject == rhs.reject && lhs.files == rhs.files
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(mark)
        hasher.combine(reject)
    }
}

/// Photo-Mechanic-style multi-select tag filter (checkboxes for which tags to
/// show). When nothing is ticked, all photos are shown.
struct TagFilter: Equatable {
    var unmarked = false
    var reject = false
    var marks: Set<Int> = []

    /// Whether any specific tag is being filtered (otherwise: show everything).
    var isActive: Bool { unmarked || reject || !marks.isEmpty }

    func matches(_ group: PhotoGroup) -> Bool {
        guard isActive else { return true }
        if unmarked && !group.hasState { return true }
        if reject && group.reject { return true }
        if group.mark != 0 && marks.contains(group.mark) { return true }
        return false
    }

    mutating func reset() { unmarked = false; reject = false; marks.removeAll() }
}

/// How the grid/filmstrip is ordered.
enum SortOrder: String, CaseIterable, Hashable {
    case filename = "Dateiname"
    case date = "Datum"
}
