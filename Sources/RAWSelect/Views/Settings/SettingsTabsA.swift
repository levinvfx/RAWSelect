import SwiftUI

// MARK: - 1. Allgemein

struct GeneralSettingsTab: View {
    @EnvironmentObject var settings: AppSettings
    var body: some View {
        Form {
            Section {
                SettingPicker(title: "Startverhalten", help: "Legt fest, was RAW Select beim Starten anzeigen soll.",
                              selection: $settings.startBehavior) {
                    ForEach(StartBehavior.allCases) { Text($0.label).tag($0) }
                }
            }
            Section {
                SettingToggle(title: "Letzte Session wiederherstellen",
                              help: "Speichert geöffnete Ordner, Auswahl und Markierungen lokal.", isOn: $settings.restoreSession)
                SettingToggle(title: "Letzten geöffneten Ordner merken",
                              help: "Merkt sich den zuletzt verwendeten Ordner oder Datenträger.", isOn: $settings.rememberLastFolder)
                SettingToggle(title: "Fensterposition und Layout merken",
                              help: "Stellt Fenstergrösse, Sidebar-Zustand und Layout wieder her.", isOn: $settings.rememberWindow)
                SettingToggle(title: "Nach App-Start automatisch scannen",
                              help: "Scannt den letzten Ordner automatisch neu. Kann bei grossen Ordnern dauern.", isOn: $settings.autoScanOnLaunch)
            }
            Section {
                SettingToggle(title: "Warnen, wenn beim Beenden ein Vorgang läuft",
                              help: "Verhindert, dass Kopier-, Verschiebe- oder Scanvorgänge versehentlich abgebrochen werden.", isOn: $settings.warnOnQuitDuringOp)
                SettingToggle(title: "Abschluss-Benachrichtigung anzeigen",
                              help: "Zeigt eine macOS-Benachrichtigung, wenn Kopieren oder Verschieben fertig ist.", isOn: $settings.completionNotification)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 2. Quellen

struct SourcesSettingsTab: View {
    @EnvironmentObject var settings: AppSettings

    private let types: [(ext: String, label: String)] = [
        ("arw", "Sony RAW .ARW"), ("cr2", "Canon RAW .CR2"), ("cr3", "Canon RAW .CR3"),
        ("nef", "Nikon RAW .NEF"), ("raf", "Fuji RAW .RAF"), ("dng", "Adobe DNG .DNG"),
        ("jpg", "JPEG .JPG/.JPEG"), ("heic", "HEIC .HEIC"), ("png", "PNG .PNG")
    ]

    var body: some View {
        Form {
            Section {
                SettingToggle(title: "SD-Karten und externe Datenträger automatisch erkennen",
                              help: "RAW Select prüft /Volumes und erkennt neue Datenträger automatisch.", isOn: $settings.autoDetectVolumes)
                SettingPicker(title: "Verhalten bei erkannter SD-Karte",
                              help: "Bestimmt, was passiert, wenn ein Kamera-Datenträger erkannt wird.", selection: $settings.sdBehavior) {
                    ForEach(SDBehavior.allCases) { Text($0.label).tag($0) }
                }
            }
            Section {
                SettingToggle(title: "Nur typische Kameraordner scannen",
                              help: "Bevorzugt DCIM, PRIVATE, MISC statt des ganzen Datenträgers.", isOn: $settings.cameraFoldersOnly)
                SettingToggle(title: "Unterordner rekursiv scannen",
                              help: "Findet Bilder auch in Unterordnern.", isOn: $settings.recursiveScan)
                SettingToggle(title: "Versteckte Dateien und Systemdateien ignorieren",
                              help: "Ignoriert .DS_Store, versteckte macOS-Dateien und Systemordner.", isOn: $settings.ignoreHidden)
                SettingToggle(title: "Bei App-Fokus zurück neu prüfen",
                              help: "Prüft beim Zurückkehren, ob neue Dateien oder Datenträger da sind.", isOn: $settings.rescanOnFocus)
                SettingPicker(title: "Scan-Modus",
                              help: "Schnell ist ideal für SD-Karten. Vollständig nur, wenn Bilder ausserhalb der Kameraordner liegen.", selection: $settings.scanMode) {
                    ForEach(ScanMode.allCases) { Text($0.label).tag($0) }
                }
            }
            Section("Unterstützte Dateitypen") {
                ForEach(types, id: \.ext) { type in
                    Toggle(type.label, isOn: typeBinding(type.ext))
                }
            }
        }
        .formStyle(.grouped)
    }

    private func typeBinding(_ ext: String) -> Binding<Bool> {
        Binding(
            get: { settings.enabledTypes.contains(ext) },
            set: { on in
                var set = settings.enabledTypes
                if on { if !set.contains(ext) { set.append(ext) } } else { set.removeAll { $0 == ext } }
                if ext == "jpg" { // keep jpeg in sync with jpg
                    set.removeAll { $0 == "jpeg" }
                    if on { set.append("jpeg") }
                }
                settings.enabledTypes = set
            }
        )
    }
}

// MARK: - 3. Ansicht & Preview

struct ViewSettingsTab: View {
    @EnvironmentObject var settings: AppSettings
    var body: some View {
        Form {
            Section("Raster / Contact Sheet") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Thumbnail-Grösse")
                        Spacer()
                        Text("\(Int(settings.thumbnailSize)) px").foregroundStyle(.secondary).monospacedDigit()
                    }
                    Slider(value: $settings.thumbnailSize, in: 80...260, step: 4)
                }
                SettingPicker(title: "Sortieren nach", selection: $settings.sortField) {
                    ForEach(SortField.allCases) { Text($0.label).tag($0) }
                }
                SettingToggle(title: "Sortierung umkehren", isOn: $settings.sortReversed)
                SettingToggle(title: "Dateiname unter Thumbnail anzeigen", isOn: $settings.showFilename)
                SettingToggle(title: "Dateityp-Badge anzeigen", help: "Kleine Badges wie RAW, JPG oder RAW+JPG.", isOn: $settings.showTypeBadge)
                SettingToggle(title: "Markierungs-Badge anzeigen", help: "Zeigt im Thumbnail, ob ein Bild mit 1–9 markiert ist.", isOn: $settings.showMarkBadge)
                SettingToggle(title: "Aufnahmedatum unter Thumbnail anzeigen", help: "Hilfreich, macht das Grid aber unruhiger.", isOn: $settings.showDateUnderThumb)
                SettingToggle(title: "RAW+JPG als ein Bild anzeigen", help: "Fasst DSC0123.ARW und DSC0123.JPG als ein Bildset zusammen.", isOn: $settings.groupRawJpg)
            }
            Section("Preview / Navigation") {
                SettingToggle(title: "Bild automatisch an Preview-Bereich anpassen", isOn: $settings.fitToPreview)
                SettingToggle(title: "Rotation automatisch beachten", isOn: $settings.respectRotation)
                SettingToggle(title: "Preview und Grid synchron halten", help: "Das passende Thumbnail bleibt im Grid ausgewählt.", isOn: $settings.syncPreviewGrid)
                SettingToggle(title: "Am Ende wieder zum Anfang springen", help: "Navigation springt nach dem letzten Bild zum ersten.", isOn: $settings.wrapNavigation)
                SettingToggle(title: "100%-Zoom mit Taste Z", isOn: $settings.zoomWithZ)
                SettingToggle(title: "Beim Zoomen Perfect Preview laden", help: "Lädt beim Schärfecheck die beste benötigte Vorschau nach.", isOn: $settings.loadPerfectOnZoom)
            }
            Section("2-Stufen-Preview") {
                SettingToggle(title: "Instant Preview immer zuerst anzeigen", help: "Zeigt sofort eine einfache Vorschau, damit nie ein leerer Ladezustand entsteht.", isOn: $settings.instantFirst)
                SettingPicker(title: "Maximale Instant-Preview-Grösse", help: "Kleiner = schneller, grösser = besser.", selection: $settings.instantSize) {
                    ForEach(InstantSize.allCases) { Text($0.label).tag($0) }
                }
                SettingPicker(title: "Instant-Preview-Qualität", help: "Darf etwas weich sein, soll aber sofort erscheinen.", selection: $settings.instantQuality) {
                    ForEach(QualityLevel.allCases) { Text($0.label).tag($0) }
                }
                SettingToggle(title: "Perfect Preview automatisch laden", help: "Lädt im Hintergrund eine hochwertige Vorschau und ersetzt die Instant Preview.", isOn: $settings.perfectAuto)
                SettingPicker(title: "Perfect-Preview-Qualität", help: "Bildschirmoptimiert lädt nur so viel Auflösung, wie der Preview-Bereich und dein Display brauchen.", selection: $settings.perfectQuality) {
                    ForEach(PerfectQuality.allCases) { Text($0.label).tag($0) }
                }
                SettingToggle(title: "Retina-/Display-Scale berücksichtigen", help: "Sorgt für scharfe Vorschau auf Retina-Displays.", isOn: $settings.respectScale)
                SettingToggle(title: "Wechsel von Instant zu Perfect weich anzeigen", help: "Verhindert hartes Flackern beim Austausch.", isOn: $settings.smoothPreviewSwap)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 4. Markierungen

struct MarkSettingsTab: View {
    @EnvironmentObject var settings: AppSettings
    var body: some View {
        Form {
            Section {
                SettingToggle(title: "Nur eine Markierung pro Bild erlauben", help: "Ein Bild gehört genau einer Kategorie. Macht Export und Filter klarer.", isOn: $settings.singleMarkPerPhoto)
                SettingToggle(title: "Taste 0 entfernt Markierung", isOn: $settings.zeroClearsMark)
                SettingToggle(title: "Nach Markierung automatisch zum nächsten Bild springen", help: "Perfekt fürs schnelle Culling.", isOn: $settings.autoAdvance)
                SettingPicker(title: "Richtung bei Auto-Advance", selection: $settings.advanceDirection) {
                    ForEach(AdvanceDirection.allCases) { Text($0.label).tag($0) }
                }
            }
            Section {
                SettingToggle(title: "Markierungen lokal speichern", help: "Speichert Markierungen lokal, ohne Originaldateien zu verändern.", isOn: $settings.storeMarksLocally)
                SettingToggle(title: "Markierungen in RAW-Dateien schreiben", help: "RAW Select verändert keine Original-RAW-Dateien.", isOn: .constant(false), disabled: true)
                SettingToggle(title: "Markierungsleiste in Toolbar anzeigen", isOn: $settings.showMarkToolbar)
                SettingToggle(title: "Beim Zurücksetzen aller Markierungen warnen", isOn: $settings.warnOnResetMarks)
            }
            Section("Markierungsnamen und Farben") {
                ForEach($settings.marks) { $mark in
                    MarkEditorRow(mark: $mark)
                }
                SettingNote(text: "Diese Namen werden für Badges, Filter und Export-Ordner verwendet.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct MarkEditorRow: View {
    @Binding var mark: MarkDefinition
    var body: some View {
        HStack(spacing: 10) {
            Text("\(mark.id)").font(.callout.monospacedDigit().weight(.semibold))
                .frame(width: 16)
            ColorPicker("", selection: Binding(
                get: { mark.color },
                set: { mark.colorHex = $0.hexString }
            ), supportsOpacity: false)
            .labelsHidden()
            TextField("Name", text: $mark.name)
                .textFieldStyle(.roundedBorder)
            Button {
                if let d = MarkDefinition.defaults.first(where: { $0.id == mark.id }) { mark = d }
            } label: { Image(systemName: "arrow.uturn.backward") }
            .buttonStyle(.borderless)
            .help("Diese Zeile zurücksetzen")
        }
    }
}
