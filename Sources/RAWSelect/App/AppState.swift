import SwiftUI
import AppKit
import Combine

@MainActor
final class AppState: ObservableObject {

    let settings = AppSettings.shared
    private var cancellables = Set<AnyCancellable>()
    private var lastSortSig = ""

    // MARK: Published state
    @Published var volumes: [VolumeInfo] = []
    @Published var rootURL: URL?
    @Published var browseRoot: URL?      // root of the sidebar folder navigator
    @Published var groups: [PhotoGroup] = []
    @Published var tagFilter = TagFilter() { didSet { reconcileSelection() } }

    /// All selected photos (multi-select). `currentID` is the "active" one shown
    /// in the loupe and used as the anchor for keyboard navigation.
    @Published var selectedIDs: Set<String> = []
    @Published var currentID: String? {
        didSet {
            prefetchAroundCurrent()
            if oldValue != currentID { zoom.sliderActive = false }   // leaving a photo exits zoom mode
        }
    }
    private var anchorID: String?

    @Published var viewMode: ViewMode = .grid { didSet { if viewMode == .loupe { prefetchAroundCurrent() } else { focusMode = false } } }

    /// Distraction-free viewing: hides filmstrip, filter bar and status bar.
    @Published var focusMode = false

    /// Runtime toggle for the EXIF overlay (default from settings.metadataPanel).
    @Published var showInfo: Bool = AppSettings.shared.metadataPanel

    @Published var isScanning = false
    @Published var statusMessage = "Kein Ordner geöffnet."

    @Published var operation: OperationState?
    @Published var pendingMoveTarget: URL?
    @Published var showExportWizard = false

    /// Transient confirmation/error banner shown at the bottom of the window.
    @Published var toast: Toast?
    /// Keyboard-shortcut cheat sheet (toggled with `?`).
    @Published var showShortcuts = false

    /// Pan/zoom state for the loupe, shared with `ZoomableImageView`.
    let zoom = ZoomController()

    enum ViewMode: String, CaseIterable { case grid, loupe }

    struct OperationState {
        var title: String
        var completed: Int
        var total: Int
    }

    struct Toast: Identifiable, Equatable {
        enum Kind: Equatable { case success, error, info }
        let id = UUID()
        var message: String
        var kind: Kind = .success
    }

