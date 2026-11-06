import SwiftUI
import AppKit

struct SidebarView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        List {
            Section("Datenträger") {
                if app.volumes.isEmpty {
                    Text("Keine externen Datenträger")
                        .font(.callout).foregroundStyle(.secondary)
                        // Starts in the text column of the rows below.
                        .padding(.leading, SidebarMetrics.horizontalPadding + SidebarMetrics.iconWidth + SidebarMetrics.spacing)
                }
                ForEach(app.volumes) { volume in
                    SidebarRow(title: volume.name, systemImage: "sdcard",
                               isActive: app.browseRoot?.standardizedFileURL == volume.url.standardizedFileURL) {
                        app.browse(volume.url)
                    }
                }
                SidebarRow(title: "Ordner öffnen…", systemImage: "folder.badge.plus") { app.openFolderDialog() }
            }

            // Same folder on the internal disk the next day: one click instead of the whole tree.
            if !settings.recentFolders.isEmpty {
                Section("Zuletzt geöffnet") {
                    let names = settings.recentFolders.map { ($0 as NSString).lastPathComponent }
                    ForEach(settings.recentFolders, id: \.self) { path in
                        let name = (path as NSString).lastPathComponent
                        // Several "02_export": the parent folder tells them apart.
                        let parent = ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent
                        SidebarRow(title: name, systemImage: "clock",
                                   detail: names.filter { $0 == name }.count > 1 ? parent : nil) {
                            app.openRecent(path)
                        }
                        .help(path)
                    }
                }
            }

            if let browseRoot = app.browseRoot {
                Section("Ordner") {
                    FolderNavigator(root: browseRoot)
                        .id(browseRoot)   // rebuild the tree when the volume/root changes
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(AppInfo.name)
    }
}

/// Shared sidebar geometry: every row (volumes, "Ordner öffnen…", recent folders, folder tree)
/// puts its icon in the same fixed column, so icons and text line up across sections.
enum SidebarMetrics {
    static let iconWidth: CGFloat = 20
    static let spacing: CGFloat = 6
    static let verticalPadding: CGFloat = 4
    static let horizontalPadding: CGFloat = 8
    static let cornerRadius: CGFloat = 6
}

/// One clickable sidebar row with hover feedback and an optional active highlight,
/// matching the folder tree's interaction feel.
private struct SidebarRow: View {
    let title: String
    let systemImage: String
    var detail: String? = nil
    var isActive = false
    let action: () -> Void
    @State private var hovering = false

    private var rowFill: Color {
        if isActive { return .accentColor.opacity(0.15) }
        if hovering { return Color.primary.opacity(0.08) }
        return .clear
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: SidebarMetrics.spacing) {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: SidebarMetrics.iconWidth)
                Text(title).lineLimit(1).truncationMode(.middle)
                if let detail {
                    Text(detail).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, SidebarMetrics.verticalPadding)
            .padding(.horizontal, SidebarMetrics.horizontalPadding)
            .background(RoundedRectangle(cornerRadius: SidebarMetrics.cornerRadius).fill(rowFill))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { inside in
            hovering = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
