import SwiftUI
import Combine

/// Large preview of the selected photo with a filmstrip below.
struct LoupeView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            if let group = app.currentGroup {
                // No .id() here: the view must PERSIST across image changes so the
                // previous frame stays visible until the next preview is ready
                // (prevents a black flash when browsing quickly).
                LargePreview(group: group)
            } else {
                Color(nsColor: .windowBackgroundColor)
            }
            // Distraction-free viewing (Return) hides the strip; Escape restores it.
            if !app.focusMode {
                Divider()
                Filmstrip()
                    .frame(height: 120)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct LargePreview: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: AppSettings
    let group: PhotoGroup
    @State private var version = 0            // bumped when an async upgrade lands
    @State private var lastGood: NSImage?     // last shown image → never a black frame
    @State private var metadata = PhotoMetadata()
    @State private var hiRes: NSImage?        // higher-res image loaded on zoom-in
    @State private var hiResID: String?       // which photo hiRes belongs to

    /// Best preview available *right now*, read straight from the in-memory cache.
    /// This is called synchronously from `body`, so switching photos NEVER waits on
    /// a task and can never drop a frame. `warmTiny` pre-caches a tiny thumbnail for
    /// every photo, so there is essentially always something to show instantly.
    private func bestCached() -> (image: NSImage, sharp: Bool)? {
        let loader = ThumbnailLoader.shared
        let url = group.previewURL
        let plan = loader.previewPlan(for: url, targetLongEdge: settings.perfectPixels)
        if let p = loader.cached(for: url, maxPixel: plan.maxPixel, fullQuality: plan.fullQuality) { return (p, true) }
        if let i = loader.cached(for: url, maxPixel: settings.instantPixels) { return (i, false) }
        if let t = loader.cached(for: url, maxPixel: PreviewConfig.tinyMaxPixel) { return (t, false) }
        return nil
    }

    var body: some View {
        let _ = version                       // depend on `version` so upgrades re-render
        let best = bestCached()
        let display = best?.image ?? lastGood  // fall back to previous frame, never black
        return ZStack {
            // Neutral dark surround like the crop editor – keeps the eye on the
            // photo and stays consistent across the app.
            Color(white: 0.11)
            if let shown = (hiResID == group.id ? hiRes : nil) ?? display {
                ZoomableImageView(imageID: group.id, image: shown, controller: app.zoom)
                    .padding(16)
            }

            VStack {
                HStack(alignment: .top) {
                    if app.showInfo && settings.metadataPanel { infoOverlay }
                    Spacer()
                    if group.mark != 0 { markPill }
                }
                Spacer()
                HStack {
                    Spacer()
                    ZoomControls(zoom: app.zoom)
                }
            }
            .padding(16)

            // Zoom mode (space bar): vertical slider on the right.
            if app.zoom.sliderActive {
                HStack {
                    Spacer()
                    ZoomSlider(zoom: app.zoom)
                }
                .padding(.trailing, 20)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: app.zoom.sliderActive)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: group.id) { await upgrade() }
        .task(id: group.id) {
            let url = group.files.first ?? group.previewURL
            metadata = await Task.detached { MetadataService.metadata(for: url) }.value
        }
        .onReceive(app.zoom.$zoomed) { zoomedIn in if zoomedIn { loadHiRes() } }
    }

    /// On first zoom-in, fetch a higher-resolution image so the zoom stays sharp
    /// (full-res for JPG; for RAW only if a larger embedded preview exists). Loaded
    /// once per photo, cached by ThumbnailLoader, swapped in without a visual jump.
    private func loadHiRes() {
        if hiResID == group.id, hiRes != nil { return }
        let g = group
        let target = settings.perfectPixels
        Task {
            let url = g.previewURL
            let big = await ThumbnailLoader.shared.thumbnail(
                for: url, maxPixel: 6000, fullQuality: !PhotoTypes.isRaw(url))
            await MainActor.run {
                guard g.id == group.id, let big else { return }
                let px = max(big.representations.first?.pixelsWide ?? 0,
                             big.representations.first?.pixelsHigh ?? 0)
                if px > target + 8 { hiRes = big; hiResID = g.id }   // only swap if genuinely sharper
            }
        }
    }

    /// Decodes the missing (sharper) tiers in the background and bumps `version`
    /// so `body` re-reads the cache and swaps them in. The synchronous body read is
    /// what guarantees the instant, frame-accurate display; this just improves it.
    private func upgrade() async {
        let loader = ThumbnailLoader.shared
        let url = group.previewURL
        let plan = loader.previewPlan(for: url, targetLongEdge: settings.perfectPixels)
        // Remember whatever is on screen now as the no-black fallback.
        if let b = bestCached() { lastGood = b.image }
        // Already have the best tier → nothing to do.
        if loader.cached(for: url, maxPixel: plan.maxPixel, fullQuality: plan.fullQuality) != nil { return }
        // Quick soft tier first (fast to decode), then the sharp one.
        if loader.cached(for: url, maxPixel: settings.instantPixels) == nil {
            _ = await loader.thumbnail(for: url, maxPixel: settings.instantPixels)
            version &+= 1
        }
        _ = await loader.thumbnail(for: url, maxPixel: plan.maxPixel, fullQuality: plan.fullQuality)
        version &+= 1
    }

    private var markPill: some View {
        HStack(spacing: 6) {
            Circle().fill(settings.markColor(group.mark)).frame(width: 12, height: 12)
            Text(settings.markName(group.mark)).font(.callout.weight(.medium))
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
    }

    private var infoOverlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.displayName).font(.callout.weight(.semibold))
            Divider().padding(.vertical, 2)
            ForEach(metadata.rows, id: \.0) { row in
                HStack(spacing: 8) {
                    Text(row.0).foregroundStyle(.secondary).frame(width: 78, alignment: .leading)
                    Text(row.1)
                }
                .font(.caption.monospacedDigit())
            }
            if metadata.rows.isEmpty {
                Text("Keine EXIF-Daten").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .frame(maxWidth: 280, alignment: .leading)
    }

}

private struct Filmstrip: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 10) {
                    ForEach(app.filteredGroups) { group in
                        ThumbnailCell(group: group,
                                      isSelected: app.selectedIDs.contains(group.id),
                                      isCurrent: group.id == app.currentID,
                                      side: 84, showsCaption: false)
                            .id(group.id)
                            .contentShape(Rectangle())
                            .onTapGesture { app.click(group.id) }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .background(Color(nsColor: .underPageBackgroundColor))
            .onChange(of: app.currentID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }
}
