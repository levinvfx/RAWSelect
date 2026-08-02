import SwiftUI
import AppKit
import Combine

@MainActor
final class AppState: ObservableObject {

    /// The live browser instance, so the app delegate can flush pending writes on quit.
    static weak var shared: AppState?

    let settings = AppSettings.shared
    private var cancellables = Set<AnyCancellable>()
    private var lastSortSig = ""

    // MARK: Published state
    @Published var volumes: [VolumeInfo] = []
    @Published var rootURL: URL?
    @Published var browseRoot: URL?      // root of the sidebar folder navigator
    @Published var groups: [PhotoGroup] = []
    @Published var tagFilter = TagFilter() { didSet { refreshDerived(); reconcileSelection() } }

    /// All selected photos (multi-select). `currentID` is the "active" one shown
    /// in the loupe and used as the anchor for keyboard navigation.
    @Published var selectedIDs: Set<String> = []
    @Published var currentID: String? {
        didSet {
            prefetchAroundCurrent()
            // Leaving a photo exits zoom mode — UNLESS we're zoomed in, then hold it across
            // photos so a burst can be checked at the same spot (see ZoomableImageView).
            if oldValue != currentID && !zoom.zoomed { zoom.sliderActive = false }
        }
    }
    private var anchorID: String?

    @Published var viewMode: ViewMode = .grid { didSet { if viewMode == .loupe { prefetchAroundCurrent() } else { focusMode = false } } }

    /// Distraction-free viewing: hides filmstrip, filter bar and status bar.
    @Published var focusMode = false

    /// Current column count of the thumbnail grid, reported by the grid view so ↑/↓
    /// can move a whole row at once (the layout is adaptive, so only the view knows it).
    @Published var gridColumns = 1

    /// Runtime toggle for the EXIF overlay (default from settings.metadataPanel).
    @Published var showInfo: Bool = AppSettings.shared.metadataPanel

    @Published var isScanning = false
    /// Files seen so far while scanning. The scanner always counted them — nobody asked for
    /// the number, so a 5000-photo folder showed a spinner with no end in sight.
    @Published var scanFound = 0
    @Published var statusMessage = "Kein Ordner geöffnet."

    @Published var operation: OperationState?
    @Published var pendingMoveTarget: URL?
    @Published var showExportWizard = false

    /// Non-destructive per-photo edits (crop/rotate/develop), keyed by group id.
    /// Made in the standalone editor or the export crop step, persisted per source,
    /// and applied on export. Only non-identity edits are kept.
    @Published var edits: [String: ImageEdit] = [:]
    /// Presents the standalone image editor for `currentGroup`.
    @Published var showEditor = false

    /// Transient confirmation/error banner shown at the bottom of the window.
    @Published var toast: Toast?
    /// Keyboard-shortcut cheat sheet (toggled with `?`).
    @Published var showShortcuts = false

    /// Pan/zoom state for the loupe, shared with `ZoomableImageView`.
    let zoom = ZoomController()

    /// Side-by-side compare (A|B): left = `currentID`, right = `compareRightID`. Each pane has
    /// its own zoom controller; keyboard/button zoom is mirrored to both for a synced check.
    let compareZoomL = ZoomController()
    let compareZoomR = ZoomController()
    @Published var compareRightID: String?
    var compareRightGroup: PhotoGroup? { compareRightID.flatMap { groupByID[$0] } }

    enum ViewMode: String, CaseIterable { case grid, loupe, compare }

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

    // MARK: Derived (cached — rebuilt only when groups/filter/marks change, so the
    // navigation hot path stays O(1) even with thousands of photos).
    @Published private(set) var filteredGroups: [PhotoGroup] = []
    private var filteredIndexByID: [String: Int] = [:]
    private var groupByID: [String: PhotoGroup] = [:]

