import SwiftUI
import AppKit

/// Clean, card-based configuration dialog for the Lightroom JPEG export, with a
/// per-image crop/rotate step (batch-capable) before rendering.
struct ExportWizard: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    enum Phase { case configure, cropping, running, done }
    @State private var phase: Phase = .configure

    // Step 1 – images
    enum Scope: Hashable { case current, selected, allMarked, filtered, tags }
    @State private var scope: Scope = .selected
    @State private var selectedTags: Set<Int> = []
    @State private var useJpgInstead = false
    // Step 2 – preset
    @State private var presetURL: URL?
    // Exposure is now purely manual, set per image in the crop step.
    // Step 4 – jpeg
    @State private var quality: Double = 100
    @State private var colorSpace: ColorSpaceChoice = .sRGB
    @State private var exportSize: ExportSizeChoice = .original
    @State private var customEdge: Double = 4000
    // Step 5 – target
    @State private var targetURL: URL?
    @State private var conflict: ConflictMode = .rename
    // crop — edits live centrally in AppState so the standalone editor and the
    // export crop step share one source of truth.
    @State private var cropIndex = 0
    @State private var editorTab: EditorTab = .crop
    // running / result
    @State private var done = 0
    @State private var total = 0
    @State private var currentName = ""
    @State private var stage: ExportStage = .preparing
    @State private var successCount = 0
    @State private var attempted = 0
    @State private var failures: [ExportFailure] = []
    @State private var lastItems: [ExportItem] = []   // for "retry failed"
    @State private var tempWarning: String?
    @State private var errorMessage: String?
    @State private var confirmOverwrite = false
    private let cancelToken = CancellationToken()

    /// Fits the wizard to the screen — big by default, but never larger than the visible
    /// screen (so it works on small displays too). Computed ONCE at first appearance and
    /// held in @State, so switching focus in/out of the app (which changes NSScreen.main)
    /// never resizes the popup on a later re-render.
    @State private var wizardSize: CGSize = ExportWizard.fittedSize()

    private static func fittedSize() -> CGSize {
        let vis = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1000, height: 800)
        return CGSize(width: min(820, vis.width * 0.92), height: min(920, vis.height * 0.92))
    }

    private var groupsToExport: [PhotoGroup] {
        switch scope {
        case .current: return app.currentGroup.map { [$0] } ?? []
        case .selected: return app.selectedGroups
        case .allMarked: return app.groups.filter { $0.mark != 0 }
        case .filtered: return app.filteredGroups
        case .tags: return app.groups.filter { selectedTags.contains($0.mark) }
        }
    }
    private var engineAvailable: Bool {
        LightroomExportService.isAvailable(preferredPath: settings.lightroomPath)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                switch phase {
                case .configure: configureView
                case .cropping: croppingView
                case .running: runningView
                case .done: doneView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: wizardSize.width, height: wizardSize.height)
        .onAppear(perform: loadDefaults)
        .onDisappear {
            app.saveEditsNow()   // persist any crop-step edits
            Task { await LightroomPreviewService.shared.clearCache() }   // previews are session-scoped
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            lrBadge
            Text("Export JPEG mit Lightroom Classic").font(.title3.weight(.semibold))
            Spacer()
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
    }

    private var lrBadge: some View {
        Text("Lr")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.10, green: 0.45, blue: 0.95)))
    }

    // MARK: Configure

    private var configureView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    if !engineAvailable { engineWarning }

                    card("Bilder") {
                        Picker("Auswahl", selection: $scope) {
                            Text("Aktuelles Bild").tag(Scope.current)
                            Text("Ausgewählte Bilder").tag(Scope.selected)
                            Text("Alle markierten Bilder").tag(Scope.allMarked)
                            Text("Alle sichtbaren Bilder").tag(Scope.filtered)
                        }
                        .onChange(of: scope) { _, new in if new != .tags { selectedTags.removeAll() } }
                        if !availableTags.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Nach Tags").font(.callout).foregroundStyle(.secondary)
                                tagChips
                            }
                        }
                        Toggle("Bei RAW+JPG das JPG statt RAW verwenden", isOn: $useJpgInstead)
                        Text("\(groupsToExport.count) Bilder werden exportiert.")
                            .font(.callout).foregroundStyle(.secondary)
                    }

                    card("Preset") {
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

                    card("JPEG") {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack { Text("Qualität"); Spacer(); Text("\(Int(quality))%").foregroundStyle(.secondary).monospacedDigit() }
                            Slider(value: $quality, in: 10...100, step: 10)
                        }
                        Picker("Farbraum", selection: $colorSpace) { ForEach(ColorSpaceChoice.allCases) { Text($0.label).tag($0) } }
                        Picker("Grösse", selection: $exportSize) { ForEach(ExportSizeChoice.allCases) { Text($0.label).tag($0) } }
                        if exportSize == .custom {
                            HStack { Text("Lange Kante"); TextField("px", value: $customEdge, format: .number).frame(width: 80); Text("px") }
                        }
                    }

                    card("Ziel") {
                        HStack {
                            Text(targetURL?.path ?? "Kein Zielordner gewählt")
                                .foregroundStyle(targetURL == nil ? .secondary : .primary).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button("Zielordner…") { chooseTarget() }
                        }
                        Text("Die Bilder werden direkt in den gewählten Ordner exportiert (keine Unterordner).")
                            .font(.caption).foregroundStyle(.secondary)
                        Picker("Bei Dateikonflikt", selection: $conflict) { ForEach(ConflictMode.allCases) { Text($0.label).tag($0) } }
                    }
                }
                .padding(20)
            }
            Divider()
            HStack {
                Button("Abbrechen") { dismiss() }
                Spacer()
                if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
                Button("Ohne Bearbeitung exportieren") { startExport(skipCrop: true) }
                    .disabled(!canExport)
                Button("Zuschneiden & Belichten →") { startCropping() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canExport)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .confirmationDialog("Vorhandene Dateien überschreiben?", isPresented: $confirmOverwrite) {
                Button("Überschreiben", role: .destructive) { runExport() }
                Button("Abbrechen", role: .cancel) {}
            } message: { Text("Gleichnamige JPEGs im Zielordner werden ersetzt.") }
        }
    }

    private var availableTags: [Int] { (1...9).filter { (app.markCounts[$0] ?? 0) > 0 } }

    private var tagChips: some View {
        HStack(spacing: 6) {
            ForEach(availableTags, id: \.self) { m in
                let on = selectedTags.contains(m)
                Button {
                    scope = .tags
                    if on { selectedTags.remove(m) } else { selectedTags.insert(m) }
                    if selectedTags.isEmpty { scope = .allMarked }
                } label: {
                    HStack(spacing: 5) {
                        Circle().fill(settings.markColor(m)).frame(width: 10, height: 10)
                        Text("\(m)").font(.callout.monospacedDigit())
                        Text("\(app.markCounts[m] ?? 0)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Capsule().fill(on ? settings.markColor(m).opacity(0.22) : Color(nsColor: .quaternaryLabelColor).opacity(0.4)))
                    .overlay(Capsule().strokeBorder(on ? settings.markColor(m) : .clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var engineWarning: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Lightroom Classic wurde nicht gefunden.").font(.callout.weight(.medium))
                Text("Bitte installiere Lightroom Classic oder wähle die App in den Einstellungen aus.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.12)))
    }

    private func card(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private var canExport: Bool { engineAvailable && !groupsToExport.isEmpty && targetURL != nil }

    // MARK: Cropping

    private var croppingView: some View {
        let items = groupsToExport
        let group = items[min(cropIndex, items.count - 1)]
        return VStack(spacing: 14) {
            HStack {
                Text("Bild vorbereiten — \(cropIndex + 1) von \(items.count)").font(.headline)
                Spacer()
                Text(group.displayName).font(.callout.monospaced()).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, 20).padding(.top, 16)

            CropEditorView(previewURL: group.previewURL, edit: editBinding(for: group),
                           rawURL: exportSource(for: group), presetURL: presetURL,
                           lightroomPath: settings.lightroomPath, editorTab: $editorTab)
                .padding(.horizontal, 20)

            Divider()
            HStack(spacing: 10) {
                Button("Alle überspringen & exportieren") { runExport() }
                Spacer()
                Button("Zurück") { stepBack(items.count) }
                    .disabled(editorTab == .crop && cropIndex == 0)
                Button("Überspringen") { skipImage(items.count) }
                // Export is only reachable from the Develop tab: „Weiter" on the crop
                // tab goes to Develop first, then „Fertig & Export" on the last image.
                Button(exportReady(items.count) ? "Fertig & Export" : "Weiter →") { stepForward(items.count) }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20).padding(.bottom, 14)
        }
    }

    /// The file that will be rendered for this photo (RAW, or its JPG sibling when
    /// "use JPG instead" is on) — used for both the export and the preset preview.
    private func exportSource(for group: PhotoGroup) -> URL {
        if useJpgInstead, let jpg = group.files.first(where: { ["jpg","jpeg"].contains($0.pathExtension.lowercased()) }) {
            return jpg
        }
        return app.rawURL(for: group)
    }

    /// Warms the Lightroom preset previews for the whole set in the background (serial,
    /// current-image first) so navigating the crop step is mostly instant.
    private func prewarmPresetPreviews() {
        guard engineAvailable, let presetURL else { return }
        let sources = groupsToExport.map { exportSource(for: $0) }
        let lr = settings.lightroomPath
        Task.detached(priority: .utility) {
            for src in sources {
                _ = await LightroomPreviewService.shared.preview(
                    rawURL: src, presetURL: presetURL, maxEdge: 2048, lightroomPath: lr)
            }
        }
    }

    private func editBinding(for group: PhotoGroup) -> Binding<ImageEdit> {
        Binding(get: { app.edits[group.id] ?? ImageEdit() },
                set: { app.edits[group.id] = $0.isIdentity ? nil : $0 })
    }

    /// Export is only offered on the Develop tab of the last image.
    private func exportReady(_ count: Int) -> Bool { editorTab == .develop && cropIndex >= count - 1 }

    private func stepForward(_ count: Int) {
        if editorTab == .crop {
            withAnimation(.easeInOut(duration: 0.15)) { editorTab = .develop }   // crop → develop, no export here
        } else if cropIndex >= count - 1 {
            runExport()
        } else {
            cropIndex += 1; editorTab = .crop
        }
    }

    private func stepBack(_ count: Int) {
        if editorTab == .develop { withAnimation(.easeInOut(duration: 0.15)) { editorTab = .crop } }
        else if cropIndex > 0 { cropIndex -= 1 }   // previous image, on its crop tab
    }

    private func skipImage(_ count: Int) {
        if cropIndex >= count - 1 { runExport() } else { cropIndex += 1; editorTab = .crop }
    }

    // MARK: Running

    private var runningView: some View {
        VStack(spacing: 18) {
            Spacer()
            ProgressView(value: total > 0 ? Double(done) : 0, total: Double(max(total, 1))).frame(width: 340)
            Text(total > 0 ? "Exportiere \(min(done + 1, total)) von \(total)…" : "Vorbereiten…").font(.headline)
            Text(stage == .rendering ? "Rendern via Lightroom Classic" : stage.rawValue)
                .font(.callout).foregroundStyle(.secondary)
            if !currentName.isEmpty { Text(currentName).font(.caption.monospaced()).foregroundStyle(.tertiary) }
            Text("Lightroom Classic wird als lokale Rendering-Engine verwendet. RAW-Dateien bleiben unverändert.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
            Spacer()
            Button("Export abbrechen") { cancelToken.cancel() }.padding(.bottom, 16)
        }
        .padding(20)
    }

    // MARK: Done

    private var doneView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 48)).foregroundStyle(failures.isEmpty ? .green : .orange)
            Text(resultTitle).font(.title3.weight(.semibold))
            if !failures.isEmpty {
                Text("\(failures.count) Fehler").foregroundStyle(.secondary)
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
                .frame(maxHeight: 180)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .quaternaryLabelColor).opacity(0.25)))
            }
            if let tempWarning { Text(tempWarning).font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center) }
            Spacer()
            HStack {
                if let t = targetURL { Button("Im Finder anzeigen") { app.revealFolder(t) } }
                if !failures.isEmpty {
                    Button("Fehlgeschlagene erneut (\(failures.count))") { retryFailed() }
                }
                Spacer()
                Button("Fertig") { dismiss() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }

    private var resultTitle: String {
        if failures.isEmpty { return "\(successCount) JPEGs erfolgreich exportiert" }
        return "\(successCount) von \(attempted) Bildern erfolgreich exportiert"
    }

    // MARK: Actions

    private func loadDefaults() {
        quality = settings.jpegQualityPercent
        colorSpace = settings.colorSpace
        exportSize = settings.exportSize
        customEdge = settings.customLongEdge
        conflict = settings.exportConflict
        // Default preset: the explicit "Standard-Preset" (Einstellungen) wins, else the most recent.
        let defaultPreset = settings.presetPath.isEmpty ? settings.recentPresets.first : settings.presetPath
        if let p = defaultPreset, FileManager.default.fileExists(atPath: p) { presetURL = URL(fileURLWithPath: p) }
        if !settings.lastExportTarget.isEmpty {
            let u = URL(fileURLWithPath: settings.lastExportTarget)
            if FileManager.default.fileExists(atPath: u.path) { targetURL = u }
        }
        if app.selectedGroups.isEmpty { scope = app.groups.contains(where: { $0.mark != 0 }) ? .allMarked : .filtered }
    }

    private func choosePreset() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowedFileTypes = ["xmp"]
        if panel.runModal() == .OK, let url = panel.url {
            presetURL = url; settings.rememberRecentPreset(url.path)
        }
    }

    private func chooseTarget() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { targetURL = url }
    }

    private func startCropping() {
        errorMessage = nil
        guard validate() else { return }
        cropIndex = 0
        editorTab = .crop
        phase = .cropping
        prewarmPresetPreviews()   // background Lightroom renders so navigation is instant
    }

    private func startExport(skipCrop: Bool) {
        errorMessage = nil
        guard validate() else { return }
        if conflict == .overwrite { confirmOverwrite = true } else { runExport() }
    }

    private func validate() -> Bool {
        guard engineAvailable else { errorMessage = "Lightroom Classic nicht gefunden."; return false }
        guard !groupsToExport.isEmpty else { errorMessage = "Keine Bilder für den Export gefunden."; return false }
        guard targetURL != nil else { errorMessage = "Bitte wähle einen Zielordner aus."; return false }
        return true
    }

    private func runExport() {
        guard let target = targetURL else { return }
        settings.lastExportTarget = target.path
        if let p = presetURL { settings.rememberRecentPreset(p.path) }

        let groups = groupsToExport
        let items: [ExportItem] = groups.map { g in
            let raw = exportSource(for: g)
            let edit = app.edits[g.id] ?? ImageEdit()
            // Manual, per-image exposure set in the crop step (written 1:1 as Exposure2012).
            return ExportItem(group: g, rawURL: raw, evDelta: edit.exposure, edit: edit)
        }
        lastItems = items
        performExport(items)
    }

    /// Retry only the items that failed in the last run.
    private func retryFailed() {
        let failedNames = Set(failures.map { $0.fileName })
        let retry = lastItems.filter { failedNames.contains($0.rawURL.lastPathComponent) }
        guard !retry.isEmpty else { return }
        performExport(retry)
    }

    private func performExport(_ items: [ExportItem]) {
        guard let target = targetURL, !items.isEmpty else { return }
        let longEdge = exportSize.longEdge(custom: Int(customEdge)) ?? 0

        cancelToken.reset()
        phase = .running
        total = items.count; done = 0; attempted = items.count; stage = .preparing
        failures = []; tempWarning = nil

        let progressCB: (Int, Int, String, ExportStage) -> Void = { d, t, name, st in
            Task { @MainActor in done = max(0, d - 1); total = t; currentName = name; stage = st }
        }

        let lrConfig = LightroomExportService.Config(
            presetURL: presetURL, jpegQuality01: max(0.1, min(1.0, quality / 100.0)),
            colorSpace: colorSpace.lrColorSpace, longEdge: longEdge,
            targetRoot: target, folderStructure: .single, sourceRoot: app.rootURL,
            conflict: conflict, deleteTemp: settings.deleteTempFiles,
            lightroomPath: settings.lightroomPath,
            autoConfirmDialogs: settings.autoConfirmLightroomDialogs,
            denoise: 0,
            denoiseUseEnhance: false)
        Task {
            let outcome = await LightroomExportService.export(
                items: items, config: lrConfig, progress: progressCB,
                isCancelled: { cancelToken.isCancelled })
            await MainActor.run {
                successCount = outcome.success
                failures = outcome.failures
                tempWarning = outcome.tempWarning
                phase = .done
            }
        }
    }
}
