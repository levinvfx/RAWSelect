import SwiftUI

/// A lazily-loaded folder tree in the sidebar. Click a folder to scan just that
/// subfolder (instead of the whole card). Subfolders load when expanded.
struct FolderNavigator: View {
    let root: URL

    var body: some View {
        FolderRow(url: root, isRootLevel: true)
    }
}

private struct FolderRow: View {
    @EnvironmentObject var app: AppState
    let url: URL
    var isRootLevel: Bool = false

    @State private var expanded = false
    @State private var children: [URL]?

    private var isCurrent: Bool {
        app.rootURL?.standardizedFileURL == url.standardizedFileURL
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            if let children {
                if children.isEmpty {
                    Text("Keine Unterordner")
                        .font(.caption).foregroundStyle(.tertiary)
                } else {
                    ForEach(children, id: \.self) { FolderRow(url: $0) }
                }
            } else {
                ProgressView().controlSize(.small)
            }
        } label: {
            Button {
                app.open(url, setBrowseRoot: false)
            } label: {
                Label(url.lastPathComponent, systemImage: isCurrent ? "folder.fill" : "folder")
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
                    .fontWeight(isCurrent ? .semibold : .regular)
            }
            .buttonStyle(.plain)
        }
        .onChange(of: expanded) { _, isOpen in
            if isOpen && children == nil { loadChildren() }
        }
        .onAppear { if isRootLevel && children == nil { loadChildren(); expanded = true } }
    }

    private func loadChildren() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])) ?? []
        children = urls
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
