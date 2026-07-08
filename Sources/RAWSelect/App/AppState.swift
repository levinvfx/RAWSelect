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
    @Published var currentID: String? { didSet { prefetchAroundCurrent() } }
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

    enum ViewMode: String, CaseIterable { case grid, loupe }

    struct OperationState {
        var title: String
        var completed: Int
        var total: Int
    }

    // MARK: Private
    private let volumeScanner = VolumeScanner()
    private var scanTask: Task<Void, Never>?
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
        scanTask?.cancel()
        browseRoot = url
        rootURL = nil
        groups = []
        selectedIDs = []
        currentID = nil
        isScanning = false
        statusMessage = "Ordner in der Seitenleiste doppelklicken, um die Bilder zu laden."
    }

    // MARK: Opening / scanning
    func openFolderDialog() {
        if let url = FinderService.chooseFolder(title: "Ordner oder SD-Karte öffnen") { open(url) }
    }

    func open(_ url: URL, setBrowseRoot: Bool = true) {
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

        scanTask = Task {
            let found: [PhotoGroup] = await Task.detached(priority: .userInitiated) {
                var groups = PhotoScanner.scan(root: url, allowedExtensions: allowed, recursive: recursive,
                                               groupPairs: groupPairs, ignoreHidden: ignoreHidden,
                                               cameraFoldersOnly: cameraOnly)
                for i in groups.indices {
                    let key = identity.persistKey(directory: groups[i].directory, baseName: groups[i].baseName)
                    groups[i].persistKey = key
                    if let state = savedMarks[key] {
                        groups[i].mark = state.mark
                    }
                }
                return groups
            }.value

            if Task.isCancelled { return }
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

    /// Warms the HD preview cache for the photos around the current one so that
    /// stepping through with the arrow keys has no load time.
    private func prefetchAroundCurrent() {
        guard viewMode == .loupe, settings.preloadPerfect, let id = currentID else { return }
        let list = filteredGroups
        guard let idx = list.firstIndex(where: { $0.id == id }) else { return }
        let lower = max(0, idx - Int(settings.preloadBackward))
        let upper = min(list.count - 1, idx + Int(settings.preloadForward))
        let target = settings.perfectPixels
        let instantPixel = settings.instantPixels
        for i in lower...upper where i != idx {
            let url = list[i].previewURL
            // Instant size first (small, quick) so the sync cache path has a frame
            // to paint immediately; the HD version follows via the size-aware plan
            // (same key the loupe reads, so it's an instant cache hit).
            ThumbnailLoader.shared.prefetch(for: url, maxPixel: instantPixel, fullQuality: false)
            let plan = ThumbnailLoader.shared.previewPlan(for: url, targetLongEdge: target)
            ThumbnailLoader.shared.prefetch(for: url, maxPixel: plan.maxPixel, fullQuality: plan.fullQuality)
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
    private func mutateSelection(_ body: (inout PhotoGroup) -> Void, status: (Int) -> String) {
        let targets = selectedIDs.isEmpty ? Set([currentID].compactMap { $0 }) : selectedIDs
        guard !targets.isEmpty else { return }

        let anchorPos = filteredGroups.firstIndex { $0.id == currentID }
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
                self.statusMessage = "\(outcome.photos) Bilder (\(outcome.files) Dateien) \(verb)."

                if kind == .move {
                    let movedIDs = Set(snapshot.map { $0.id })
                    self.groups.removeAll { movedIDs.contains($0.id) }
                    self.selectedIDs.subtract(movedIDs)
                    self.persistState()
                    self.reconcileSelection()
                }
                if self.settings.revealAfterExport { FinderService.revealFolder(target) }
            } catch {
                self.operation = nil
                self.statusMessage = "Fehler: \(error.localizedDescription)"
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
        if event.modifierFlags.contains(.command) { return false }   // leave ⌘-shortcuts to menus
        if NSApp.keyWindow?.firstResponder is NSText { return false }

        let extend = event.modifierFlags.contains(.shift)

        switch event.keyCode {
        case 123: step(by: -1, extend: extend); return true   // ←
        case 124: step(by: 1, extend: extend); return true    // →
        default: break
        }

        // Space/Return/Escape only steer the browser window – never while the
        // export wizard or the Settings window is up (would swallow their keys).
        let browserIsKey = !showExportWizard && NSApp.keyWindow === NSApp.mainWindow
        if browserIsKey {
            switch event.keyCode {
            case 36:                                          // Return → focused viewing
                if viewMode == .loupe { focusMode.toggle(); return true }
                if currentID != nil { viewMode = .loupe; return true }
            case 53:                                          // Escape → leave focus / loupe
                if focusMode { focusMode = false; return true }
                if viewMode == .loupe { viewMode = .grid; return true }
            default: break
            }
        }

        if let chars = event.charactersIgnoringModifiers, chars.count == 1,
           let scalar = chars.unicodeScalars.first {
            switch scalar.value {
            case 48:                                        // 0 → clear mark
                if settings.zeroClearsMark { setMark(0) }
                return true
            case 49...57:                                   // 1–9 → colour mark
                setMark(Int(scalar.value) - 48); return true
            case UInt32(UInt8(ascii: "i")), UInt32(UInt8(ascii: "I")):
                toggleInfo(); return true
            case UInt32(UInt8(ascii: "f")), UInt32(UInt8(ascii: "F")):
                toggleFullscreen(); return true
            default: break
            }
        }
        return false
    }
}
