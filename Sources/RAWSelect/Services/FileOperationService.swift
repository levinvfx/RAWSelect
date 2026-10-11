import Foundation

/// Copies a set of photos flat into a chosen target folder (like a classic culling app).
/// Originals are only ever READ — marks live in the app, never in the files, so copies carry no
/// app tags. Never overwrites and never deletes: on a name clash it appends _1, _2, …
/// (Moving and overwriting were removed with V1.10: no release code path could reach them, and
/// they were the only ways a copy could ever remove a user's file.)
struct FileOperationService {

    struct Outcome {
        var photos: Int   // number of photo groups processed
        var files: Int    // number of individual files copied (incl. XMP)
        var failures: [String] = []          // "filename: reason" for files that failed
        var cancelled = false                // stopped early by the user — never report as "done"
    }

    /// - Parameters:
    ///   - groups: the photos to copy (already the user's selection).
    ///   - targetRoot: destination folder (files are placed directly inside).
    ///   - includeSidecars: also copy matching .xmp files.
    static func copy(groups: [PhotoGroup],
                     targetRoot: URL,
                     includeSidecars: Bool,
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
        var failures: [String] = []
        var cancelled = false
        var used = Set<String>()            // destinations already written in THIS run
        progress(0, totalFiles)

        for group in groups {
            if isCancelled() { cancelled = true; break }
            var didProcessAny = false

            for file in filesToProcess(group) {
                if isCancelled() { cancelled = true; break }
                guard fm.fileExists(atPath: file.path) else {
                    // A vanished source is a FAILURE, not a silent skip — otherwise the report
                    // says "done" while photos are missing at the destination.
                    failures.append("\(file.lastPathComponent): Quelldatei nicht gefunden")
                    completed += 1; progress(completed, totalFiles)
                    continue
                }

                // Name clash on disk OR with a file written earlier in this batch → _1, _2, …
                let destination = uniqueDestination(for: file.lastPathComponent, in: targetRoot, avoiding: used)
                do {
                    try fm.copyItem(at: file, to: destination)
                    used.insert(destination.path)
                    fileCount += 1
                    completed += 1
                    didProcessAny = true
                    progress(completed, totalFiles)
                } catch {
                    // Collect the failure and keep going – never abort the whole batch.
                    failures.append("\(file.lastPathComponent): \(error.localizedDescription)")
                }
            }
            if didProcessAny { photoCount += 1 }
        }

        return Outcome(photos: photoCount, files: fileCount, failures: failures, cancelled: cancelled)
    }

    struct TrashOutcome {
        var photos: Int                       // photo groups with at least one file trashed
        var files: Int                        // individual files moved to the Trash (incl. XMP)
        var failures: [String] = []           // "filename: reason"
        var trashedGroupIDs: Set<String> = [] // groups whose files ALL trashed → drop from the list
        var trashedURLs: [URL] = []           // resulting locations in the Trash
        var cancelled = false
    }

    /// Moves a set of photos (and optional sidecars) to the macOS Trash — recoverable, never a
    /// hard delete. Like `perform`, a single file failure never aborts the batch. Only groups
    /// whose files were ALL trashed are reported for removal from the source list.
    static func trash(groups: [PhotoGroup],
                      includeSidecars: Bool = true,
                      progress: (Int, Int) -> Void = { _, _ in },
                      isCancelled: () -> Bool = { false }) -> TrashOutcome {
        let fm = FileManager.default
        func filesToProcess(_ g: PhotoGroup) -> [URL] {
            includeSidecars ? g.files + g.sidecars : g.files
        }
        let totalFiles = groups.reduce(0) { $0 + filesToProcess($1).count }
        var completed = 0, photoCount = 0, fileCount = 0
        var failures: [String] = []
        var trashedGroupIDs = Set<String>()
        var trashedURLs: [URL] = []
        var cancelled = false
        progress(0, totalFiles)

        for group in groups {
            if isCancelled() { cancelled = true; break }
            var didProcessAny = false
            var completedWholeGroup = true
            for file in filesToProcess(group) {
                if isCancelled() { cancelled = true; completedWholeGroup = false; break }
                guard fm.fileExists(atPath: file.path) else { completedWholeGroup = false; continue }
                do {
                    var resulting: NSURL?
                    try fm.trashItem(at: file, resultingItemURL: &resulting)
                    if let r = resulting as URL? { trashedURLs.append(r) }
                    fileCount += 1; completed += 1; didProcessAny = true
                    progress(completed, totalFiles)
                } catch {
                    failures.append("\(file.lastPathComponent): \(error.localizedDescription)")
                    completedWholeGroup = false
                }
            }
            if didProcessAny { photoCount += 1 }
            if didProcessAny && completedWholeGroup { trashedGroupIDs.insert(group.id) }
        }
        return TrashOutcome(photos: photoCount, files: fileCount, failures: failures,
                            trashedGroupIDs: trashedGroupIDs, trashedURLs: trashedURLs, cancelled: cancelled)
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
