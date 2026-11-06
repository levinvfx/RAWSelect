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

            // ONE suffix for the whole photo: RAW, JPG and XMP must keep matching names. Picked
            // per file, a clash on the RAW alone made it DSC01234_1.ARW while its XMP stayed
            // DSC01234.xmp — and Lightroom hung the settings on the OLD photo of that name.
            let present = filesToProcess(group).filter { fm.fileExists(atPath: $0.path) }
            let names = groupDestinationNames(present.map { $0.lastPathComponent }, base: group.baseName,
                                              in: targetRoot, avoiding: used)

            for file in filesToProcess(group) {
                if isCancelled() { cancelled = true; break }
                guard let name = names[file.lastPathComponent], fm.fileExists(atPath: file.path) else {
                    // A vanished source is a FAILURE, not a silent skip — otherwise the report
                    // says "done" while photos are missing at the destination.
                    failures.append("\(file.lastPathComponent): Quelldatei nicht gefunden")
                    completed += 1; progress(completed, totalFiles)
                    continue
                }
                let destination = targetRoot.appendingPathComponent(name)
                do {
                    try copyAtomically(file, to: destination)
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

    /// Copies into a hidden temp file next to the target and only then renames it into place
    /// (never replacing an existing file). A copy cut off by ⌘Q, a full disk or a pulled card
    /// leaves at most a hidden ".part" — never a truncated photo under its real name, which a
    /// later import would take for the original.
    static func copyAtomically(_ source: URL, to destination: URL) throws {
        let fm = FileManager.default
        let temp = destination.deletingLastPathComponent()
            .appendingPathComponent(".rawselect-\(UUID().uuidString).part")
        do {
            try fm.copyItem(at: source, to: temp)
            guard renamex_np(temp.path, destination.path, UInt32(RENAME_EXCL)) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
    }

    /// Destination names for one photo's files with a SHARED suffix: the first n (0 = original
    /// names, then _1, _2 …) where every name is free on disk and unused in this run.
    /// "DSC01234.ARW" + "DSC01234.ARW.xmp" → "DSC01234_1.ARW" + "DSC01234_1.ARW.xmp".
    static func groupDestinationNames(_ filenames: [String], base: String, in directory: URL,
                                      avoiding used: Set<String> = []) -> [String: String] {
        func suffixed(_ name: String, _ n: Int) -> String {
            guard n > 0 else { return name }
            // Insert after the photo's base name; files not starting with it get it before the first dot.
            let cut = (!base.isEmpty && name.lowercased().hasPrefix(base.lowercased()))
                ? name.index(name.startIndex, offsetBy: base.count)
                : (name.firstIndex(of: ".") ?? name.endIndex)
            return String(name[..<cut]) + "_\(n)" + String(name[cut...])
        }
        var n = 0
        while true {
            let names = Dictionary(filenames.map { ($0, suffixed($0, n)) }, uniquingKeysWith: { a, _ in a })
            let allFree = names.values.allSatisfy { name in
                let path = directory.appendingPathComponent(name).path
                return !FileManager.default.fileExists(atPath: path) && !used.contains(path)
            }
            if allFree { return names }
            n += 1
        }
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
