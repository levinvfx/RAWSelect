import Foundation

/// Cloud folders macOS shows in the Finder under "Orte" (Google Drive, OneDrive, Dropbox …).
/// RAW Select never talks to a cloud service itself: the provider's own Mac app uploads what we
/// copy into its folder. No login in the app, and the update check stays the only connection.
enum CloudFolderService {

    struct Account: Equatable {
        let account: String   // "name@gmail.com"
        let url: URL          // ~/Library/CloudStorage/GoogleDrive-name@gmail.com
    }

    /// Download page of "Google Drive für Desktop" (opened only on the user's click).
    static let googleDriveDownloadURL = URL(string: "https://www.google.com/drive/download/")!

    /// Where macOS mounts File-Provider clouds: one folder per provider and account.
    static var cloudStorageRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/CloudStorage", isDirectory: true)
    }
    static var iCloudDriveRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    }

    /// Accounts set up in "Google Drive für Desktop" (folders named "GoogleDrive-<mail>").
    /// Only lists the top level — the contents stay untouched until the user picks a folder.
    static func googleDriveAccounts(in root: URL = cloudStorageRoot) -> [Account] {
        let prefix = "GoogleDrive-"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.sorted().compactMap { name in
            guard name.hasPrefix(prefix) else { return nil }
            return Account(account: String(name.dropFirst(prefix.count)),
                           url: root.appendingPathComponent(name, isDirectory: true))
        }
    }

    /// "Google Drive" when `url` lies in a synced cloud folder; nil for local disks, cards and NAS.
    static func provider(for url: URL, cloudRoot: URL = cloudStorageRoot,
                         iCloudRoot: URL = iCloudDriveRoot) -> String? {
        let path = url.resolvingSymlinksInPath().path
        if isInside(path, iCloudRoot) { return "iCloud Drive" }
        let base = cloudRoot.resolvingSymlinksInPath().path
        guard isInside(path, cloudRoot),
              let folder = path.dropFirst(base.count).split(separator: "/").first else { return nil }
        // "GoogleDrive-name@gmail.com", "OneDrive-Persönlich", "Dropbox" → the part before the dash.
        let key = folder.split(separator: "-", maxSplits: 1).first.map(String.init) ?? String(folder)
        let known = ["GoogleDrive": "Google Drive", "OneDrive": "OneDrive", "Dropbox": "Dropbox", "Box": "Box"]
        return known[key] ?? key
    }

    /// Strictly below `root` — "CloudStorageOld" next to "CloudStorage" does not count.
    private static func isInside(_ path: String, _ root: URL) -> Bool {
        let base = root.resolvingSymlinksInPath().path
        return path.hasPrefix(base + "/")
    }
}
