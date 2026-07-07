import SwiftUI

struct DetailView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: AppSettings

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
        } else {
            VStack(spacing: 0) {
                if settings.showMarkToolbar {
                    FilterBar()
                    Divider()
                }
                contentBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var contentBody: some View {
        if app.filteredGroups.isEmpty {
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
            .help("Ordner öffnen (⌘O)")
        }

        ToolbarItem(placement: .principal) {
            Picker("Ansicht", selection: $app.viewMode) {
                Image(systemName: "square.grid.2x2").tag(AppState.ViewMode.grid)
                Image(systemName: "photo").tag(AppState.ViewMode.loupe)
            }
            .pickerStyle(.segmented)
            .help("Zwischen Raster und grosser Vorschau wechseln")
        }

        ToolbarItemGroup(placement: .automatic) {
            Menu {
                Picker("Sortieren nach", selection: $settings.sortField) {
                    ForEach(SortField.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Umgekehrt", isOn: $settings.sortReversed)
            } label: {
                Label("Sortieren", systemImage: "arrow.up.arrow.down")
            }
            .help("Sortierreihenfolge")

            Button {
                app.toggleInfo()
            } label: {
                Label("Info", systemImage: app.showInfo ? "info.circle.fill" : "info.circle")
            }
            .help("EXIF-Infos ein/aus (I)")

            Button {
                app.toggleFullscreen()
            } label: {
                Label("Vollbild", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .help("Vollbild (F)")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                app.revealCurrent()
            } label: {
                Label("Im Finder anzeigen", systemImage: "arrow.up.forward.app")
            }
            .disabled(app.currentGroup == nil)
            .help("Aktuelles Bild im Finder anzeigen (⌘R)")
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Bilder + XMP kopieren…") { app.copySelection(includeSidecars: true) }
                Button("Nur Bilder kopieren (ohne XMP)…") { app.copySelection(includeSidecars: false) }
            } label: {
                Label("Kopieren", systemImage: "doc.on.doc")
            }
            .menuStyle(.button)
            .buttonStyle(.borderedProminent)   // clear blue button
            .tint(.blue)
            .disabled(app.selectionCount == 0)
            .help(app.selectionCount > 0
                  ? "\(app.selectionCount) ausgewählte Bilder kopieren – Art im Menü wählen"
                  : "Ausgewählte Bilder kopieren")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                app.requestMoveSelection()
            } label: {
                Label("Auswahl verschieben…", systemImage: "arrow.right.doc.on.clipboard")
            }
            .disabled(app.selectionCount == 0 || app.sourceIsExternal)
            .help(app.sourceIsExternal
                  ? "Verschieben ist von SD-Karten/externen Datenträgern deaktiviert."
                  : "Ausgewählte Bilder verschieben")
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
            Text("Kein Ordner geladen")
                .font(.title2.weight(.semibold))
            Text("Wähle links einen Datenträger, navigiere durch die Ordner und **doppelklicke** einen Ordner, um seine Bilder zu laden.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button("Ordner öffnen…") { app.openFolderDialog() }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
