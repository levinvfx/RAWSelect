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
        ToolbarItem(placement: .principal) {
            HStack(spacing: 14) {
                viewPicker
                sortMenu
            }
        }

        // Right-aligned: where the photos go next. Since macOS 26 trailing items follow the centre
        // group directly; the flexible spacer pushes them to the window edge again.
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.flexible, placement: .primaryAction)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            // Teilen: the app from Settings → "Bilder öffnen mit" (Lightroom by default), Google
            // Drive, the Finder — the three places the selection goes next. Nothing else.
            Menu {
                Button {
                    app.openSelectionInExternalApp()
                } label: {
                    Label { Text(app.openWithButtonTitle) } icon: {
                        AppIcon(path: app.openWithIconPath, fallback: "arrow.up.right.square")
                    }
                }
                Button {
                    app.sendToGoogleDrive(marked: false)
                } label: {
                    Label { Text(driveTitle) } icon: {
                        AppIcon(path: AppIcon.googleDrivePath, fallback: "icloud.and.arrow.up")
                    }
                }
                Button {
                    app.revealCurrent()
                } label: {
                    Label { Text("Im Finder anzeigen") } icon: { AppIcon(path: AppIcon.finderPath, fallback: "folder") }
                }
            } label: {
                Label("Teilen", systemImage: "square.and.arrow.up")
            }
            .menuStyle(.button)
            .disabled(app.currentGroup == nil || app.operation != nil)
            .help("In Lightroom öffnen, an Google Drive senden oder im Finder anzeigen")

            // Copy: pick a folder, copy (with XMP) — no menu, the one plain action.
            Button {
                app.copySelection()
            } label: {
                Label("Kopieren", systemImage: "doc.on.doc")
            }
            .disabled(app.currentGroup == nil || app.operation != nil)
            .help("Auswahl (inkl. XMP) in einen Ordner kopieren · alle markierten: ⌘⇧C. Die Farbmarkierungen bleiben in RAW Select.")
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

    private var driveTitle: String {
        app.googleDriveFolderName.map { "An Google Drive senden (\($0))" } ?? "An Google Drive senden…"
    }

}

/// A real app icon (Lightroom, Google Drive, Finder) for the Teilen menu, so each target is
/// recognisable at a glance. Sized like the icons in Finder's own "Öffnen mit" menu (16 pt): the
/// NSImage itself carries the size, because a menu row takes the image size as-is — a full-size
/// icon made every row twice as tall. Falls back to an SF Symbol when the app is not installed.
private struct AppIcon: View {
    static let finderPath = "/System/Library/CoreServices/Finder.app"
    static let googleDrivePath = "/Applications/Google Drive.app"
    let path: String
    let fallback: String
    var size: CGFloat = 16

    var body: some View {
        if !path.isEmpty, FileManager.default.fileExists(atPath: path),
           let icon = NSWorkspace.shared.icon(forFile: path).copy() as? NSImage {
            let _ = icon.size = NSSize(width: size, height: size)
            Image(nsImage: icon)
        } else {
            Image(systemName: fallback)
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
