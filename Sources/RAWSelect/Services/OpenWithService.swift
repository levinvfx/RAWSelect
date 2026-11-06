import AppKit
import UniformTypeIdentifiers

/// Opens image files in an external editor (Lightroom / Lightroom Classic / …).
/// The chosen app is stored as a path in AppSettings and can be changed anytime.
enum OpenWithService {

    /// Installed Lightroom apps (Classic first, then the cloud version), offered as quick picks.
    /// Adobe installs them one folder deep ("/Applications/Adobe Lightroom Classic/…app"), so the
    /// bundle IDs are asked first and the Applications folders (incl. their Lightroom subfolders)
    /// are scanned as a fallback.
    static func lightroomApps() -> [URL] {
        var found: [URL] = []
        for id in ["com.adobe.LightroomClassicCC7", "com.adobe.lightroomCC"] {
            found += NSWorkspace.shared.urlsForApplications(withBundleIdentifier: id)
        }
        let fm = FileManager.default
        for dir in ["/Applications", (NSHomeDirectory() as NSString).appendingPathComponent("Applications")] {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for name in items where name.localizedCaseInsensitiveContains("lightroom") {
                let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
                if name.hasSuffix(".app") { found.append(url); continue }
                for inner in (try? fm.contentsOfDirectory(atPath: url.path)) ?? []
                where inner.hasSuffix(".app") && inner.localizedCaseInsensitiveContains("lightroom") {
                    found.append(url.appendingPathComponent(inner))
                }
            }
        }
        var seen = Set<String>()
        let unique = found.map(\.standardizedFileURL).filter { seen.insert($0.path).inserted }
        // Classic first: it is the culling photographer's usual next step.
        return unique.sorted { a, b in
            let ca = a.lastPathComponent.contains("Classic"), cb = b.lastPathComponent.contains("Classic")
            return ca != cb ? ca : a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
        }
    }

    /// Scanned once per launch: the toolbar redraws on every selection change and must not list
    /// /Applications each time.
    static let installedLightroomApps: [URL] = lightroomApps()

    /// Opens the given files with the app at `appPath`. Returns false if the app is
    /// missing (so the caller can clear the stale setting and ask again).
    @discardableResult
    static func open(_ files: [URL], withAppAt appPath: String) -> Bool {
        guard !appPath.isEmpty, FileManager.default.fileExists(atPath: appPath), !files.isEmpty else { return false }
        let cfg = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(files, withApplicationAt: URL(fileURLWithPath: appPath),
                                configuration: cfg, completionHandler: nil)
        return true
    }

    /// File picker to choose an application (defaults to /Applications).
    static func chooseApp() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "App zum Öffnen wählen"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Auswählen"
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Display name for an app path (file name without the ".app" extension).
    static func appName(_ path: String) -> String {
        path.isEmpty ? "" : (path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
    }
}
