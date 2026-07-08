import SwiftUI

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
        let sharp = best?.sharp ?? false
        return ZStack {
            Color(nsColor: .textBackgroundColor).opacity(0.4)
            if let display {
                Image(nsImage: display)
                    .resizable()
                    .interpolation(sharp ? .high : .medium)
                    .aspectRatio(contentMode: .fit)
                    .padding(16)
            }

            VStack {
                HStack(alignment: .top) {
                    if app.showInfo && settings.metadataPanel { infoOverlay }
                    Spacer()
                    if group.mark != 0 { markPill }
                }
                Spacer()
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: group.id) { await upgrade() }
        .task(id: group.id) {
            let url = group.files.first ?? group.previewURL
            metadata = await Task.detached { MetadataService.metadata(for: url) }.value
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
