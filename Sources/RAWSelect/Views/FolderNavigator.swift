import SwiftUI
import AppKit

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
    @State private var hovering = false

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
    /// Background tint: selection wins, then path context, then a soft hover tint
    /// so it's visible that a row is clickable.
    private var rowFill: Color {
        if isCurrent { return .accentColor }
        if isAncestorOfCurrent { return .accentColor.opacity(0.12) }
        if hovering { return Color.primary.opacity(0.08) }
        return .clear
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
        .background(RoundedRectangle(cornerRadius: 6).fill(rowFill))
        .animation(.easeOut(duration: 0.12), value: hovering)
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onTapGesture(count: 2) { app.open(url, setBrowseRoot: false) }   // load images
        .onTapGesture(count: 1) { if canExpand { expanded.toggle() } }    // just navigate
        .help("Doppelklick lädt die Bilder dieses Ordners")
    }

    private func loadChildren() {
        // Fully explicit types + a plain loop: the previous chained filter+sorted with a
        // `try?`/`== true` (double-optional Bool) pushed the release-build type-checker past its
        // time budget, which cascaded into bogus "no member" errors across the whole function.
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey]
        let opts: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
        let urls: [URL] = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: opts)) ?? []
        var dirs: [URL] = []
        for child in urls {
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true { dirs.append(child) }
        }
        dirs.sort { (a: URL, b: URL) -> Bool in
            a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
        }
        children = dirs
        if isRootLevel && !(children?.isEmpty ?? true) { expanded = true }
    }
}
