import SwiftUI
import AppKit

@MainActor
final class AppState: ObservableObject {

    // MARK: Published state
    @Published var volumes: [VolumeInfo] = []
    @Published var rootURL: URL?
    @Published var groups: [PhotoGroup] = []
    @Published var filter: PhotoFilter = .all { didSet { reconcileSelection() } }

    /// All selected photos (multi-select). `currentID` is the "active" one shown
    /// in the loupe and used as the anchor for keyboard navigation.
    @Published var selectedIDs: Set<String> = []
    @Published var currentID: String?
    private var anchorID: String?

    @Published var viewMode: ViewMode = .grid

    @Published var isScanning = false
    @Published var statusMessage = "Kein Ordner geöffnet."

    @Published var operation: OperationState?
    @Published var pendingMoveTarget: URL?

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
    var filteredGroups: [PhotoGroup] { groups.filter { filter.matches($0) } }

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
    var unmarkedCount: Int { groups.filter { $0.mark == 0 }.count }
    var markedCount: Int { groups.filter { $0.mark != 0 }.count }

    // MARK: Lifecycle
    func start() {
        refreshVolumes()
        volumeScanner.startWatching { [weak self] in self?.refreshVolumes() }
        installKeyMonitor()
    }

    func refreshVolumes() { volumes = VolumeScanner.externalVolumes() }

    // MARK: Opening / scanning
    func openFolderDialog() {
        if let url = FinderService.chooseFolder(title: "Ordner oder SD-Karte öffnen") { open(url) }
    }

    func open(_ url: URL) {
        scanTask?.cancel()
        rootURL = url
        groups = []
        selectedIDs = []
        currentID = nil
        anchorID = nil
        isScanning = true
        statusMessage = "Scanne \(url.lastPathComponent) …"

        let identity = FolderIdentity(root: url)
        self.identity = identity
        let savedMarks = SessionStore.load(identityID: identity.id)

        scanTask = Task {
            let found: [PhotoGroup] = await Task.detached(priority: .userInitiated) {
                var groups = PhotoScanner.scan(root: url)
                for i in groups.indices {
                    let key = identity.persistKey(directory: groups[i].directory, baseName: groups[i].baseName)
                    groups[i].persistKey = key
                    if let mark = savedMarks[key] { groups[i].mark = mark }
                }
                return groups
            }.value

            if Task.isCancelled { return }
            self.groups = found
            self.isScanning = false
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
        let next = min(max(current + delta, 0), list.count - 1)
        let id = list[next].id
        if extend { selectRange(to: id) } else { selectSingle(id) }
    }

    private func reconcileSelection() {
        let ids = Set(filteredGroups.map { $0.id })
        selectedIDs.formIntersection(ids)
        if let id = currentID, ids.contains(id) { return }
        currentID = filteredGroups.first?.id
        if let c = currentID, selectedIDs.isEmpty { selectedIDs = [c]; anchorID = c }
    }

    // MARK: Marking (applies to the whole selection)
    func setMark(_ mark: Int) {
        let targets = selectedIDs.isEmpty ? Set([currentID].compactMap { $0 }) : selectedIDs
        guard !targets.isEmpty else { return }

        let anchorPos = filteredGroups.firstIndex { $0.id == currentID }
        for i in groups.indices where targets.contains(groups[i].id) { groups[i].mark = mark }
        persistMarks()

        let n = targets.count
        if mark == 0 {
            statusMessage = n == 1 ? "Markierung entfernt." : "Markierung von \(n) Bildern entfernt."
        } else {
            statusMessage = n == 1 ? "Markierung \(mark) gesetzt." : "Markierung \(mark) für \(n) Bilder gesetzt."
        }

        // Keep culling flowing: if the marked photos left the current filter,
        // move to the neighbouring photo.
        let visible = Set(filteredGroups.map { $0.id })
        if currentID == nil || !visible.contains(currentID!) {
            let list = filteredGroups
            if list.isEmpty { selectedIDs = []; currentID = nil }
            else {
                let pos = min(anchorPos ?? 0, list.count - 1)
                selectSingle(list[pos].id)
            }
        } else {
            selectedIDs.formIntersection(visible)
            if selectedIDs.isEmpty, let c = currentID { selectedIDs = [c] }
        }
    }

    private func persistMarks() {
        guard let identity else { return }
        var marks: [String: Int] = [:]
        for g in groups where g.mark != 0 { marks[g.persistKey] = g.mark }
        SessionStore.save(identityID: identity.id, marks: marks)
    }

    // MARK: Finder
    func revealCurrent() {
        guard let g = currentGroup else { statusMessage = "Kein Bild ausgewählt."; return }
        FinderService.reveal(g.previewURL)
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

    private func runOperation(_ kind: FileOperationService.Kind, target: URL,
                              groups snapshot: [PhotoGroup], includeSidecars: Bool) {
        let title = kind == .copy ? "Kopiere Bilder …" : "Verschiebe Bilder …"
        let token = CancellationToken()
        cancelToken = token
        operation = OperationState(title: title, completed: 0, total: 0)

        Task {
            do {
                let outcome = try await Task.detached(priority: .userInitiated) { [weak self] in
                    try FileOperationService.perform(
                        kind, groups: snapshot, targetRoot: target, includeSidecars: includeSidecars,
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
                    self.persistMarks()
                    self.reconcileSelection()
                }
                FinderService.revealFolder(target)
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

        if let chars = event.charactersIgnoringModifiers, chars.count == 1,
           let scalar = chars.unicodeScalars.first, scalar.value >= 48, scalar.value <= 57 {
            setMark(Int(scalar.value) - 48)
            return true
        }
        return false
    }
}
