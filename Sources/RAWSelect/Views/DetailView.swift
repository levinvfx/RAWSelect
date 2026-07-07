import SwiftUI

struct DetailView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            StatusBar()
        }
        .toolbar { toolbarItems }
        .navigationTitle(app.rootURL?.lastPathComponent ?? AppInfo.name)
    }

    @ViewBuilder
    private var content: some View {
        if app.rootURL == nil {
            EmptyStateView()
        } else if app.filteredGroups.isEmpty {
            ContentUnavailableView(
                app.groups.isEmpty ? "Keine Bilder gefunden" : "Nichts in diesem Filter",
                systemImage: "photo",
                description: Text(app.groups.isEmpty
                    ? "In diesem Ordner wurden keine unterstützten Bilder gefunden."
                    : "Für diesen Filter gibt es keine Bilder.")
            )
        } else {
            switch app.viewMode {
            case .grid: ThumbnailGridView()
            case .loupe: LoupeView()
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                app.openFolderDialog()
            } label: {
                Label("Ordner öffnen", systemImage: "folder")
            }
        }

        ToolbarItem(placement: .principal) {
            Picker("Ansicht", selection: $app.viewMode) {
                Image(systemName: "square.grid.2x2").tag(AppState.ViewMode.grid)
                Image(systemName: "photo").tag(AppState.ViewMode.loupe)
            }
            .pickerStyle(.segmented)
            .help("Zwischen Raster und grosser Vorschau wechseln")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                app.revealSelected()
            } label: {
                Label("Im Finder anzeigen", systemImage: "arrow.up.forward.app")
            }
            .disabled(app.selectedGroup == nil)

            Button {
                app.copyMarked()
            } label: {
                Label("Markierte kopieren…", systemImage: "doc.on.doc")
            }
            .disabled(app.markedCount == 0)

            Button {
                app.requestMoveMarked()
            } label: {
                Label("Markierte verschieben…", systemImage: "arrow.right.doc.on.clipboard")
            }
            .disabled(app.markedCount == 0 || app.sourceIsExternal)
            .help(app.sourceIsExternal
                  ? "Verschieben ist von SD-Karten/externen Datenträgern deaktiviert."
                  : "Markierte Bilder verschieben")
        }
    }
}

private struct EmptyStateView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.stack")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary)
            Text("Kein Ordner geöffnet")
                .font(.title2.weight(.semibold))
            Text("Wähle links einen Datenträger oder öffne einen Ordner, um mit dem Sichten zu beginnen.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button("Ordner öffnen…") { app.openFolderDialog() }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
