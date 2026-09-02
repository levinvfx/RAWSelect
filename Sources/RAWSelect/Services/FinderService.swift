import AppKit

/// Thin wrapper around Finder integration and file dialogs (AppKit).
enum FinderService {

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func revealFolder(_ url: URL) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }

    /// Prompts for a folder to open (scan source).
    static func chooseFolder(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Öffnen"
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Prompts for a target folder (copy/move destination).
    static func chooseDestination(title: String, startAt: String = "") -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        if !startAt.isEmpty, FileManager.default.fileExists(atPath: startAt) {
            panel.directoryURL = URL(fileURLWithPath: startAt, isDirectory: true)
        }
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Zielordner wählen"
        return panel.runModal() == .OK ? panel.url : nil
    }
}
