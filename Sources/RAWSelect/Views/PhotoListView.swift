import SwiftUI

/// Finder-like list of the photos: one row per photo with mark, name, dates, type and size.
/// Clicking a column header sorts by it — ascending, descending, then no sort (`AppState.cycleSort`);
/// the order is the same one the grid and the loupe use. Double-click opens the large view.
struct PhotoListView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: AppSettings

    /// The header arrows mirror the shared sort setting; a click is turned into the Finder cycle
    /// instead of the table's own asc/desc toggle (which has no "none").
    private var sortOrder: Binding<[KeyPathComparator<PhotoGroup>]> {
        Binding(
            get: {
                let order: SortOrder = settings.sortReversed ? .reverse : .forward
                switch settings.sortField {
                case .unsorted: return []
                case .filename: return [KeyPathComparator(\PhotoGroup.displayName, order: order)]
                case .captureDate: return [KeyPathComparator(\PhotoGroup.fileDate, order: order)]
                case .type: return [KeyPathComparator(\PhotoGroup.typeLabel, order: order)]
                case .size: return [KeyPathComparator(\PhotoGroup.fileSize, order: order)]
                }
            },
            set: { new in
                guard let clicked = new.first?.keyPath else { return }
                if clicked == \PhotoGroup.displayName { app.cycleSort(.filename) }
                else if clicked == \PhotoGroup.fileDate { app.cycleSort(.captureDate) }
                else if clicked == \PhotoGroup.typeLabel { app.cycleSort(.type) }
                else if clicked == \PhotoGroup.fileSize { app.cycleSort(.size) }
            }
        )
    }

    private var selection: Binding<Set<String>> {
        Binding(get: { app.selectedIDs }, set: { app.selectFromList($0) })
    }

    var body: some View {
        ScrollViewReader { proxy in
            Table(app.filteredGroups, selection: selection, sortOrder: sortOrder) {
                TableColumn("") { g in
                    if g.mark != 0 { MarkBadge(mark: g.mark, size: 11) }
                }
                .width(18)

                TableColumn("Name", value: \.displayName) { g in
                    HStack(spacing: 8) {
                        ListThumbnail(url: g.previewURL)
                        Text(g.displayName).lineLimit(1).truncationMode(.middle)
                    }
                }
                .width(min: 180, ideal: 280)

                TableColumn("Erstellungsdatum", value: \.fileDate) { g in
                    Text(Self.dateText(g.fileDate)).foregroundStyle(.secondary).monospacedDigit()
                }
                .width(min: 120, ideal: 150)

                TableColumn("Typ", value: \.typeLabel) { g in
                    Text(g.typeLabel).foregroundStyle(.secondary)
                }
                .width(min: 60, ideal: 80)

                TableColumn("Grösse", value: \.fileSize) { g in
                    Text(ByteCountFormatter.string(fromByteCount: Int64(g.fileSize), countStyle: .file))
                        .foregroundStyle(.secondary).monospacedDigit()
                }
                .width(min: 60, ideal: 80)
            }
            .contextMenu(forSelectionType: String.self) { _ in
                // Same as the toolbar: Teilen (app, Google Drive, Finder), then Kopieren.
                Button(app.openWithButtonTitle) { app.openSelectionInExternalApp() }
                Button("An Google Drive senden") { app.sendToGoogleDrive(marked: false) }
                Button("Im Finder anzeigen") { app.revealCurrent() }
                Divider()
                Button("Kopieren…") { app.copySelection() }
            } primaryAction: { ids in
                if let id = ids.first { app.selectSingle(id); app.viewMode = .loupe }
            }
            .onChange(of: app.currentID) { _, id in
                if let id { proxy.scrollTo(id) }
            }
            // Re-sorting does NOT follow the selected photo here (unlike the grid): the list stays
            // where it was scrolled, like the Finder. The arrow keys bring the selection back.
            .onAppear {
                guard let id = app.currentID else { return }
                DispatchQueue.main.async { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private static func dateText(_ date: Date) -> String {
        date == .distantPast ? "–" : date.formatted(date: .numeric, time: .shortened)
    }
}

/// The tiny preview in a list row, from the same cache as the grid (no extra decode when warm).
private struct ListThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        let shown = image ?? ThumbnailLoader.shared.cached(for: url, maxPixel: PreviewConfig.tinyMaxPixel)
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: .quaternaryLabelColor).opacity(0.35))
            if let shown {
                Image(nsImage: shown).resizable().interpolation(.medium).aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: 26, height: 20)
        .task(id: url) {
            if image == nil { image = await ThumbnailLoader.shared.thumbnail(for: url, maxPixel: PreviewConfig.tinyMaxPixel) }
        }
    }
}