    /// Shows a transient toast that auto-dismisses (errors linger a bit longer).
    func showToast(_ message: String, kind: Toast.Kind = .success) {
        let t = Toast(message: message, kind: kind)
        toast = t
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: kind == .error ? 4_500_000_000 : 2_600_000_000)
            if self.toast?.id == t.id { self.toast = nil }
        }
    }

    // MARK: Private
    private let volumeScanner = VolumeScanner()
    private var scanTask: Task<Void, Never>?
    private var scanCancelToken: CancellationToken?
    private var cancelToken: CancellationToken?
    private var keyMonitor: Any?
    private var identity: FolderIdentity?

    // MARK: Derived
    var filteredGroups: [PhotoGroup] { groups.filter { tagFilter.matches($0) } }

    var currentGroup: PhotoGroup? {
        guard let id = currentID else { return nil }
        return groups.first { $0.id == id }
    }

    var selectedGroups: [PhotoGroup] { groups.filter { selectedIDs.contains($0.id) } }
    var selectionCount: Int { selectedIDs.count }

    /// Move is only allowed from an internal disk, never from an SD card/external.
    var sourceIsExternal: Bool { rootURL?.isOnExternalVolume ?? false }

    var markCounts: [Int: Int] {
        var counts: [Int: Int] = [:]
        for g in groups where g.mark != 0 { counts[g.mark, default: 0] += 1 }
        return counts
    }
    var unmarkedCount: Int { groups.filter { !$0.hasState }.count }
    var markedCount: Int { groups.filter { $0.mark != 0 }.count }

    // MARK: Lifecycle
    func start() {
        refreshVolumes()
        volumeScanner.startWatching { [weak self] in self?.refreshVolumes() }
        installKeyMonitor()
        lastSortSig = sortSignature
        ThumbnailLoader.shared.setMaxConcurrent(Int(settings.maxParallelJobs))
        // React to settings changes that affect already-loaded content.
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.settingsChanged() }
            .store(in: &cancellables)
    }

    private var sortSignature: String { "\(settings.sortField.rawValue)|\(settings.sortReversed)" }

    private func settingsChanged() {
        if sortSignature != lastSortSig {
            lastSortSig = sortSignature
            applySort()
        }
        ThumbnailLoader.shared.setMaxConcurrent(Int(settings.maxParallelJobs))
    }

    func refreshVolumes() { volumes = VolumeScanner.externalVolumes() }

    /// Show a volume/folder in the sidebar navigator WITHOUT scanning it. Images
    /// are only loaded when the user double-clicks a (sub)folder.
    func browse(_ url: URL) {
        scanCancelToken?.cancel()
        scanTask?.cancel()
        browseRoot = url
        rootURL = nil
        groups = []
        selectedIDs = []
        currentID = nil
        isScanning = false
        statusMessage = "Ordner in der Seitenleiste doppelklicken, um die Bilder zu laden."
    }

    /// Abort an in-progress scan (large folders / slow network volumes).
    func cancelScan() {
        guard isScanning else { return }
        scanCancelToken?.cancel()
        scanCancelToken?.cancel()
        scanTask?.cancel()
        isScanning = false
        statusMessage = "Scan abgebrochen."
    }

    // MARK: Opening / scanning
    func openFolderDialog() {
        if let url = FinderService.chooseFolder(title: "Ordner oder SD-Karte öffnen") { open(url) }
    }

    func open(_ url: URL, setBrowseRoot: Bool = true) {
        scanCancelToken?.cancel()
        scanTask?.cancel()
        rootURL = url
        tagFilter.reset()  // opening a folder always shows all images found in it
        if setBrowseRoot {
            if url.isOnExternalVolume, let vol = try? url.resourceValues(forKeys: [.volumeURLKey]).volume {
                browseRoot = vol
            } else {
                browseRoot = url
            }
        }
        groups = []
        selectedIDs = []
        currentID = nil
        anchorID = nil
        isScanning = true
        statusMessage = "Scanne \(url.lastPathComponent) …"

        let identity = FolderIdentity(root: url)
        self.identity = identity
        let savedMarks = SessionStore.load(identityID: identity.id)

        // Capture scan-relevant settings on the main actor.
        let allowed = Set(settings.enabledTypes.map { $0.lowercased() })
        let recursive = settings.recursiveScan
        let groupPairs = settings.groupRawJpg
        let ignoreHidden = settings.ignoreHidden
        let cameraOnly = settings.cameraFoldersOnly

        let token = CancellationToken()
        scanCancelToken = token
        scanTask = Task {
            let found: [PhotoGroup] = await Task.detached(priority: .userInitiated) {
                var groups = PhotoScanner.scan(root: url, allowedExtensions: allowed, recursive: recursive,
                                               groupPairs: groupPairs, ignoreHidden: ignoreHidden,
                                               cameraFoldersOnly: cameraOnly,
                                               isCancelled: { token.isCancelled })
                for i in groups.indices {
                    let key = identity.persistKey(directory: groups[i].directory, baseName: groups[i].baseName)
                    groups[i].persistKey = key
                    if let state = savedMarks[key] {
                        groups[i].mark = state.mark
                    }
                }
                return groups
            }.value

            if Task.isCancelled || token.isCancelled { self.isScanning = false; return }
            self.groups = found
            self.applySort()
            self.isScanning = false
            // Warm the tiny-thumbnail cache for every photo so the grid always has
            // at least a low-res image to show while scrolling (never a spinner).
            ThumbnailLoader.shared.warmTiny(found.map { $0.previewURL }, maxPixel: PreviewConfig.tinyMaxPixel)
            if let first = self.filteredGroups.first { self.selectSingle(first.id) }
            let markedNote = self.markedCount > 0 ? " (\(self.markedCount) bereits markiert)" : ""
            self.statusMessage = found.isEmpty
                ? "Keine Bilder gefunden."
                : "\(found.count) Bilder gefunden\(markedNote)."
        }
    }

    // MARK: Selection
    func selectSingle(_ id: String) {
        selectedIDs = [id]; currentID = id; anchorID = id
    }

    func toggleSelect(_ id: String) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
        currentID = id; anchorID = id
    }

    func selectRange(to id: String) {
        let list = filteredGroups.map { $0.id }
        guard let target = list.firstIndex(of: id) else { return }
        let anchor = anchorID ?? currentID ?? id
        let anchorIdx = list.firstIndex(of: anchor) ?? target
        let range = min(anchorIdx, target)...max(anchorIdx, target)
        selectedIDs = Set(range.map { list[$0] })
        currentID = id
    }

    func selectAllFiltered() {
        let list = filteredGroups
        selectedIDs = Set(list.map { $0.id })
        if currentID == nil { currentID = list.first?.id }
        anchorID = list.first?.id
        statusMessage = "\(selectedIDs.count) Bilder ausgewählt."
    }

    /// Handles a click coming from the grid/filmstrip with modifier keys.
    func click(_ id: String) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift) { selectRange(to: id) }
        else if flags.contains(.command) { toggleSelect(id) }
        else { selectSingle(id) }
    }

    private func step(by delta: Int, extend: Bool) {
        let list = filteredGroups
        guard !list.isEmpty else { return }
        let current = list.firstIndex { $0.id == currentID } ?? (delta > 0 ? -1 : 0)
        var next = current + delta
        if settings.wrapNavigation && !extend {
            next = (next % list.count + list.count) % list.count   // wrap around
        } else {
            next = min(max(next, 0), list.count - 1)
        }
        let id = list[next].id
        if extend { selectRange(to: id) } else { selectSingle(id) }
    }

    /// Warms the preview cache around the current photo so stepping through has no
    /// load time. Two tiers: a WIDE soft (instant-size) buffer so even fast scrubbing
    /// always finds a ready — if soft — frame, and a narrower sharp (HD) buffer for
    /// the immediate neighbours. Warms closest-first so the very next image is ready
    /// soonest.
    private func prefetchAroundCurrent() {
        guard viewMode == .loupe, settings.preloadPerfect, let id = currentID else { return }
        let list = filteredGroups
        let count = list.count
        guard let idx = list.firstIndex(where: { $0.id == id }), count > 1 else { return }
        let loader = ThumbnailLoader.shared
        let target = settings.perfectPixels
        let instantPixel = settings.instantPixels

        let sharpFwd = Int(settings.preloadForward)
        let sharpBack = Int(settings.preloadBackward)
        let softFwd = sharpFwd + 25          // much wider soft buffer (cheap to hold)
        let softBack = sharpBack + 12
        let maxOffset = max(softFwd, softBack)

        for d in 1...maxOffset {
            for dir in [1, -1] {             // forward first at each distance
                let i = idx + d * dir
                guard i >= 0, i < count else { continue }
                let softLimit = dir > 0 ? softFwd : softBack
                guard d <= softLimit else { continue }
                let url = list[i].previewURL
                loader.prefetch(for: url, maxPixel: instantPixel, fullQuality: false)
                let sharpLimit = dir > 0 ? sharpFwd : sharpBack
                if d <= sharpLimit {
                    let plan = loader.previewPlan(for: url, targetLongEdge: target)
                    loader.prefetch(for: url, maxPixel: plan.maxPixel, fullQuality: plan.fullQuality)
                }
            }
        }
    }

    private func reconcileSelection() {
        let ids = Set(filteredGroups.map { $0.id })
        selectedIDs.formIntersection(ids)
        if let id = currentID, ids.contains(id) { return }
        currentID = filteredGroups.first?.id
        if let c = currentID, selectedIDs.isEmpty { selectedIDs = [c]; anchorID = c }
    }

    // MARK: Rating / marking (applies to the whole selection)
    func setMark(_ mark: Int) {
        let before = currentID
        let single = selectedIDs.count <= 1
        mutateSelection({ $0.mark = mark }) { n in
            mark == 0
                ? (n == 1 ? "Markierung entfernt." : "Markierung von \(n) Bildern entfernt.")
                : (n == 1 ? "Markierung \(mark) gesetzt." : "Markierung \(mark) für \(n) Bilder gesetzt.")
        }
        // Auto-advance for fast culling (Settings → Markierungen).
        if settings.autoAdvance && mark != 0 && single && currentID == before {
            step(by: settings.advanceDirection == .next ? 1 : -1, extend: false)
        }
    }

    /// Applies `body` to every selected photo, persists, and keeps culling flowing
    /// by advancing to a neighbour if the photos left the current filter.
    // MARK: Mark undo (⌘Z)
    private var markUndoStack: [[String: Int]] = []

    private func pushUndo(_ ids: Set<String>) {
        let snap = Dictionary(uniqueKeysWithValues: groups.filter { ids.contains($0.id) }.map { ($0.id, $0.mark) })
        markUndoStack.append(snap)
        if markUndoStack.count > 50 { markUndoStack.removeFirst() }
    }

    func undoMark() {
        guard let snap = markUndoStack.popLast() else { return }
        for i in groups.indices { if let m = snap[groups[i].id] { groups[i].mark = m } }
        persistState()
        reconcileSelection()
        statusMessage = "Markierung rückgängig gemacht."
    }

    private func mutateSelection(_ body: (inout PhotoGroup) -> Void, status: (Int) -> String) {
        let targets = selectedIDs.isEmpty ? Set([currentID].compactMap { $0 }) : selectedIDs
        guard !targets.isEmpty else { return }

        let anchorPos = filteredGroups.firstIndex { $0.id == currentID }
        pushUndo(targets)
        for i in groups.indices where targets.contains(groups[i].id) { body(&groups[i]) }
        persistState()
        statusMessage = status(targets.count)

        let visible = Set(filteredGroups.map { $0.id })
        if currentID == nil || !visible.contains(currentID!) {
            let list = filteredGroups
            if list.isEmpty { selectedIDs = []; currentID = nil }
            else { selectSingle(list[min(anchorPos ?? 0, list.count - 1)].id) }
        } else {
            selectedIDs.formIntersection(visible)
            if selectedIDs.isEmpty, let c = currentID { selectedIDs = [c] }
        }
    }

    private func persistState() {
        guard let identity else { return }
        var states: [String: SessionStore.PhotoState] = [:]
        for g in groups where g.hasState {
            states[g.persistKey] = SessionStore.PhotoState(mark: g.mark)
        }
        SessionStore.save(identityID: identity.id, states: states)
    }

    // MARK: Sorting & view
    func applySort() {
        let field = settings.sortField
        groups.sort { a, b in
            switch field {
            case .filename: return a.id.localizedStandardCompare(b.id) == .orderedAscending
            case .captureDate:
                if a.fileDate != b.fileDate { return a.fileDate < b.fileDate }
                return a.id.localizedStandardCompare(b.id) == .orderedAscending
            case .mark:
                if a.mark != b.mark { return a.mark < b.mark }
                return a.id.localizedStandardCompare(b.id) == .orderedAscending
            }
        }
        if settings.sortReversed { groups.reverse() }
        reconcileSelection()
    }

    func toggleFullscreen() { NSApp.keyWindow?.toggleFullScreen(nil) }
    func toggleInfo() { showInfo.toggle() }

    // MARK: Finder
    func revealCurrent() {
        guard let g = currentGroup else { statusMessage = "Kein Bild ausgewählt."; return }
        FinderService.reveal(g.previewURL)
    }
    func revealFolder(_ url: URL) { FinderService.revealFolder(url) }

    // MARK: Export helpers
    /// Resolves an export image source to the matching photo groups.
    func groups(for source: ExportImageSource) -> [PhotoGroup] {
        switch source {
        case .current: return currentGroup.map { [$0] } ?? []
        case .selected: return selectedGroups
        case .allMarked: return groups.filter { $0.mark != 0 }
        case .mark(let n): return groups.filter { $0.mark == n }
        case .filtered: return filteredGroups
        }
    }

    /// File to develop for a group (RAW preferred).
    func rawURL(for group: PhotoGroup) -> URL {
        group.files.first { PhotoTypes.isRaw($0) } ?? group.previewURL
    }

    // MARK: Copy / Move (operate on the selection)
    func copySelection(includeSidecars: Bool) {
        let sel = selectedGroups
        guard !sel.isEmpty else { statusMessage = "Keine Bilder ausgewählt."; return }
        let what = includeSidecars ? "Bilder + XMP" : "nur Bilder"
        guard let target = FinderService.chooseDestination(title: "Ziel für \(sel.count) Bilder (\(what))") else { return }
        runOperation(.copy, target: target, groups: sel, includeSidecars: includeSidecars)
    }

    func requestMoveSelection() {
        let sel = selectedGroups
        guard !sel.isEmpty else { statusMessage = "Keine Bilder ausgewählt."; return }
        guard !sourceIsExternal else {
            statusMessage = "Verschieben ist von SD-Karten/externen Datenträgern deaktiviert – bitte kopieren."
            return
        }
        guard let target = FinderService.chooseDestination(title: "Ziel für \(sel.count) Bilder (Verschieben)") else { return }
        pendingMoveTarget = target
    }

    func confirmMove() {
        guard let target = pendingMoveTarget else { return }
        pendingMoveTarget = nil
        runOperation(.move, target: target, groups: selectedGroups, includeSidecars: true)
    }

    func cancelMove() { pendingMoveTarget = nil }
    func cancelOperation() { cancelToken?.cancel() }

    /// Extra warning required before overwriting existing files.
    private func confirmOverwrite() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Vorhandene Dateien überschreiben?"
        alert.informativeText = "Der Konfliktmodus steht auf „Überschreiben“. Gleichnamige Dateien im Zielordner werden ersetzt. Dies kann nicht rückgängig gemacht werden."
        alert.addButton(withTitle: "Überschreiben")
        alert.addButton(withTitle: "Abbrechen")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func runOperation(_ kind: FileOperationService.Kind, target: URL,
                              groups selection: [PhotoGroup], includeSidecars: Bool) {
        let useSubfolders = settings.exportSubfolders
        // In mark-based export mode, optionally skip unmarked photos.
        var snapshot = selection
        if useSubfolders && settings.ignoreUnmarked {
            snapshot = snapshot.filter { $0.mark != 0 }
        }
        guard !snapshot.isEmpty else { statusMessage = "Keine passenden Bilder für den Export."; return }

        let conflict = settings.conflictMode
        let rawJpgMode = settings.rawJpgExport
        if conflict == .overwrite && !confirmOverwrite() { return }

        let makeSubfolder: (PhotoGroup) -> String? = useSubfolders
            ? { [settings] g in settings.exportFolderName(for: g.mark) }
            : { _ in nil }

        let title = kind == .copy ? "Kopiere Bilder …" : "Verschiebe Bilder …"
        let token = CancellationToken()
        cancelToken = token
        operation = OperationState(title: title, completed: 0, total: 0)

        Task {
            do {
                let outcome = try await Task.detached(priority: .userInitiated) { [weak self] in
                    try FileOperationService.perform(
                        kind, groups: snapshot, targetRoot: target, includeSidecars: includeSidecars,
                        rawJpg: rawJpgMode, subfolder: makeSubfolder, conflict: conflict,
                        progress: { completed, total in
                            Task { @MainActor in
                                self?.operation?.completed = completed
                                self?.operation?.total = total
                            }
                        },
                        isCancelled: { token.isCancelled }
                    )
                }.value

                self.operation = nil
                let verb = kind == .copy ? "kopiert" : "verschoben"

                if kind == .move {
                    // Only remove groups whose files ALL moved (partial moves stay).
                    let moved = outcome.movedGroupIDs
                    self.groups.removeAll { moved.contains($0.id) }
                    self.selectedIDs.subtract(moved)
                    self.persistState()
                    self.reconcileSelection()
                }

                if outcome.failures.isEmpty {
                    self.statusMessage = "\(outcome.photos) Bilder (\(outcome.files) Dateien) \(verb)."
                    self.showToast("\(outcome.photos) Bilder \(verb).", kind: .success)
                } else {
                    self.statusMessage = "\(outcome.files) Dateien \(verb) – \(outcome.failures.count) fehlgeschlagen."
                    self.showToast("\(outcome.failures.count) Datei(en) nicht \(verb) – Rest ok.", kind: .error)
                }
                if self.settings.revealAfterExport { FinderService.revealFolder(target) }
            } catch {
                self.operation = nil
                self.statusMessage = "Fehler: \(error.localizedDescription)"
                self.showToast("Fehler: \(error.localizedDescription)", kind: .error)
            }
        }
    }

    // MARK: Keyboard
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        // ⌘Z undoes the last marking — only in the browser (not Settings/sheets/text fields).
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "z",
           !showExportWizard, NSApp.keyWindow === NSApp.mainWindow,
           !(NSApp.keyWindow?.firstResponder is NSText) {
            undoMark(); return true
        }
        if event.modifierFlags.contains(.command) { return false }   // leave ⌘-shortcuts to menus
        if NSApp.keyWindow?.firstResponder is NSText { return false }

        // While the shortcut cheat sheet is up, only Esc (close) is handled here.
        if showShortcuts {
            if event.keyCode == 53 { showShortcuts = false; return true }
            return false
        }

        // CRITICAL: only the browser window (no export sheet / Settings window
        // open) may react to ANY culling/navigation key. Otherwise digit keys
        // would silently re-mark the background selection while a modal is up.
        guard !showExportWizard, NSApp.keyWindow === NSApp.mainWindow else { return false }

        let extend = event.modifierFlags.contains(.shift)

        switch event.keyCode {
        case 123: step(by: -1, extend: extend); return true   // ←
        case 124: step(by: 1, extend: extend); return true    // →
        case 10:  setMark(0); return true                     // § (ISO-Taste links der 1) → Markierung entfernen
        default: break
        }

        if event.characters == "?" { showShortcuts = true; return true }
        switch event.keyCode {
        case 49:                                          // Space → toggle zoom mode (loupe only)
            if viewMode == .loupe { zoom.setZoomMode(!zoom.sliderActive); return true }
        case 36:                                          // Return → focused viewing
            if viewMode == .loupe { focusMode.toggle(); return true }
            if currentID != nil { viewMode = .loupe; return true }
        case 53:                                          // Escape → leave zoom mode / reset zoom / leave loupe
            if viewMode == .loupe && zoom.sliderActive { zoom.setZoomMode(false); return true }
            if viewMode == .loupe && zoom.zoomed { zoom.fit(); return true }
            if focusMode { focusMode = false; return true }
            if viewMode == .loupe { viewMode = .grid; return true }
        default: break
        }

        if let chars = event.charactersIgnoringModifiers, chars.count == 1,
           let scalar = chars.unicodeScalars.first {
            switch scalar.value {
            case 48:                                        // 0 → clear mark
                if settings.zeroClearsMark { setMark(0) }
                return true
            case 0xA7, 0xB0:                                // § / ° (Taste links der 1, CH-Layout) → Markierung entfernen
                setMark(0); return true
            case 49...57:                                   // 1–9 → colour mark
                setMark(Int(scalar.value) - 48); return true
            case UInt32(UInt8(ascii: "i")), UInt32(UInt8(ascii: "I")):
                toggleInfo(); return true
            case UInt32(UInt8(ascii: "f")), UInt32(UInt8(ascii: "F")):
                toggleFullscreen(); return true
            case UInt32(UInt8(ascii: "z")), UInt32(UInt8(ascii: "Z")):
                if viewMode == .loupe { zoom.toggle100(); return true }
            case UInt32(UInt8(ascii: "+")), UInt32(UInt8(ascii: "=")):
                if viewMode == .loupe { zoom.zoomIn(); return true }
            case UInt32(UInt8(ascii: "-")), UInt32(UInt8(ascii: "_")):
                if viewMode == .loupe { zoom.zoomOut(); return true }
            default: break
            }
        }
        return false
    }
}
