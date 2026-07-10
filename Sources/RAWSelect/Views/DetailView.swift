import SwiftUI

struct DetailView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            content
            if !app.focusMode {
                Divider()
                StatusBar()
            }
        }
        .toolbar { toolbarItems }
        .navigationTitle(app.rootURL?.lastPathComponent ?? AppInfo.name)
        .sheet(isPresented: $app.showExportWizard) {
            ExportWizard()
        }
    }

    @ViewBuilder
    private var content: some View {
        if app.rootURL == nil {
            EmptyStateView()
        } else {
            VStack(spacing: 0) {
                if settings.showMarkToolbar && !app.focusMode {
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
        if app.isScanning && app.groups.isEmpty {
            ScanningView(name: app.rootURL?.lastPathComponent ?? "")
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
        }

        // Export actions, most important first so they never fall into overflow.
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Bilder + XMP kopieren…") { app.copySelection(includeSidecars: true) }
                Button("Nur Bilder kopieren (ohne XMP)…") { app.copySelection(includeSidecars: false) }
            } label: {
                Label("Kopieren", systemImage: "doc.on.doc")
            }
            .menuStyle(.button)
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            .disabled(app.selectionCount == 0)
            .help("Originale kopieren – Art im Menü wählen")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                app.showExportWizard = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "wand.and.stars")
                    Text("Export JPEG")
                    Text("Lr")
                        .font(.caption2.weight(.bold)).foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.10, green: 0.45, blue: 0.95)))
                }
            }
            .buttonStyle(.bordered)
            .disabled(app.groups.isEmpty)
            .help("Export JPEG mit Lightroom Classic")
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

/// Shown while a folder is being scanned and no images have arrived yet — so the
/// grid never briefly flashes a false "Keine Bilder gefunden".
private struct ScanningView: View {
    @EnvironmentObject var app: AppState
    let name: String
    var body: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text(name.isEmpty ? "Ordner wird gescannt…" : "\(name) wird gescannt…")
                .font(.headline).foregroundStyle(.secondary)
            Text("Bilder werden gesucht und gruppiert.")
                .font(.callout).foregroundStyle(.tertiary)
            Button("Abbrechen") { app.cancelScan() }
                .keyboardShortcut(.cancelAction)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
