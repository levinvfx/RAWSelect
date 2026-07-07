import SwiftUI
import AppKit

/// Apple-like configuration sheet for the Photoshop-powered JPEG export.
/// One clean scrolling dialog covering all steps, then progress and result.
struct PhotoshopExportWizard: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    enum Phase { case configure, running, done }
    @State private var phase: Phase = .configure

    // Step 1 – images
    @State private var source: ExportImageSource = .allMarked
    @State private var useJpgInstead = false
    // Step 2 – preset
    @State private var presetURL: URL?
    // Step 3 – smart exposure
    @State private var strength: SmartExposure = .standard
    @State private var maxEV: SmartExposureEV = .ev07
    @State private var protectHi = true
    @State private var protectLo = true
    @State private var respectIntent = true
    @State private var results: [SmartExposureResult] = []
    @State private var analyzing = false
    // Step 4 – jpeg
    @State private var quality: JPEGQuality = .q90
    @State private var colorSpace: ColorSpaceChoice = .sRGB
    @State private var exportSize: ExportSizeChoice = .original
    @State private var customEdge: Double = 4000
    @State private var sharpen: SharpenChoice = .off
    // Step 5 – target
    @State private var targetURL: URL?
    @State private var folderStructure: ExportFolderStructure = .perMark
    @State private var conflict: ConflictMode = .rename
    // running / result
    @State private var done = 0
    @State private var total = 0
    @State private var currentName = ""
    @State private var stage: ExportStage = .preparing
    @State private var successCount = 0
    @State private var failures: [ExportFailure] = []
    @State private var tempWarning: String?
    @State private var errorMessage: String?
    @State private var confirmOverwrite = false
    private let cancelToken = CancellationToken()

    private var selectedGroups: [PhotoGroup] { app.groups(for: source) }
    private var photoshopAvailable: Bool { PhotoshopExportService.isAvailable(preferredPath: settings.photoshopPath) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                switch phase {
                case .configure: configureView
                case .running: runningView
                case .done: doneView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 540, height: 620)
        .onAppear(perform: loadDefaults)
    }

    private var header: some View {
        HStack(spacing: 10) {
            PsBadge()
            Text("Export JPEG mit Photoshop").font(.headline)
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    // MARK: Configure

    private var configureView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !photoshopAvailable { psWarning }

                    section("Bilder") {
                        Picker("Auswahl", selection: $source) {
                            Text("Aktuelles Bild").tag(ExportImageSource.current)
                            Text("Ausgewählte Bilder").tag(ExportImageSource.selected)
                            Text("Alle markierten Bilder").tag(ExportImageSource.allMarked)
                            Text("Alle sichtbaren Bilder").tag(ExportImageSource.filtered)
                            Divider()
                            ForEach(1...9, id: \.self) { m in
                                Text("Nur \(settings.markName(m)) (\(m))").tag(ExportImageSource.mark(m))
                            }
                        }
                        Toggle("Bei RAW+JPG das JPG statt RAW verwenden", isOn: $useJpgInstead)
                        Text("\(selectedGroups.count) Bilder werden exportiert.")
                            .font(.callout).foregroundStyle(.secondary)
                    }

                    section("Preset") {
                        HStack {
                            Text(presetURL?.lastPathComponent ?? "Kein Preset (nur Smart Exposure)")
                                .foregroundStyle(presetURL == nil ? .secondary : .primary).lineLimit(1)
                            Spacer()
                            if presetURL != nil { Button("Entfernen") { presetURL = nil } }
                            Button("Preset auswählen…") { choosePreset() }
                        }
                        if !settings.recentPresets.isEmpty {
                            Menu("Zuletzt verwendet") {
                                ForEach(settings.recentPresets, id: \.self) { p in
                                    Button((p as NSString).lastPathComponent) { presetURL = URL(fileURLWithPath: p) }
                                }
                            }.menuStyle(.borderlessButton).fixedSize()
                        }
                    }

                    section("Smart Exposure") {
                        Picker("Stärke", selection: $strength) { ForEach(SmartExposure.allCases) { Text($0.label).tag($0) } }
                        if strength != .off {
                            Picker("Maximale Helligkeitskorrektur", selection: $maxEV) { ForEach(SmartExposureEV.allCases) { Text($0.label).tag($0) } }
                            Toggle("Highlights schützen", isOn: $protectHi)
                            Toggle("Schatten schützen", isOn: $protectLo)
                            Toggle("Absichtlich dunkle/helle Bilder respektieren", isOn: $respectIntent)
                            HStack {
                                Button(analyzing ? "Analysiere…" : "Belichtung analysieren") { analyze() }.disabled(analyzing)
                                Spacer()
                            }
                            if !results.isEmpty { correctionTable }
                        }
                        Text("Analysiert jedes Bild lokal über Histogramm/Helligkeit. Keine Cloud, keine AI, kein Internet.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    section("JPEG") {
                        Picker("Qualität", selection: $quality) { ForEach(JPEGQuality.allCases) { Text($0.label).tag($0) } }
                        Picker("Farbraum", selection: $colorSpace) { ForEach(ColorSpaceChoice.allCases) { Text($0.label).tag($0) } }
                        Picker("Grösse", selection: $exportSize) { ForEach(ExportSizeChoice.allCases) { Text($0.label).tag($0) } }
                        if exportSize == .custom {
                            HStack { Text("Lange Kante"); TextField("px", value: $customEdge, format: .number).frame(width: 80); Text("px") }
                        }
                        Picker("Nachschärfen", selection: $sharpen) { ForEach(SharpenChoice.allCases) { Text($0.label).tag($0) } }
                    }

                    section("Ziel") {
                        HStack {
                            Text(targetURL?.path ?? "Kein Zielordner gewählt")
                                .foregroundStyle(targetURL == nil ? .secondary : .primary).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button("Zielordner…") { chooseTarget() }
                        }
                        Picker("Ordnerstruktur", selection: $folderStructure) { ForEach(ExportFolderStructure.allCases) { Text($0.label).tag($0) } }
                        Picker("Bei Dateikonflikt", selection: $conflict) { ForEach(ConflictMode.allCases) { Text($0.label).tag($0) } }
                    }
                }
                .padding(20)
            }
            Divider()
            footer
        }
    }

    private var psWarning: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Photoshop wurde nicht gefunden.").font(.callout.weight(.medium))
                Text("Bitte installiere Photoshop oder wähle die App in den Einstellungen aus.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }

    private var correctionTable: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(results.prefix(60)) { r in
                HStack {
                    Text(r.fileName).font(.caption.monospaced()).lineLimit(1)
                    Spacer()
                    Text(r.evLabel).font(.caption.monospacedDigit())
                        .foregroundStyle(abs(r.clampedEV) < 0.02 ? .secondary : .primary)
                }
            }
            if results.count > 60 { Text("… und \(results.count - 60) weitere").font(.caption2).foregroundStyle(.tertiary) }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .quaternaryLabelColor).opacity(0.25)))
    }

    private var footer: some View {
        HStack {
            Button("Abbrechen") { dismiss() }
            Spacer()
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
            Button("Export starten") { startExport() }
                .buttonStyle(.borderedProminent)
                .disabled(!canExport)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .confirmationDialog("Vorhandene Dateien überschreiben?", isPresented: $confirmOverwrite) {
            Button("Überschreiben", role: .destructive) { runExport() }
            Button("Abbrechen", role: .cancel) {}
        } message: { Text("Gleichnamige JPEGs im Zielordner werden ersetzt.") }
    }

    private var canExport: Bool {
        photoshopAvailable && !selectedGroups.isEmpty && targetURL != nil
    }

    // MARK: Running

    private var runningView: some View {
        VStack(spacing: 18) {
            Spacer()
            ProgressView(value: total > 0 ? Double(done) : 0, total: Double(max(total, 1)))
                .frame(width: 320)
            Text(total > 0 ? "Exportiere \(min(done + 1, total)) von \(total)…" : "Vorbereiten…")
                .font(.headline)
            Text(stage.rawValue).font(.callout).foregroundStyle(.secondary)
            if !currentName.isEmpty { Text(currentName).font(.caption.monospaced()).foregroundStyle(.tertiary) }
            Text("Photoshop wird als lokale Rendering-Engine verwendet. RAW-Dateien bleiben unverändert.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
            Spacer()
            Button("Export abbrechen") { cancelToken.cancel() }
            .padding(.bottom, 16)
        }
        .padding(20)
    }

    // MARK: Done

    private var doneView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 46)).foregroundStyle(failures.isEmpty ? .green : .orange)
            Text("\(successCount) JPEGs exportiert").font(.title3.weight(.semibold))
            Text("\(failures.count) Fehler").foregroundStyle(.secondary)
            if !failures.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(failures) { f in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(f.fileName).font(.caption.weight(.medium))
                                Text(f.message).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }.padding(10)
                }
                .frame(maxHeight: 160)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .quaternaryLabelColor).opacity(0.25)))
            }
            if let tempWarning { Text(tempWarning).font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center) }
            Spacer()
            HStack {
                if let t = targetURL { Button("Im Finder anzeigen") { app.revealFolder(t) } }
                Spacer()
                Button("Fertig") { dismiss() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }

    // MARK: Sections helper

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }

    // MARK: Actions

    private func loadDefaults() {
        strength = settings.smartExposure
        maxEV = settings.smartExposureMax
        protectHi = settings.protectHighlights
        protectLo = settings.protectShadows
        respectIntent = settings.respectIntentional
        quality = settings.jpegQuality
        colorSpace = settings.colorSpace
        exportSize = settings.exportSize
        customEdge = settings.customLongEdge
        sharpen = settings.sharpening
        folderStructure = settings.psFolderStructure
        conflict = settings.psConflict
        if let p = settings.recentPresets.first, FileManager.default.fileExists(atPath: p) { presetURL = URL(fileURLWithPath: p) }
        if !settings.lastPsExportTarget.isEmpty {
            let u = URL(fileURLWithPath: settings.lastPsExportTarget)
            if FileManager.default.fileExists(atPath: u.path) { targetURL = u }
        }
        if app.currentGroup != nil && app.groups(for: .allMarked).isEmpty { source = .selected }
    }

    private var analyzerConfig: SmartExposureAnalyzer.Config {
        .init(strength: strength, maxEV: maxEV.ev, protectHighlights: protectHi, protectShadows: protectLo, respectIntentional: respectIntent)
    }

    private func analyze() {
        analyzing = true
        let groups = selectedGroups
        let cfg = analyzerConfig
        Task.detached {
            let res = groups.map { SmartExposureAnalyzer.analyze(url: $0.previewURL, config: cfg) }
            await MainActor.run { results = res; analyzing = false }
        }
    }

    private func choosePreset() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowedFileTypes = ["xmp"]
        if panel.runModal() == .OK, let url = panel.url {
            presetURL = url
            settings.rememberRecentPreset(url.path)
        }
    }

    private func chooseTarget() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { targetURL = url }
    }

    private func startExport() {
        errorMessage = nil
        guard photoshopAvailable else { errorMessage = "Photoshop nicht gefunden."; return }
        guard !selectedGroups.isEmpty else { errorMessage = "Keine Bilder für den Export gefunden."; return }
        guard targetURL != nil else { errorMessage = "Bitte wähle einen Zielordner aus."; return }
        if conflict == .overwrite { confirmOverwrite = true } else { runExport() }
    }

    private func runExport() {
        guard let target = targetURL else { return }
        settings.lastPsExportTarget = target.path
        if let p = presetURL { settings.rememberRecentPreset(p.path) }

        let groups = selectedGroups
        let cfg = analyzerConfig
        let existing = Dictionary(uniqueKeysWithValues: results.map { ($0.fileURL.path, $0.clampedEV) })

        let items: [PhotoshopExportItem] = groups.map { g in
            let raw = useJpgInstead ? (g.files.first { ["jpg","jpeg"].contains($0.pathExtension.lowercased()) } ?? app.rawURL(for: g)) : app.rawURL(for: g)
            var ev = 0.0
            if strength != .off {
                ev = existing[g.previewURL.path] ?? SmartExposureAnalyzer.analyze(url: g.previewURL, config: cfg).clampedEV
            }
            return PhotoshopExportItem(group: g, rawURL: raw, evDelta: ev)
        }

        let longEdge = exportSize.longEdge(custom: Int(customEdge)) ?? 0
        let config = PhotoshopExportService.Config(
            presetURL: presetURL, jpegQualityPS: qualityPS, colorProfile: colorSpace.psProfile,
            longEdge: longEdge, sharpenAmount: sharpen.amount, sharpenRadius: sharpen.radius,
            targetRoot: target, folderStructure: folderStructure, sourceRoot: app.rootURL,
            conflict: conflict, deleteTemp: settings.deleteTempFiles,
            closePhotoshop: settings.closePhotoshopAfter, saveLog: settings.saveExportLog,
            photoshopPath: settings.photoshopPath)

        phase = .running
        total = items.count; done = 0; stage = .preparing

        Task {
            let outcome = await PhotoshopExportService.export(
                items: items, config: config,
                progress: { d, t, name, st in
                    Task { @MainActor in done = max(0, d - 1); total = t; currentName = name; stage = st }
                },
                isCancelled: { cancelToken.isCancelled })
            await MainActor.run {
                successCount = outcome.success
                failures = outcome.failures
                tempWarning = outcome.tempWarning
                phase = .done
            }
        }
    }

    private var qualityPS: Int {
        switch quality { case .q80: return 10; case .q90: return 11; case .q100: return 12 }
    }
}
