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
            ContentUnavailableView(
                app.groups.isEmpty ? (app.scanCancelled ? "Scan abgebrochen" : "Keine Bilder gefunden") : "Nichts in diesem Filter",
                systemImage: app.scanCancelled && app.groups.isEmpty ? "stop.circle" : "photo",
                description: Text(app.groups.isEmpty
                    ? (app.scanCancelled ? "Der Scan wurde abgebrochen, bevor Bilder geladen waren. Ordner erneut öffnen, um fortzufahren."
                                         : "In diesem Ordner wurden keine unterstützten Bilder gefunden.")
                    : "Für diesen Filter gibt es keine Bilder.")
            )
        } else {
            switch app.viewMode {
            case .grid: ThumbnailGridView()
            case .loupe: LoupeView()
            case .compare: CompareView()
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
            // Third segment = compare, so the control always reflects the real mode.
            Picker("Ansicht", selection: Binding(
                get: { app.viewMode },
                set: { mode in
                    if mode == .compare { app.enterCompare() }
                    else { if app.viewMode == .compare { app.exitCompare() }; app.viewMode = mode }
                }
            )) {
                Image(systemName: "square.grid.2x2").tag(AppState.ViewMode.grid)
                Image(systemName: "photo").tag(AppState.ViewMode.loupe)
                Image(systemName: "rectangle.split.2x1").tag(AppState.ViewMode.compare)
            }
            .pickerStyle(.segmented)
            .help("Raster · grosse Vorschau · Vergleich A|B (C)")
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

        // The one action that ends a culling session: copy the selection (always with XMP).
        ToolbarItem(placement: .primaryAction) {
            Button {
                app.copySelection(includeSidecars: true)
            } label: {
                Label("Auswahl kopieren…", systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            .disabled(app.selectionCount == 0)
            .help("Ausgewählte Originale (inkl. XMP) flach in einen Zielordner kopieren")
        }

        // Combined "Öffnen" menu: open the selection in the external app
        // (Lightroom / chosen app) or reveal it in the Finder. Merges the two former
        // separate toolbar buttons into one dropdown.
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    app.openSelectionInExternalApp()
                } label: {
                    Label(app.openWithButtonTitle, systemImage: "arrow.up.right.square")
                }
                .disabled(app.selectionCount == 0)

                Button {
                    app.revealCurrent()
                } label: {
                    Label("Im Finder anzeigen", systemImage: "arrow.up.forward.app")
                }
                .disabled(app.currentGroup == nil)
            } label: {
                Label("Öffnen", systemImage: "arrow.up.right.square")
            }
            .menuStyle(.button)
            .disabled(app.currentGroup == nil)
            .help("In App öffnen oder im Finder anzeigen")
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
