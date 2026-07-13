import Foundation
import CryptoKit

/// Persists marks per source (identified by FolderIdentity) in
/// ~/Library/Application Support/RAW Select/Sessions/<hash>.json.
///
/// Marks are stored centrally and never written into the source folder, so an
/// SD card is never modified. Keyed by the group's volume-relative persist key.
struct SessionStore {

    /// Per-photo culling state, keyed by persistKey.
    struct PhotoState: Codable {
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

    static func load(identityID: String) -> [String: PhotoState] {
        let url = fileURL(for: identityID)
        guard let data = try? Data(contentsOf: url),
              let session = try? JSONDecoder().decode(SessionData.self, from: data) else {
            return [:]
        }
        return session.states
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

    static func save(identityID: String, states: [String: PhotoState]) {
        let nonDefault = states.filter { !$0.value.isDefault }
        let session = SessionData(identity: identityID, states: nonDefault)
        let url = fileURL(for: identityID)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(session)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("RAW Select: failed to save session: \(error.localizedDescription)")
        }
    }
}
