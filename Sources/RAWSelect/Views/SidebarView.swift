import SwiftUI

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
                    Button { app.browse(volume.url) } label: {
                        Label(volume.name, systemImage: "sdcard")
                    }
                    .buttonStyle(.plain)
                }
                Button { app.openFolderDialog() } label: {
                    Label("Ordner öffnen…", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.plain)
            }

            if let browseRoot = app.browseRoot {
                Section("Ordner") {
                    FolderNavigator(root: browseRoot)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(AppInfo.name)
    }
}
