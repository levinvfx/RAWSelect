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
        #if DEBUG
        .sheet(isPresented: $app.showExportWizard) { ExportWizard() }
        #endif
    }

    @ViewBuilder
    private var content: some View {
        if app.rootURL == nil {
            EmptyStateView()
        } else {
            VStack(spacing: 0) {
                if !app.focusMode {
                    FilterBar()
                    Divider()
                }
                contentBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            #if DEBUG
            .sheet(isPresented: $app.showEditor) {
                if let g = app.currentGroup { ImageEditorSheet(group: g) }
            }
            #endif
        }
    }

    @ViewBuilder
    private var contentBody: some View {
        if app.isScanning && app.groups.isEmpty {
            ScanningView(name: app.rootURL?.lastPathComponent ?? "")
        } else if app.filteredGroups.isEmpty {
            ContentUnavailableView {
                Label(app.groups.isEmpty ? (app.scanCancelled ? "Scan abgebrochen" : "Keine Bilder gefunden") : "Nichts in diesem Filter",
                      systemImage: app.scanCancelled && app.groups.isEmpty ? "stop.circle" : "photo")
            } description: {
                Text(app.groups.isEmpty
                    ? (app.scanCancelled ? "Der Scan wurde abgebrochen, bevor Bilder geladen waren. Ordner erneut öffnen, um fortzufahren."
                                         : "In diesem Ordner wurden keine unterstützten Bilder gefunden.")
                    : "Für diesen Filter gibt es keine Bilder.")
            } actions: {
                if !app.groups.isEmpty {
                    Button("Alle zeigen (⌥0)") { app.tagFilter.setAll(shown: true) }
                }
            }
        } else {
            switch app.viewMode {
            case .grid: ThumbnailGridView()
            case .list: PhotoListView()
            case .loupe: LoupeView()
            }
        }
    }

    /// Raster · Liste · grosse Ansicht — the same three ways of looking as in the Finder.
    private var viewPicker: some View {
        Picker("Ansicht", selection: $app.viewMode) {
            Label("Raster", systemImage: "square.grid.2x2").tag(AppState.ViewMode.grid)
            Label("Liste", systemImage: "list.bullet").tag(AppState.ViewMode.list)
            Label("Grosse Ansicht", systemImage: "photo").tag(AppState.ViewMode.loupe)
        }
        .labelStyle(.iconOnly)
        .pickerStyle(.segmented)
        .fixedSize()
        .help("Raster · Liste · grosse Ansicht (Return)")
    }

    /// Finder-style sort menu next to the view switch. The list's column headers set the same
    /// order (click: ascending → descending → none).
    private var sortMenu: some View {
        Menu {
            Picker("Sortieren nach", selection: $settings.sortField) {
                ForEach(SortField.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.inline)
            Divider()
            Picker("Reihenfolge", selection: $settings.sortReversed) {
                Text("Aufsteigend").tag(false)
                Text("Absteigend").tag(true)
            }
            .pickerStyle(.inline)
            .disabled(settings.sortField == .unsorted)
        } label: {
            Label("Sortieren", systemImage: "arrow.up.arrow.down")
        }
        .menuStyle(.button)
        .fixedSize()
        .help(settings.sortField == .unsorted
              ? "Sortieren: ohne (Reihenfolge der Karte)"
              : "Sortieren: \(settings.sortField.label), \(settings.sortReversed ? "absteigend" : "aufsteigend")")
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

        // Centred over the photos: how to look at them, and in which order.
        // Two items, not one HStack: a single toolbar item shows only ONE tooltip (the sort menu
        // showed the view switch's).
        ToolbarItemGroup(placement: .principal) {
            viewPicker
            sortMenu.padding(.leading, 8)
        }

        // Right-aligned: where the photos go next. Since macOS 26 trailing items follow the centre
        // group directly; the flexible spacer pushes them to the window edge again.
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.flexible, placement: .primaryAction)
        }
        // Where the photos go next, then a clear break before Kopieren. One toolbar item PER tile:
        // inside a single item macOS showed the first tooltip ("In Lightroom öffnen") on all of them.
        ToolbarItem(placement: .primaryAction) {
            ToolbarTile(title: app.openWithButtonTitle, disabled: tilesBusy, action: app.openSelectionInExternalApp) { openWithIcon }
        }
        ToolbarItem(placement: .primaryAction) {
            ToolbarTile(title: driveTitle, disabled: tilesBusy, action: { app.sendToGoogleDrive(marked: false) }) {
                Image(nsImage: BrandGlyph.googleDrive)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            ToolbarTile(title: "Im Finder anzeigen (⌘R)", disabled: tilesBusy, action: app.revealCurrent) {
                appIcon(BrandGlyph.finderPath, fallback: "folder")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            // A Divider on its own in the toolbar lies flat; draw the upright line ourselves.
            Rectangle().fill(Color.primary.opacity(0.18)).frame(width: 1, height: 18)
                .padding(.horizontal, ToolbarTileMetrics.groupGap)
        }
        ToolbarItem(placement: .primaryAction) {
            ToolbarTile(title: "Kopieren: Auswahl (inkl. XMP) in einen Ordner · alle markierten: ⌘⇧C",
                        disabled: tilesBusy, action: { app.copySelection() }) {
                Image(nsImage: BrandGlyph.copy).renderingMode(.template)
            }
        }

        #if DEBUG
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
        #endif

        // A little air between the last button and the window edge.
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
    }

    private var openWithIcon: some View {
        appIcon(app.openWithIconPath, fallback: "arrow.up.right.square")
    }

    @ViewBuilder
    private func appIcon(_ path: String, fallback: String) -> some View {
        if let icon = BrandGlyph.appIcon(path: path) {
            Image(nsImage: icon)
        } else {
            Image(systemName: fallback).font(.system(size: 16))
        }
    }

    private var tilesBusy: Bool { app.currentGroup == nil || app.operation != nil }

    private var driveTitle: String {
        app.googleDriveFolderName.map { "An Google Drive senden (\($0))" } ?? "An Google Drive senden…"
    }

}

private struct EmptyStateView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.stack")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary)
            Text("Ordner auswählen")
                .font(.title2.weight(.semibold))
            // No volume suggested: a card or a 2-TB disk opened as a whole can be far too much.
            Text("Wähle links auf einer Karte den Ordner mit den Bildern oder öffne einen Ordner.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button("Ordner öffnen…") { app.openFolderDialog() }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            Text("Tipp: **?** zeigt alle Tastaturkürzel.")
                .font(.caption).foregroundStyle(.tertiary)
                .padding(.top, 6)
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
            Text(app.scanFound > 0 ? "\(app.scanFound) Dateien gefunden…" : "Bilder werden gesucht und gruppiert.")
                .font(.callout).foregroundStyle(.tertiary)
                .monospacedDigit()
            Button("Abbrechen") { app.cancelScan() }
                .keyboardShortcut(.cancelAction)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
