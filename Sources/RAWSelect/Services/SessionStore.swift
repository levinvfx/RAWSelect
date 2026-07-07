import Foundation
import CryptoKit

/// Persists marks per scanned folder in
/// ~/Library/Application Support/RAW Select/Sessions/<hash>.json.
///
/// Marks are stored centrally and never written into the source folder, so an
/// SD card is never modified. Keyed by the group's stable relative id.
struct SessionStore {

    struct SessionData: Codable {
        var rootPath: String
        var marks: [String: Int]   // groupID -> mark (1…9)
    }

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("RAW Select/Sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func fileURL(for root: URL) -> URL {
        let path = root.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(path.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(hex).json")
    }

    static func load(root: URL) -> [String: Int] {
        let url = fileURL(for: root)
        guard let data = try? Data(contentsOf: url),
              let session = try? JSONDecoder().decode(SessionData.self, from: data) else {
            return [:]
        }
        return session.marks
    }

    static func save(root: URL, marks: [String: Int]) {
        let nonZero = marks.filter { $0.value != 0 }
        let session = SessionData(rootPath: root.standardizedFileURL.path, marks: nonZero)
        let url = fileURL(for: root)
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
