import Foundation

/// Copies or moves marked photos into per-mark subfolders. Never overwrites:
/// on a name clash it appends _1, _2, … Reports progress per file.
struct FileOperationService {

    enum Kind { case copy, move }

    struct Outcome {
        var photos: Int   // number of photo groups processed
        var files: Int    // number of individual files copied/moved
    }

    /// Performs the operation. `progress(completed, total)` is called on a
    /// background thread; the caller marshals to the UI. `isCancelled` is polled
    /// between files.
    static func perform(_ kind: Kind,
                        groups: [PhotoGroup],
                        targetRoot: URL,
                        progress: (Int, Int) -> Void,
                        isCancelled: () -> Bool) throws -> Outcome {

        let marked = groups.filter { $0.mark != 0 }
        let totalFiles = marked.reduce(0) { $0 + $1.files.count }
        let fm = FileManager.default

        var completed = 0
        var photoCount = 0
        var fileCount = 0
        progress(0, totalFiles)

        for group in marked {
            if isCancelled() { break }
            let subfolder = targetRoot.appendingPathComponent(MarkStyle.folderName(for: group.mark), isDirectory: true)
            try fm.createDirectory(at: subfolder, withIntermediateDirectories: true)

            for file in group.files {
                if isCancelled() { break }
                let destination = uniqueDestination(for: file.lastPathComponent, in: subfolder)
                switch kind {
                case .copy: try fm.copyItem(at: file, to: destination)
                case .move: try fm.moveItem(at: file, to: destination)
                }
                fileCount += 1
                completed += 1
                progress(completed, totalFiles)
            }
            photoCount += 1
        }

        return Outcome(photos: photoCount, files: fileCount)
    }

    /// Returns a non-colliding destination URL, appending _1, _2, … if needed.
    static func uniqueDestination(for filename: String, in directory: URL) -> URL {
        let candidate = directory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }

        let ns = filename as NSString
        let base = ns.deletingPathExtension
        let ext = ns.pathExtension
        var index = 1
        while true {
            let newName = ext.isEmpty ? "\(base)_\(index)" : "\(base)_\(index).\(ext)"
            let url = directory.appendingPathComponent(newName)
            if !FileManager.default.fileExists(atPath: url.path) { return url }
            index += 1
        }
    }
}
