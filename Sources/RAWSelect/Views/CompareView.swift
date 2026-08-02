import SwiftUI

/// Side-by-side A|B comparison for picking the sharpest frame from a burst. The left pane is
/// the anchor (the current photo); ←/→ cycle the right pane through the series. Zoom is driven
/// from the keyboard/buttons and mirrored to both panes (see `AppState.compareZoomBoth`), so a
/// 100% check happens on both at once. Pan is per-pane in this version.
struct CompareView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        Group {
            if let left = app.currentGroup, let right = app.compareRightGroup {
                HStack(spacing: 2) {
                    ComparePane(group: left, zoom: app.compareZoomL, label: "A")
                    Rectangle().fill(Color.black).frame(width: 2)
                    ComparePane(group: right, zoom: app.compareZoomR, label: "B")
                }
            } else {
                VStack(spacing: 8) {
                    Text("Zum Vergleichen mindestens zwei Bilder nötig.")
                        .foregroundStyle(.secondary)
                    Button("Zurück") { app.exitCompare() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .overlay(alignment: .bottom) {
            Text("←/→ rechtes Bild · Z 100% · ↩ B→A übernehmen · Esc schliessen")
                .font(.caption)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 12)
        }
    }
}

/// One pane of the compare view: shows a sharp preview of `group`, upgrades to the full-res
/// decode while zoomed, and reports zoom through its own `ZoomController`.
private struct ComparePane: View {
    @EnvironmentObject var settings: AppSettings
    let group: PhotoGroup
    @ObservedObject var zoom: ZoomController
    let label: String

    @State private var image: NSImage?
    @State private var hiRes: NSImage?
    @State private var hiResID: String?
    @State private var hiResTask: Task<Void, Never>?

    private var rawURL: URL { group.files.first { PhotoTypes.isRaw($0) } ?? group.previewURL }

    var body: some View {
        ZStack {
            Color(white: 0.11)
            if let shown = (hiResID == group.id ? hiRes : nil) ?? image {
                ZoomableImageView(imageID: group.id, image: shown, controller: zoom)
                    .padding(8)
            } else {
                ProgressView().controlSize(.small)
            }
            VStack {
                HStack(alignment: .top) {
                    Text("\(label) · \(group.displayName)")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1).truncationMode(.middle)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(.regularMaterial, in: Capsule())
                    Spacer()
                    if group.mark != 0 {
                        HStack(spacing: 5) {
                            Circle().fill(settings.markColor(group.mark)).frame(width: 10, height: 10)
                            Text(settings.markName(group.mark)).font(.caption.weight(.medium))
                        }
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(.regularMaterial, in: Capsule())
                    }
                }
                Spacer()
            }
            .padding(10)
        }
        .task(id: group.id) {
            let loader = ThumbnailLoader.shared
            let plan = loader.previewPlan(for: group.previewURL, targetLongEdge: settings.perfectPixels)
            image = await loader.thumbnail(for: group.previewURL, maxPixel: plan.maxPixel, fullQuality: plan.fullQuality)
        }
        .onChange(of: group.id) { _, _ in
            hiResTask?.cancel(); hiRes = nil; hiResID = nil
            if zoom.zoomed { loadHiRes() }
        }
        .onReceive(zoom.$zoomed) { zoomedIn in
            if zoomedIn, hiResID != group.id { loadHiRes() }
        }
        .onDisappear { hiResTask?.cancel() }
    }

    private func loadHiRes() {
        let g = group
        hiResTask?.cancel()
        hiResTask = Task {
            let big = await ThumbnailLoader.shared.fullDecode(for: rawURL, maxPixel: PreviewConfig.zoomMaxPixel)
            await MainActor.run {
                guard group.id == g.id, let big else { return }
                hiRes = big; hiResID = g.id
            }
        }
    }
}
