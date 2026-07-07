import Foundation
import CryptoKit

/// Persists marks per source (identified by FolderIdentity) in
/// ~/Library/Application Support/RAW Select/Sessions/<hash>.json.
///
/// Marks are stored centrally and never written into the source folder, so an
/// SD card is never modified. Keyed by the group's volume-relative persist key.
struct SessionStore {

    struct SessionData: Codable {
        var identity: String
        var marks: [String: Int]   // persistKey -> mark (1…9)
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

    static func load(identityID: String) -> [String: Int] {
        let url = fileURL(for: identityID)
        guard let data = try? Data(contentsOf: url),
              let session = try? JSONDecoder().decode(SessionData.self, from: data) else {
            return [:]
        }
        return session.marks
    }

    static func save(identityID: String, marks: [String: Int]) {
        let nonZero = marks.filter { $0.value != 0 }
        let session = SessionData(identity: identityID, marks: nonZero)
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
