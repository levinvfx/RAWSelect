import SwiftUI
import AppKit

@MainActor
final class AppState: ObservableObject {

    // MARK: Published state
    @Published var volumes: [VolumeInfo] = []
    @Published var rootURL: URL?
    @Published var groups: [PhotoGroup] = []
    @Published var filter: PhotoFilter = .all { didSet { reconcileSelection() } }
    @Published var selectedID: String?
    @Published var viewMode: ViewMode = .grid

    @Published var isScanning = false
    @Published var scanCount = 0
    @Published var statusMessage = "Kein Ordner geöffnet."

    @Published var operation: OperationState?          // active copy/move overlay
    @Published var pendingMoveTarget: URL?             // set while move confirm is shown

    enum ViewMode: String, CaseIterable { case grid, loupe }

    struct OperationState {
        var title: String
        var completed: Int
        var total: Int
    }

    // MARK: Private
    private let volumeScanner = VolumeScanner()
    private var scanTask: Task<Void, Never>?
    private var cancelToken: CancellationToken?   // for copy/move cancellation
    private var keyMonitor: Any?

    // MARK: Derived
    var filteredGroups: [PhotoGroup] {
        groups.filter { filter.matches($0) }
    }

    var selectedGroup: PhotoGroup? {
        guard let id = selectedID else { return nil }
        return groups.first { $0.id == id }
    }

    /// Move is only allowed from an internal disk, never from an SD card/external.
    var sourceIsExternal: Bool {
        rootURL?.isOnExternalVolume ?? false
    }

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

    func refreshVolumes() {
        volumes = VolumeScanner.externalVolumes()
    }

    // MARK: Opening / scanning
    func openFolderDialog() {
        if let url = FinderService.chooseFolder(title: "Ordner oder SD-Karte öffnen") {
            open(url)
        }
    }

    func open(_ url: URL) {
        scanTask?.cancel()
        rootURL = url
        groups = []
        selectedID = nil
        isScanning = true
        scanCount = 0
        statusMessage = "Scanne \(url.lastPathComponent) …"

        let savedMarks = SessionStore.load(root: url)

        scanTask = Task {
            let found: [PhotoGroup] = await Task.detached(priority: .userInitiated) {
                var groups = PhotoScanner.scan(root: url) { _ in }
                for i in groups.indices {
                    if let mark = savedMarks[groups[i].id] { groups[i].mark = mark }
                }
                return groups
            }.value

            if Task.isCancelled { return }
            self.groups = found
            self.isScanning = false
            self.selectedID = self.filteredGroups.first?.id
            let markedNote = self.markedCount > 0 ? " (\(self.markedCount) markiert)" : ""
            self.statusMessage = found.isEmpty
                ? "Keine Bilder gefunden."
                : "\(found.count) Bilder gefunden\(markedNote)."
        }
    }

    // MARK: Selection & navigation
    func select(_ id: String) { selectedID = id }

    func selectNext() { step(by: 1) }
    func selectPrevious() { step(by: -1) }

    private func step(by delta: Int) {
        let list = filteredGroups
        guard !list.isEmpty else { return }
        let current = list.firstIndex { $0.id == selectedID } ?? (delta > 0 ? -1 : 0)
        let next = min(max(current + delta, 0), list.count - 1)
        selectedID = list[next].id
    }

    private func reconcileSelection() {
        let list = filteredGroups
        if let id = selectedID, list.contains(where: { $0.id == id }) { return }
        selectedID = list.first?.id
    }

    // MARK: Marking
    func setMark(_ mark: Int) {
        guard let id = selectedID, let idx = groups.firstIndex(where: { $0.id == id }) else { return }
        let list = filteredGroups
        let positionInFilter = list.firstIndex { $0.id == id }

        groups[idx].mark = mark
        persistMarks()

        if mark == 0 {
            statusMessage = "Markierung entfernt."
        } else {
            statusMessage = "Markierung \(mark) gesetzt."
        }

        // If the just-marked photo no longer matches the active filter, advance
        // to the neighbour so culling keeps flowing.
        if !filter.matches(groups[idx]), let pos = positionInFilter {
            let newList = filteredGroups
            if newList.isEmpty {
                selectedID = nil
            } else {
                selectedID = newList[min(pos, newList.count - 1)].id
            }
        }
    }

    private func persistMarks() {
        guard let root = rootURL else { return }
        var marks: [String: Int] = [:]
        for g in groups where g.mark != 0 { marks[g.id] = g.mark }
        SessionStore.save(root: root, marks: marks)
    }

    // MARK: Finder
    func revealSelected() {
        guard let g = selectedGroup else {
            statusMessage = "Kein Bild ausgewählt."
            return
        }
        FinderService.reveal(g.previewURL)
    }

    // MARK: Copy / Move
    func copyMarked() {
        guard markedCount > 0 else { statusMessage = "Keine markierten Bilder."; return }
        guard let target = FinderService.chooseDestination(title: "Ziel für markierte Bilder (Kopieren)") else { return }
        runOperation(.copy, target: target)
    }

    /// Called by the toolbar button. If the source is external, we refuse; else
    /// we stash the target and let the view show a confirmation dialog.
    func requestMoveMarked() {
        guard markedCount > 0 else { statusMessage = "Keine markierten Bilder."; return }
        guard !sourceIsExternal else {
            statusMessage = "Verschieben ist von SD-Karten/externen Datenträgern deaktiviert – bitte kopieren."
            return
        }
        guard let target = FinderService.chooseDestination(title: "Ziel für markierte Bilder (Verschieben)") else { return }
        pendingMoveTarget = target
    }

    func confirmMove() {
        guard let target = pendingMoveTarget else { return }
        pendingMoveTarget = nil
        runOperation(.move, target: target)
    }

    func cancelMove() { pendingMoveTarget = nil }

    func cancelOperation() { cancelToken?.cancel() }

    private func runOperation(_ kind: FileOperationService.Kind, target: URL) {
        let snapshot = groups
        let title = kind == .copy ? "Kopiere markierte Bilder …" : "Verschiebe markierte Bilder …"
        let token = CancellationToken()
        cancelToken = token
        operation = OperationState(title: title, completed: 0, total: 0)

        Task {
            do {
                let outcome = try await Task.detached(priority: .userInitiated) { [weak self] in
                    try FileOperationService.perform(
                        kind,
                        groups: snapshot,
                        targetRoot: target,
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
                    // Remove moved photos from the current view.
                    let movedIDs = Set(snapshot.filter { $0.mark != 0 }.map { $0.id })
                    self.groups.removeAll { movedIDs.contains($0.id) }
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

    /// Returns true if the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        // Don't interfere with menu / system shortcuts.
        if event.modifierFlags.contains(.command) { return false }
        // Don't steal keys while editing text.
        if NSApp.keyWindow?.firstResponder is NSText { return false }

        switch event.keyCode {
        case 123: selectPrevious(); return true   // left arrow
        case 124: selectNext(); return true       // right arrow
        default: break
        }

        if let chars = event.charactersIgnoringModifiers, chars.count == 1,
           let scalar = chars.unicodeScalars.first, scalar.value >= 48, scalar.value <= 57 {
            let digit = Int(scalar.value) - 48   // 0…9
            setMark(digit)
            return true
        }
        return false
    }
}
