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
    @State private var hiRes: NSImage?        // full-res image loaded on zoom-in
    @State private var hiResID: String?       // which photo hiRes belongs to
    @State private var isLoadingHiRes = false // shows the "RAW lädt…" indicator
    @State private var hiResTask: Task<Void, Never>?  // cancellable full-res decode
    @State private var loadingID: String?     // photo whose full-res decode is in flight
    @State private var attemptedID: String?   // photo already tried once (no reload-spam)
    /// Photo that could not be decoded at all. Without this, `lastGood` kept the PREVIOUS
    /// photo on screen under this one's file name and mark pill — so a corrupt RAW looked
    /// like a perfectly good frame and got culled blind.
    @State private var failedID: String?
    /// Full-res decodes kept warm: the photo on screen plus the NEXT one in stepping direction,
    /// pre-developed while zoomed. Hard cap 2 — a developed RAW is 100+ MB. Checking a burst at
    /// 100 % used to restart a cold 12 000-px decode on every single step.
    @State private var hiResStore: [(id: String, image: NSImage)] = []
    @State private var neighborTask: Task<NSImage?, Never>?
    @State private var neighborID: String?

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
        let broken = failedID == group.id
        // Carry the previous frame over WHILE LOADING (no black flash) — but never once we
        // know this photo can't be decoded, or the user judges the wrong picture.
        let display = broken ? nil : (best?.image ?? lastGood)
        return ZStack {
            // Neutral dark surround like the crop editor – keeps the eye on the
            // photo and stays consistent across the app.
            Color(white: 0.11)
            if let shown = (hiResID == group.id ? hiRes : nil) ?? display {
                ZoomableImageView(imageID: group.id, image: shown, controller: app.zoom)
                    .padding(16)
            } else if broken {
                brokenNotice
            }

            VStack {
                HStack(alignment: .top) {
                    if app.showInfo { infoOverlay }
                    Spacer()
                    if group.mark != 0 { markPill }
                }
                Spacer()
                if app.zoom.zoomed && !app.zoom.sliderActive {
                    HStack {
                        Spacer()
                        ZoomControls(zoom: app.zoom)
                    }
                    .transition(.opacity)
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
        .animation(.easeOut(duration: 0.15), value: app.zoom.zoomed)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            if isLoadingHiRes && app.zoom.zoomed {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("RAW lädt…").font(.caption.weight(.medium))
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(.regularMaterial, in: Capsule())
                .padding(.top, 16)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isLoadingHiRes)
        .task(id: group.id) { await upgrade() }
        // EXIF is read only while the overlay is on — it was one extra file read per photo on
        // every step through a series, even with the overlay hidden (I/O on the card).
        .task(id: "\(group.id)|\(app.showInfo)") {
            guard app.showInfo else { return }
            let url = group.files.first ?? group.previewURL
            metadata = await Task.detached { MetadataService.metadata(for: url) }.value
        }
        // Load the full-res RAW on zoom-in. Do NOT release on zoom-out: keep it for
        // this photo so re-zooming is instant and never re-shows "RAW lädt…".
        .onReceive(app.zoom.$zoomed) { zoomedIn in
            if zoomedIn { loadHiRes() }
        }
        // Free the full-res RAW (and cancel any in-flight decode) only when the
        // photo actually changes — so only ever one RAW is held in memory.
        // If the zoom is being HELD across photos, immediately develop the new one to sharp
        // too (the `$zoomed` edge won't fire again because it never dropped to false).
        .onChange(of: group.id) { _, _ in
            releaseHiRes()
            if app.zoom.zoomed { loadHiRes() }
        }
    }

    /// On zoom-in, develop the actual RAW at native resolution so the zoom is
    /// razor-sharp to the pixel — instead of upscaling the on-screen preview. For a
    /// RAW+JPG pair this decodes the RAW file (not the JPG). Runs ONLY while zoomed,
    /// one image at a time, uncached; swapped in without a visual jump and freed
    /// again on zoom-out so browsing stays light. See `releaseHiRes()`.
    private func loadHiRes() {
        if hiResID == group.id, hiRes != nil { return }   // already sharp for this photo
        // Pre-developed while we were on the previous photo → instant, no "RAW lädt…".
        if let hit = hiResStore.first(where: { $0.id == group.id }) {
            hiRes = hit.image; hiResID = group.id
            prefetchNeighborHiRes()
            return
        }
        if attemptedID == group.id { return }             // already tried once → don't retry
        if loadingID == group.id { return }               // already decoding this photo →
                                                          // ignore the per-frame zoom events
                                                          // (otherwise every frame cancels
                                                          // and restarts the decode).
        hiResTask?.cancel()
        let g = group
        let shownPx = bestCached().map { pixelCount($0.image) } ?? 0
        let url = app.rawURL(for: g)                       // the RAW file if present
        loadingID = g.id
        isLoadingHiRes = true
        // If the neighbour pre-decode is already working on exactly this photo, wait for it
        // instead of starting a second 100-MB decode of the same file.
        let pending: Task<NSImage?, Never>? = (neighborID == g.id) ? neighborTask : nil
        hiResTask = Task {
            // Develops the RAW, or (if the OS lacks a codec, e.g. A7 V) falls back to
            // the largest embedded preview inside fullDecode.
            let big: NSImage?
            if let pending { big = await pending.value }
            else { big = await ThumbnailLoader.shared.fullDecode(for: url, maxPixel: PreviewConfig.zoomMaxPixel) }
            await MainActor.run {
                guard loadingID == g.id else { return }    // superseded or released
                loadingID = nil
                isLoadingHiRes = false
                attemptedID = g.id                         // one attempt per photo → no reload-spam
                guard let big else { return }              // decode failed entirely
                if pixelCount(big) > shownPx { hiRes = big; hiResID = g.id; remember(g.id, big) }  // only if genuinely sharper
                prefetchNeighborHiRes()
            }
        }
    }

    private func remember(_ id: String, _ image: NSImage) {
        hiResStore.removeAll { $0.id == id }
        hiResStore.append((id, image))
        // Evict the oldest entry that is not the photo on screen.
        while hiResStore.count > 2, let i = hiResStore.firstIndex(where: { $0.id != group.id }) {
            hiResStore.remove(at: i)
        }
    }

    /// Develops the next RAW in stepping direction while the user still looks at this one.
    private func prefetchNeighborHiRes() {
        guard app.zoom.zoomed,
              let nid = app.neighborID(of: group.id, direction: app.lastStepDirection),
              nid != neighborID,
              !hiResStore.contains(where: { $0.id == nid }),
              let ng = app.group(nid) else { return }
        neighborTask?.cancel()
        neighborID = nid
        let url = app.rawURL(for: ng)
        neighborTask = Task {
            let img = await ThumbnailLoader.shared.fullDecode(for: url, maxPixel: PreviewConfig.zoomMaxPixel)
            await MainActor.run {
                if let img { remember(nid, img) }
                if neighborID == nid { neighborID = nil; neighborTask = nil }
            }
            return img
        }
    }

    /// Longest pixel edge of an image (0 if unknown).
    private func pixelCount(_ img: NSImage) -> Int {
        max(img.representations.first?.pixelsWide ?? 0, img.representations.first?.pixelsHigh ?? 0)
    }

    /// Cancels any in-flight full-res decode and drops the on-screen full-res image when the
    /// photo changes. The small `hiResStore` (current + pre-developed neighbour) is kept so
    /// stepping through a burst at 100 % stays instant; it is capped at two entries.
    private func releaseHiRes() {
        hiResTask?.cancel()
        hiResTask = nil
        loadingID = nil
        attemptedID = nil
        isLoadingHiRes = false
        hiRes = nil
        hiResID = nil
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
            if Task.isCancelled { return }
            version &+= 1
        }
        let sharp = await loader.thumbnail(for: url, maxPixel: plan.maxPixel, fullQuality: plan.fullQuality)
        // Moved on while decoding: a cancelled decode returns nil, which must NOT brand this
        // (perfectly fine) photo as unreadable — that is how healthy frames got culled blind.
        if Task.isCancelled { return }
        version &+= 1
        // Nothing decoded at any tier → this file is unreadable. Say so instead of leaving
        // the previous photo on screen pretending to be this one.
        if sharp == nil, bestCached() == nil {
            failedID = group.id
            lastGood = nil
        } else if failedID == group.id {
            failedID = nil            // decoded on a later visit → clear the stale failure flag
        }
    }

    private var brokenNotice: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34)).foregroundStyle(.orange)
            Text("Bild kann nicht gelesen werden").font(.callout.weight(.medium))
            Text(group.displayName).font(.caption).foregroundStyle(.secondary)
        }
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
                // Lazy: with thousands of photos only the visible strip cells are
                // built & decoded, instead of instantiating every cell at once.
                LazyHStack(spacing: 10) {
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
            .background(Color(white: 0.14))   // neutral, consistent with the loupe surround
            .onChange(of: app.currentID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }
}