    /// Rebuilds the cached filtered list and lookup maps. This is the single choke
    /// point that keeps the derived state honest — call it after ANY change to
    /// `groups`, `tagFilter`, or marks. Avoids the O(n) `filter`/`firstIndex` that
    /// previously ran several times per keystroke.
    private func refreshDerived() {
        filteredGroups = groups.filter { tagFilter.matches($0) }
        filteredIndexByID.removeAll(keepingCapacity: true)
        for (i, g) in filteredGroups.enumerated() { filteredIndexByID[g.id] = i }
        groupByID.removeAll(keepingCapacity: true)
        for g in groups { groupByID[g.id] = g }
    }

    var currentGroup: PhotoGroup? {
        guard let id = currentID else { return nil }
        return groupByID[id]
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
        AppState.shared = self
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
        refreshDerived()
        selectedIDs = []
        currentID = nil
        isScanning = false
        statusMessage = "Ordner in der Seitenleiste doppelklicken, um die Bilder zu laden."
    }

    /// Abort an in-progress scan (large folders / slow network volumes).
    func cancelScan() {
        guard isScanning else { return }
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
        // The undo snapshots belong to the folder we're leaving. Photo ids are relative to the
        // scan root, so two card folders both hold "/img_0001" — keeping the stack meant ⌘Z
        // applied the OTHER folder's marks to this folder's photos, and persisted them.
        markUndoStack.removeAll()
        if setBrowseRoot {
            if url.isOnExternalVolume, let vol = try? url.resourceValues(forKeys: [.volumeURLKey]).volume {
                browseRoot = vol
            } else {
                browseRoot = url
            }
        }
        groups = []
        refreshDerived()
        selectedIDs = []
        currentID = nil
        anchorID = nil
        isScanning = true
        scanFound = 0
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
                                               isCancelled: { token.isCancelled },
                                               onProgress: { n in Task { @MainActor in self.scanFound = n } })
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
            // Re-attach saved non-destructive edits to their photos.
            var loadedEdits: [String: ImageEdit] = [:]
            for g in found {
                if let e = savedMarks[g.persistKey]?.edit, !e.isIdentity { loadedEdits[g.id] = e }
            }
            self.edits = loadedEdits
            self.applySort()
            self.isScanning = false
            // Warm only the first screenful of tiny thumbnails so the initial grid
            // is instant; the rest load lazily on appearance and via the sliding
            // prefetch window around the current photo (no queue flood at open).
            let initialWarm = self.filteredGroups.prefix(PreviewConfig.initialWarmCount).map { $0.previewURL }
            ThumbnailLoader.shared.warmTiny(initialWarm, maxPixel: PreviewConfig.tinyMaxPixel)
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
        let current = currentID.flatMap { filteredIndexByID[$0] } ?? (delta > 0 ? -1 : 0)
        var next = current + delta
        if settings.wrapNavigation && !extend {
            next = (next % list.count + list.count) % list.count   // wrap around
        } else {
            next = min(max(next, 0), list.count - 1)
        }
        let id = list[next].id
        if extend { selectRange(to: id) } else { selectSingle(id) }
    }

    /// Jumps to the next/previous still-UNMARKED photo — the core of the second culling
    /// pass ("show me what I haven't judged yet") without changing the filter.
    private func jumpUnmarked(forward: Bool) {
        let list = filteredGroups
        guard !list.isEmpty else { return }
        let start = currentID.flatMap { filteredIndexByID[$0] } ?? -1
        let indices = forward ? Array(stride(from: start + 1, to: list.count, by: 1))
                              : Array(stride(from: start - 1, through: 0, by: -1))
        for i in indices where list[i].mark == 0 { selectSingle(list[i].id); return }
        statusMessage = forward ? "Kein weiteres unmarkiertes Bild." : "Kein vorheriges unmarkiertes Bild."
    }

    /// Selects the first/last photo in the current filtered list (Home/End).
    private func jumpToEdge(last: Bool, extend: Bool) {
        guard let g = last ? filteredGroups.last : filteredGroups.first else { return }
        if extend { selectRange(to: g.id) } else { selectSingle(g.id) }
    }

    // MARK: Compare (A|B)
    /// Enters side-by-side compare with the current photo on the left and its neighbour on the
    /// right. ←/→ then cycle the right pane through the series; Return promotes B to A.
    func enterCompare() {
        guard filteredGroups.count >= 2, let cur = currentID, let idx = filteredIndexByID[cur] else { return }
        let rightIdx = idx + 1 < filteredGroups.count ? idx + 1 : idx - 1
        compareRightID = filteredGroups[rightIdx].id
        viewMode = .compare
    }

    func exitCompare() { if viewMode == .compare { viewMode = .loupe } }

    private func compareCycleRight(_ delta: Int) {
        let list = filteredGroups
        guard let rid = compareRightID, let i = filteredIndexByID[rid], !list.isEmpty else { return }
        let j = min(max(i + delta, 0), list.count - 1)
        compareRightID = list[j].id
    }

    /// Promotes the right photo (B) to the left anchor (A) and moves the old A to the right —
    /// so you can keep the better frame and keep comparing against the rest.
    private func compareSwap() {
        guard let rid = compareRightID, let cur = currentID else { return }
        selectSingle(rid)
        compareRightID = cur
    }

    private func compareZoomBoth(_ action: (ZoomController) -> Void) {
        action(compareZoomL); action(compareZoomR)
    }

    /// Keyboard handling while in compare mode (kept separate from the loupe/grid keys).
    private func handleCompare(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 123: compareCycleRight(-1); return true          // ← cycle B back
        case 124: compareCycleRight(1);  return true          // → cycle B forward
        case 36:  compareSwap();         return true          // Return → promote B to A
        case 53, 8: exitCompare();       return true          // Esc / C → leave compare
        case 49:  compareZoomBoth { $0.spaceToggle() }; return true   // Space → both 100%/fit
        default: break
        }
        if let chars = event.charactersIgnoringModifiers, chars.count == 1, let s = chars.unicodeScalars.first {
            switch s.value {
            case 48, 0xA7, 0xB0: setMark(0); return true       // 0 / § → clear mark (on A)
            case 49...57: setMark(Int(s.value) - 48); return true   // 1–9 → mark A
            case UInt32(UInt8(ascii: "z")), UInt32(UInt8(ascii: "Z")): compareZoomBoth { $0.toggle100() }; return true
            case UInt32(UInt8(ascii: "+")), UInt32(UInt8(ascii: "=")): compareZoomBoth { $0.zoomIn() }; return true
            case UInt32(UInt8(ascii: "-")), UInt32(UInt8(ascii: "_")): compareZoomBoth { $0.zoomOut() }; return true
            default: break
            }
        }
        return true   // swallow everything else so stray keys can't act on the background
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
        guard let idx = filteredIndexByID[id], count > 1 else { return }
        let loader = ThumbnailLoader.shared
        let target = settings.perfectPixels
        let instantPixel = settings.instantPixels

        let sharpFwd = Int(settings.preloadForward)
        let sharpBack = Int(settings.preloadBackward)
        let softFwd = sharpFwd + 25          // much wider soft buffer (cheap to hold)
        let softBack = sharpBack + 12
        let maxOffset = max(softFwd, softBack)

        var wantedPaths = Set<String>()
        wantedPaths.insert(list[idx].previewURL.path)   // the current photo is always wanted
        for d in 1...maxOffset {
            for dir in [1, -1] {             // forward first at each distance
                let i = idx + d * dir
                guard i >= 0, i < count else { continue }
                let softLimit = dir > 0 ? softFwd : softBack
                guard d <= softLimit else { continue }
                let url = list[i].previewURL
                wantedPaths.insert(url.path)
                // Tiny first (cheapest) so even a fast scrub always finds a frame,
                // then the soft instant tier.
                loader.prefetch(for: url, maxPixel: PreviewConfig.tinyMaxPixel, fullQuality: false)
                loader.prefetch(for: url, maxPixel: instantPixel, fullQuality: false)
                let sharpLimit = dir > 0 ? sharpFwd : sharpBack
                if d <= sharpLimit {
                    let plan = loader.previewPlan(for: url, targetLongEdge: target)
                    loader.prefetch(for: url, maxPixel: plan.maxPixel, fullQuality: plan.fullQuality)
                }
            }
        }
        // Drop prefetch work for anything the cursor has moved away from (fast scrub / jump).
        loader.retainPrefetch(wantedPaths: wantedPaths)
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
        // Auto-advance for fast culling (Settings → Markierungen). Never in compare mode —
        // there the left anchor must stay put while you cycle the right pane.
        if settings.autoAdvance && mark != 0 && single && currentID == before && viewMode != .compare {
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
        refreshDerived()
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
        refreshDerived()
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

    /// Snapshot of what belongs in the session file for the folder that's open right now.
    private func sessionSnapshot() -> (id: String, states: [String: SessionStore.PhotoState], scope: Set<String>)? {
        guard let identity else { return nil }
        var states: [String: SessionStore.PhotoState] = [:]
        var scope = Set<String>()
        scope.reserveCapacity(groups.count)
        for g in groups {
            // The scope is EVERY loaded photo, not just the marked ones: the store may only
            // replace the keys of this folder, and an unmarked photo has to be able to drop
            // out. Other folders share the same file (one per volume) and must survive.
            scope.insert(g.persistKey)
            let edit = edits[g.id]
            let hasEdit = !(edit?.isIdentity ?? true)
            guard g.mark != 0 || hasEdit else { continue }
            states[g.persistKey] = SessionStore.PhotoState(mark: g.mark, edit: hasEdit ? edit : nil)
        }
        return (identity.id, states, scope)
    }

    private func report(_ result: SessionStore.SaveResult) {
        switch result {
        case .ok:
            break
        case .quarantined(let name):
            let msg = "Gespeicherte Markierungen waren beschädigt – beiseitegelegt als \(name). Neu wird sauber gespeichert."
            statusMessage = msg
            showToast("Session war beschädigt – beiseitegelegt, wird neu gespeichert.", kind: .error)
        case .failed(let msg):
            // Silence here meant marking for hours into the void when the disk was full.
            // The status line alone is not enough: the next keypress overwrites it, and it is
            // hidden entirely in focus mode — so an error MUST also raise a lingering toast.
            statusMessage = "Markierungen konnten NICHT gespeichert werden: \(msg)"
            showToast("Markierungen konnten NICHT gespeichert werden!", kind: .error)
        }
    }

    /// Serialises session writes so the LAST keypress always wins. Independent `Task {}`s
    /// were not guaranteed to reach the writer in creation order, so a late older snapshot
    /// (scope = the whole folder) could overwrite a newer one. Each write now awaits the
    /// previous one, which pins execution order to submission order.
    private var writeChain: Task<Void, Never>?

    /// Carries a save result across the semaphore in `persistStateNow` without hopping to the
    /// main actor inside the task (which would deadlock while the main thread is blocked).
    private final class SaveResultBox: @unchecked Sendable { var value: SessionStore.SaveResult = .ok }

    /// Saves in the background. Encoding and writing the file used to happen synchronously on
    /// the main thread on EVERY keypress — with thousands of photos that is the one place the
    /// app must never stall, because it's the whole job. Chained so writes still land in order.
    private func persistState() {
        guard let snap = sessionSnapshot() else { return }
        let previous = writeChain
        writeChain = Task { [weak self] in
            _ = await previous?.value
            let result = await SessionStore.SessionWriter.shared.write(snap.id, snap.states, snap.scope)
            self?.report(result)
        }
    }

    /// Saves right now and waits for it — draining any queued writes first so the newest state
    /// is what lands. Used when the app is about to lose the state (export wizard closing, app
    /// terminating), where correctness beats the millisecond.
    private func persistStateNow() {
        guard let snap = sessionSnapshot() else { return }
        let pending = writeChain
        let box = SaveResultBox()
        let sem = DispatchSemaphore(value: 0)
        Task.detached {
            _ = await pending?.value   // let queued writes finish in order (last wins)
            box.value = await SessionStore.SessionWriter.shared.write(snap.id, snap.states, snap.scope)
            sem.signal()
        }
        sem.wait()                     // safe: the detached task never touches the main actor
        report(box.value)
    }

    /// Flushes any pending marks/edits synchronously. Called when the app is about to quit so
    /// the very last mark before ⌘Q is never lost to an in-flight background write.
    func flushPendingWrites() { persistStateNow() }

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
        refreshDerived()
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

    // MARK: Image editing
    /// Current non-destructive edit for a photo (identity when untouched).
    func edit(for id: String) -> ImageEdit { edits[id] ?? ImageEdit() }

    /// Stores an edit centrally and persists it. Identity edits are dropped so the
    /// session file stays clean and `hasEdits` stays honest.
    func commitEdit(_ edit: ImageEdit, for id: String) {
        if edit.isIdentity { edits[id] = nil } else { edits[id] = edit }
        persistState()
    }

    func hasEdit(_ id: String) -> Bool { !(edits[id]?.isIdentity ?? true) }

    /// Flushes the current edits to disk (e.g. when the export wizard closes).
    func saveEditsNow() { persistStateNow() }

    /// Opens the standalone editor for the active photo (loupe or grid).
    func openEditor() {
        guard currentGroup != nil else { statusMessage = "Kein Bild ausgewählt."; return }
        showEditor = true
    }

    // MARK: Open in external app (Lightroom etc.)
    /// Display name of the currently configured "open with" app (default: Lightroom).
    var openWithAppName: String {
        let name = OpenWithService.appName(settings.openWithAppPath)
        return name.isEmpty ? "Lightroom" : name
    }
    /// Title for the toolbar button — reflects the chosen app once set.
    var openWithButtonTitle: String {
        settings.openWithAppPath.isEmpty ? "Öffnen mit…" : "In \(openWithAppName) öffnen"
    }

    /// Opens the selected photos' original/RAW files in the chosen external app.
    /// On first use (no app configured yet) it asks which app to use and remembers
    /// it; afterwards the choice is fixed but changeable in Settings.
    func openSelectionInExternalApp() {
        let sel = selectedGroups
        guard !sel.isEmpty else {
            statusMessage = "Keine Bilder ausgewählt."
            showToast("Keine Bilder ausgewählt.", kind: .error); return
        }
        // First use: let the user pick the default app, then store it.
        if settings.openWithAppPath.isEmpty {
            guard let chosen = OpenWithService.chooseApp() else { return }   // cancelled
            settings.openWithAppPath = chosen.path
        }
        let files = sel.map { rawURL(for: $0) }               // the RAW/original per photo
        if OpenWithService.open(files, withAppAt: settings.openWithAppPath) {
            showToast("\(sel.count == 1 ? "Bild" : "\(sel.count) Bilder") in \(openWithAppName) geöffnet.")
        } else {
            // App missing → clear the stale path so the next click asks again.
            let missing = openWithAppName
            settings.openWithAppPath = ""
            statusMessage = "App zum Öffnen nicht gefunden."
            showToast("„\(missing)“ nicht gefunden – bitte neu wählen.", kind: .error)
        }
    }

    // MARK: Export helpers
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

    /// Reject flow: moves the selected photos to the macOS Trash (recoverable), then advances
    /// to the neighbour so culling keeps flowing. Disabled from SD cards/external volumes —
    /// the source there must never be modified (same rule as Move).
    func trashSelection() {
        let sel = selectedGroups
        guard !sel.isEmpty else { statusMessage = "Keine Bilder ausgewählt."; return }
        guard !sourceIsExternal else {
            statusMessage = "Löschen ist von SD-Karten/externen Datenträgern deaktiviert – bitte erst kopieren."
            showToast("Löschen von SD-Karten ist deaktiviert.", kind: .error); return
        }
        let anchorPos = filteredGroups.firstIndex { $0.id == currentID }
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                FileOperationService.trash(groups: sel)
            }.value
            let trashed = outcome.trashedGroupIDs
            guard !trashed.isEmpty || !outcome.failures.isEmpty else { return }
            self.groups.removeAll { trashed.contains($0.id) }
            self.selectedIDs.subtract(trashed)
            for id in trashed { self.edits[id] = nil }
            self.refreshDerived()
            self.persistState()

            // Keep the cursor where it was, on the photo that slid into this slot.
            let list = self.filteredGroups
            if list.isEmpty { self.selectedIDs = []; self.currentID = nil }
            else { self.selectSingle(list[min(anchorPos ?? 0, list.count - 1)].id) }

            if outcome.failures.isEmpty {
                let n = outcome.photos
                self.statusMessage = "\(n) \(n == 1 ? "Bild" : "Bilder") in den Papierkorb verschoben."
                self.showToast("\(n) in den Papierkorb.", kind: .success)
            } else {
                self.statusMessage = "\(outcome.failures.count) Datei(en) nicht gelöscht – Rest im Papierkorb."
                self.showToast("\(outcome.failures.count) nicht gelöscht – Rest im Papierkorb.", kind: .error)
            }
        }
    }

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
        // Always a flat export into the chosen target — no per-mark subfolders.
        let snapshot = selection
        guard !snapshot.isEmpty else { statusMessage = "Keine passenden Bilder für den Export."; return }

        let conflict = settings.conflictMode
        let rawJpgMode = settings.rawJpgExport
        if conflict == .overwrite && !confirmOverwrite() { return }

        let makeSubfolder: (PhotoGroup) -> String? = { _ in nil }

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
                    self.refreshDerived()
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
           !showExportWizard, !showEditor, NSApp.keyWindow === NSApp.mainWindow,
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
        guard !showExportWizard, !showEditor, NSApp.keyWindow === NSApp.mainWindow else { return false }

        if viewMode == .compare { return handleCompare(event) }

        let extend = event.modifierFlags.contains(.shift)

        switch event.keyCode {
        case 123: step(by: -1, extend: extend); return true   // ←
        case 124: step(by: 1, extend: extend); return true    // →
        case 126: if viewMode == .grid { step(by: -gridColumns, extend: extend) }; return true  // ↑ (one row up)
        case 125: if viewMode == .grid { step(by: gridColumns, extend: extend) }; return true   // ↓ (one row down)
        case 115: jumpToEdge(last: false, extend: extend); return true   // Home → first
        case 119: jumpToEdge(last: true, extend: extend); return true    // End → last
        case 48:  jumpUnmarked(forward: !extend); return true            // Tab / ⇧Tab → next/prev unmarked
        case 51:  trashSelection(); return true                         // ⌫ Delete → in den Papierkorb (Reject)
        case 10:  setMark(0); return true                     // § (ISO-Taste links der 1) → Markierung entfernen
        default: break
        }

        if event.characters == "?" { showShortcuts = true; return true }
        switch event.keyCode {
        case 49:                                          // Space → native ⇄ fit zoom toggle (loupe only)
            if viewMode == .loupe { zoom.spaceToggle(); return true }
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
            case UInt32(UInt8(ascii: "c")), UInt32(UInt8(ascii: "C")):
                enterCompare(); return true
            case UInt32(UInt8(ascii: "e")), UInt32(UInt8(ascii: "E")):
                openEditor(); return true
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
