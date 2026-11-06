import AppKit

/// Thin wrapper around Finder integration and file dialogs (AppKit).
enum FinderService {

    static func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
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

    /// Prompts for a folder inside Google Drive (starts there). A folder outside Drive is refused:
    /// "An Google Drive senden" must never quietly land on the local disk.
    static func chooseGoogleDriveFolder(current: String) -> URL? {
        let start = !current.isEmpty ? current : (CloudFolderService.googleDriveAccounts().first?.url.path ?? "")
        guard let url = chooseDestination(title: "Ordner in Google Drive wählen", startAt: start) else { return nil }
        guard CloudFolderService.provider(for: url) == "Google Drive" else {
            let alert = NSAlert()
            alert.messageText = "Dieser Ordner liegt nicht in Google Drive."
            alert.informativeText = "Wähle links unter „Orte“ Google Drive und darin den Ordner, in den die Bilder sollen."
            alert.runModal()
            return nil
        }
        return url
    }
}
