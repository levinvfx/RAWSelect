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
        var failures: [String] = []          // "filename: reason" for files that failed
        var movedGroupIDs: Set<String> = []  // groups whose files ALL moved (move only)
    }

    /// - Parameters:
    ///   - groups: the photos to process (already the user's selection).
    ///   - targetRoot: destination folder (files are placed directly inside).
    ///   - includeSidecars: also copy/move matching .xmp files.
    static func perform(_ kind: Kind,
                        groups: [PhotoGroup],
                        targetRoot: URL,
                        includeSidecars: Bool,
                        rawJpg: RawJpgExport = .both,
                        subfolder: (PhotoGroup) -> String? = { _ in nil },
                        conflict: ConflictMode = .rename,
                        progress: (Int, Int) -> Void,
                        isCancelled: () -> Bool) throws -> Outcome {

        let fm = FileManager.default
        try fm.createDirectory(at: targetRoot, withIntermediateDirectories: true)

        func imageFiles(_ g: PhotoGroup) -> [URL] {
            switch rawJpg {
            case .both: return g.files
            case .rawOnly:
                let r = g.files.filter { PhotoTypes.isRaw($0) }
                return r.isEmpty ? g.files : r
            case .jpgOnly:
                let j = g.files.filter { ["jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
                return j.isEmpty ? g.files : j
            }
        }
        func filesToProcess(_ g: PhotoGroup) -> [URL] {
            includeSidecars ? imageFiles(g) + g.sidecars : imageFiles(g)
        }

        let totalFiles = groups.reduce(0) { $0 + filesToProcess($1).count }
        var completed = 0
        var photoCount = 0
        var fileCount = 0
        var failures: [String] = []
        var movedGroupIDs = Set<String>()
        var used = Set<String>()            // destinations already written in THIS run
        progress(0, totalFiles)

        for group in groups {
            if isCancelled() { break }
            var didProcessAny = false
            var completedWholeGroup = true   // false if any file skipped/failed/cancelled

            let dir: URL
            if let sub = subfolder(group), !sub.isEmpty {
                dir = targetRoot.appendingPathComponent(sub, isDirectory: true)
                do { try fm.createDirectory(at: dir, withIntermediateDirectories: true) }
                catch { failures.append("\(sub): \(error.localizedDescription)"); continue }
            } else {
                dir = targetRoot
            }

            for file in filesToProcess(group) {
                if isCancelled() { completedWholeGroup = false; break }
                guard fm.fileExists(atPath: file.path) else { completedWholeGroup = false; continue }

                var destination = dir.appendingPathComponent(file.lastPathComponent)
                if used.contains(destination.path) {
                    // In-batch name clash → never clobber our own just-written file.
                    destination = uniqueDestination(for: file.lastPathComponent, in: dir, avoiding: used)
                } else if fm.fileExists(atPath: destination.path) {
                    switch conflict {
                    case .skip: completedWholeGroup = false; continue
                    case .overwrite: try? fm.removeItem(at: destination)
                    case .rename: destination = uniqueDestination(for: file.lastPathComponent, in: dir, avoiding: used)
                    }
                }
                do {
                    switch kind {
                    case .copy: try fm.copyItem(at: file, to: destination)
                    case .move: try fm.moveItem(at: file, to: destination)
                    }
                    used.insert(destination.path)
                    fileCount += 1
                    completed += 1
                    didProcessAny = true
                    progress(completed, totalFiles)
                } catch {
                    // Collect the failure and keep going – never abort the whole batch.
                    failures.append("\(file.lastPathComponent): \(error.localizedDescription)")
                    completedWholeGroup = false
                }
            }
            if didProcessAny { photoCount += 1 }
            // Only groups whose files ALL moved may be removed from the source list.
            if kind == .move && didProcessAny && completedWholeGroup { movedGroupIDs.insert(group.id) }
        }

        return Outcome(photos: photoCount, files: fileCount, failures: failures, movedGroupIDs: movedGroupIDs)
    }

    /// Returns a non-colliding destination URL, appending _1, _2, … if needed.
    static func uniqueDestination(for filename: String, in directory: URL,
                                  avoiding used: Set<String> = []) -> URL {
        func free(_ url: URL) -> Bool {
            !FileManager.default.fileExists(atPath: url.path) && !used.contains(url.path)
        }
        let candidate = directory.appendingPathComponent(filename)
        if free(candidate) { return candidate }

        let ns = filename as NSString
        let base = ns.deletingPathExtension
        let ext = ns.pathExtension
        var index = 1
        while true {
            let newName = ext.isEmpty ? "\(base)_\(index)" : "\(base)_\(index).\(ext)"
            let url = directory.appendingPathComponent(newName)
            if free(url) { return url }
            index += 1
        }
    }
}
