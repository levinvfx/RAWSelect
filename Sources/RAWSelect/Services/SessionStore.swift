import Foundation
import CryptoKit

/// Persists marks per source (identified by FolderIdentity) in
/// ~/Library/Application Support/RAW Select/Sessions/<hash>.json.
///
/// Marks are stored centrally and never written into the source folder, so an
/// SD card is never modified. Keyed by the group's volume-relative persist key.
struct SessionStore {

    /// Per-photo culling state, keyed by persistKey.
    struct PhotoState: Codable, Equatable {
        var mark: Int = 0
        /// Non-destructive develop/crop edit; nil when the photo is untouched.
        /// Optional so older session files (mark only) still decode.
        var edit: ImageEdit? = nil
        var isDefault: Bool { mark == 0 && (edit?.isIdentity ?? true) }
    }

    struct SessionData: Codable {
        var identity: String
        var states: [String: PhotoState]
    }

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("RAW Select/Sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func fileURL(for identityID: String) -> URL {
        let digest = SHA256.hash(data: Data(identityID.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(hex).json")
    }

    /// What's on disk for an identity. `unreadable` is deliberately NOT folded into `none`:
    /// a file that exists but won't decode must never be silently overwritten, or a temporary
    /// glitch turns into permanent loss of every mark on that volume.
    enum Stored: Equatable {
        case none
        case states([String: PhotoState])
        case unreadable
    }

    static func read(identityID: String) -> Stored {
        let url = fileURL(for: identityID)
        guard FileManager.default.fileExists(atPath: url.path) else { return .none }
        guard let data = try? Data(contentsOf: url),
              let session = try? JSONDecoder().decode(SessionData.self, from: data) else {
            return .unreadable
        }
        return .states(session.states)
    }

    static func load(identityID: String) -> [String: PhotoState] {
        if case .states(let s) = read(identityID: identityID) { return s }
        return [:]
    }

    /// Exports every stored session file into a single JSON bundle.
    static func exportAll(to url: URL) -> Bool {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return false }
        var bundle: [String: SessionData] = [:]
        for f in files where f.pathExtension == "json" {
            if let d = try? Data(contentsOf: f), let s = try? JSONDecoder().decode(SessionData.self, from: d) {
                bundle[f.lastPathComponent] = s
            }
        }
        guard let data = try? JSONEncoder().encode(bundle) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// Restores session files from a bundle created by `exportAll`.
    static func importAll(from url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let bundle = try? JSONDecoder().decode([String: SessionData].self, from: data) else { return false }
        for (name, session) in bundle {
            if let d = try? JSONEncoder().encode(session) {
                try? d.write(to: directory.appendingPathComponent(name), options: .atomic)
            }
        }
        return true
    }

    enum SaveResult: Equatable {
        case ok
        /// The existing file was unreadable and was moved aside; work continues on a fresh one.
        case quarantined(String)
        case failed(String)
    }

    /// Writes the states of the photos in `scope` and leaves every other entry alone.
    ///
    /// `scope` is what makes this safe. One session file covers a whole VOLUME, but the app
    /// only ever holds ONE folder in memory. Writing just that folder's states wiped every
    /// other folder on the same disk: open a second folder, press one key, and the 200 marks
    /// from the first were gone — silently. Merging blindly would be wrong the other way
    /// round, because clearing a mark has to actually remove it. So the caller owns exactly
    /// `scope` (every photo currently loaded, marked or not) and may replace those keys;
    /// everything else belongs to another folder and stays untouched.
    @discardableResult
    static func save(identityID: String, states: [String: PhotoState], scope: Set<String>) -> SaveResult {
        var merged: [String: PhotoState] = [:]
        var quarantined: String?
        switch read(identityID: identityID) {
        case .states(let existing):
            merged = existing
        case .none:
            break
        case .unreadable:
            // Never overwrite a file we couldn't read — it may still be recoverable.
            quarantined = quarantine(identityID: identityID)
        }

        for key in scope { merged[key] = nil }
        for (key, state) in states where !state.isDefault { merged[key] = state }

        let session = SessionData(identity: identityID, states: merged)
        let url = fileURL(for: identityID)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(session)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("RAW Select: failed to save session: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
        if let quarantined { return .quarantined(quarantined) }
        return .ok
    }

    /// Serialises session writes off the main thread. Being an actor is the whole point: the
    /// writes still happen strictly in order, so the last keypress always wins — but marking
    /// never waits for the disk.
    actor SessionWriter {
        static let shared = SessionWriter()
        func write(_ id: String, _ states: [String: PhotoState], _ scope: Set<String>) -> SaveResult {
            SessionStore.save(identityID: id, states: states, scope: scope)
        }
    }

    /// Removes an identity's file. Used by the self-test to clean up after itself.
    static func delete(identityID: String) {
        try? FileManager.default.removeItem(at: fileURL(for: identityID))
    }

    /// Moves a damaged session file aside instead of destroying it, so the marks in it can
    /// still be rescued by hand. Returns the new file name.
    private static func quarantine(identityID: String) -> String? {
        let url = fileURL(for: identityID)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let dest = url.deletingPathExtension().appendingPathExtension("defekt-\(stamp).json")
        guard (try? FileManager.default.moveItem(at: url, to: dest)) != nil else { return nil }
        return dest.lastPathComponent
    }
}
