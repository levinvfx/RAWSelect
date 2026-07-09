import SwiftUI
import AppKit

struct SidebarView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        List {
            Section("Datenträger") {
                if app.volumes.isEmpty {
                    Text("Keine externen Datenträger")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(app.volumes) { volume in
                    VolumeRow(volume: volume)
                }
                Button { app.openFolderDialog() } label: {
                    Label("Ordner öffnen…", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.plain)
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

/// A single external volume row with hover feedback and an active highlight,
/// matching the folder tree's interaction feel.
private struct VolumeRow: View {
    @EnvironmentObject var app: AppState
    let volume: VolumeInfo
    @State private var hovering = false

    private var isActive: Bool {
        app.browseRoot?.standardizedFileURL == volume.url.standardizedFileURL
    }
    private var rowFill: Color {
        if isActive { return .accentColor.opacity(0.15) }
        if hovering { return Color.primary.opacity(0.08) }
        return .clear
    }

    var body: some View {
        Button { app.browse(volume.url) } label: {
            Label(volume.name, systemImage: "sdcard")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3).padding(.horizontal, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(rowFill))
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
