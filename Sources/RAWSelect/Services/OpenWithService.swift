import AppKit
import UniformTypeIdentifiers

/// Opens image files in an external editor (Lightroom / Lightroom Classic / …).
/// The chosen app is stored as a path in AppSettings and can be changed anytime.
enum OpenWithService {

    /// Installed apps whose name contains "Lightroom" (Classic + cloud), offered as
    /// quick picks in Settings. Scans the standard Applications folders.
    static func lightroomApps() -> [URL] {
        let dirs = ["/Applications", (NSHomeDirectory() as NSString).appendingPathComponent("Applications")]
        let fm = FileManager.default
        var found: [URL] = []
        for dir in dirs {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for name in items where name.hasSuffix(".app") && name.localizedCaseInsensitiveContains("lightroom") {
                found.append(URL(fileURLWithPath: dir).appendingPathComponent(name))
            }
        }
        return found.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

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
