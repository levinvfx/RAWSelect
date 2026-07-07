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

    /// All files belonging to this photo (e.g. the .ARW and the .JPG).
    var files: [URL]

    /// File used for on-screen thumbnail/preview (prefers a quick-preview format).
    let previewURL: URL

    /// File whose name we show to the user (prefers the RAW file if present).
    let displayName: String

    /// 0 = unmarked, 1…9 = mark.
    var mark: Int = 0

    var isRaw: Bool { files.contains(where: { PhotoTypes.isRaw($0) }) }

    static func == (lhs: PhotoGroup, rhs: PhotoGroup) -> Bool {
        lhs.id == rhs.id && lhs.mark == rhs.mark && lhs.files == rhs.files
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(mark)
    }
}

/// Sidebar filter states.
enum PhotoFilter: Hashable {
    case all
    case unmarked
    case mark(Int)

    func matches(_ group: PhotoGroup) -> Bool {
        switch self {
        case .all: return true
        case .unmarked: return group.mark == 0
        case .mark(let n): return group.mark == n
        }
    }
}
