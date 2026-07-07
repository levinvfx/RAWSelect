import Foundation

/// Copies or moves a set of photos flat into a chosen target folder (like a
/// classic culling app). Originals are read from disk only now – marks live in
/// the app, never in the files, so copies carry no app tags. Never overwrites:
/// on a name clash it appends _1, _2, …
struct FileOperationService {

    enum Kind { case copy, move }

    struct Outcome {
        var photos: Int   // number of photo groups processed
        var files: Int    // number of individual files copied/moved (incl. XMP)
    }

    /// - Parameters:
    ///   - groups: the photos to process (already the user's selection).
    ///   - targetRoot: destination folder (files are placed directly inside).
    ///   - includeSidecars: also copy/move matching .xmp files.
    static func perform(_ kind: Kind,
                        groups: [PhotoGroup],
                        targetRoot: URL,
                        includeSidecars: Bool,
                        subfolder: (PhotoGroup) -> String? = { _ in nil },
                        conflict: ConflictMode = .rename,
                        progress: (Int, Int) -> Void,
                        isCancelled: () -> Bool) throws -> Outcome {

        let fm = FileManager.default
        try fm.createDirectory(at: targetRoot, withIntermediateDirectories: true)

        func filesToProcess(_ g: PhotoGroup) -> [URL] {
            includeSidecars ? g.files + g.sidecars : g.files
        }

        let totalFiles = groups.reduce(0) { $0 + filesToProcess($1).count }
        var completed = 0
        var photoCount = 0
        var fileCount = 0
        progress(0, totalFiles)

        for group in groups {
            if isCancelled() { break }
            var didProcessAny = false

            let dir: URL
            if let sub = subfolder(group), !sub.isEmpty {
                dir = targetRoot.appendingPathComponent(sub, isDirectory: true)
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            } else {
                dir = targetRoot
            }

            for file in filesToProcess(group) {
                if isCancelled() { break }
                guard fm.fileExists(atPath: file.path) else { continue }

                var destination = dir.appendingPathComponent(file.lastPathComponent)
                if fm.fileExists(atPath: destination.path) {
                    switch conflict {
                    case .skip: continue
                    case .overwrite: try? fm.removeItem(at: destination)
                    case .rename, .ask: destination = uniqueDestination(for: file.lastPathComponent, in: dir)
                    }
                }
                switch kind {
                case .copy: try fm.copyItem(at: file, to: destination)
                case .move: try fm.moveItem(at: file, to: destination)
                }
                fileCount += 1
                completed += 1
                didProcessAny = true
                progress(completed, totalFiles)
            }
            if didProcessAny { photoCount += 1 }
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
