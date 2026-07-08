import SwiftUI

/// A lazily-loaded folder tree in the sidebar. Single click navigates (expands),
/// double click loads that folder's images. Folders without subfolders can't be
/// expanded (no disclosure triangle).
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
    /// True when the loaded folder lives somewhere below this one (path context).
    private var isAncestorOfCurrent: Bool {
        guard let root = app.rootURL?.standardizedFileURL else { return false }
        return root.path.hasPrefix(url.standardizedFileURL.path + "/")
    }
    private var canExpand: Bool { (children?.isEmpty == false) }

    var body: some View {
        Group {
            if canExpand {
                DisclosureGroup(isExpanded: $expanded) {
                    ForEach(children ?? [], id: \.self) { FolderRow(url: $0) }
                } label: {
                    label
                }
            } else {
                // Leaf folder – no triangle. Slight leading inset to align with
                // the expandable siblings.
                label.padding(.leading, 14)
            }
        }
        .onAppear { if children == nil { loadChildren() } }
    }

    private var iconName: String {
        if isCurrent || isAncestorOfCurrent { return "folder.fill" }
        return "folder"
    }
    private var iconColor: Color {
        if isCurrent { return .white }
        if isAncestorOfCurrent { return .accentColor }
        return .secondary
    }

    private var label: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 16)
            Text(url.lastPathComponent)
                .foregroundStyle(isCurrent ? Color.white : Color.primary)
                .fontWeight(isCurrent || isAncestorOfCurrent ? .semibold : .regular)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isCurrent ? Color.accentColor
                      : (isAncestorOfCurrent ? Color.accentColor.opacity(0.12) : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { app.open(url, setBrowseRoot: false) }   // load images
        .onTapGesture(count: 1) { if canExpand { expanded.toggle() } }    // just navigate
        .help("Doppelklick lädt die Bilder dieses Ordners")
    }

    private func loadChildren() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])) ?? []
        children = urls
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        if isRootLevel && !(children?.isEmpty ?? true) { expanded = true }
    }
}
