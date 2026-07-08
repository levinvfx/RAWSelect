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
    @State private var image: NSImage?
    @State private var isSharp = false
    @State private var metadata = PhotoMetadata()

    var body: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor).opacity(0.4)
            if let image {
                // Two-stage preview: never a spinner. Instant (soft) shows first,
                // then Perfect swaps in directly (no fade) for fast browsing.
                Image(nsImage: image)
                    .resizable()
                    .interpolation(isSharp ? .high : .medium)
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
        .task(id: group.id) {
            let loader = ThumbnailLoader.shared
            // Size-aware plan: RAW → small embedded preview; small sharp JPEG/HEIC
            // → original, untouched; big files → downscaled. See ThumbnailLoader.
            let plan = loader.previewPlan(for: group.previewURL, targetLongEdge: settings.perfectPixels)

            // 1) SYNCHRONOUS cache read → paint the frame instantly, *before* any
            //    await. Because it runs before a suspension point it still happens
            //    even when this task is cancelled a moment later (holding ←/→). So
            //    every already-cached image in the strip actually shows, like a
            //    flip-book – no dropped in-between frames, no per-image lag.
            if let perfect = loader.cached(for: group.previewURL, maxPixel: plan.maxPixel, fullQuality: plan.fullQuality) {
                image = perfect
                isSharp = true
                return
            }
            var shown = false
            if let instant = loader.cached(for: group.previewURL, maxPixel: settings.instantPixels) {
                image = instant
                isSharp = false
                shown = true
            }

            // 2) Not cached at HD yet: decode asynchronously. The previous frame
            //    stays visible until the new one is ready (no black flash).
            if !shown, let instant = await loader.thumbnail(for: group.previewURL, maxPixel: settings.instantPixels) {
                image = instant
                isSharp = false
            }
            // 3) Perfect preview per the plan (native & sharp for small files,
            //    downscaled for big ones, embedded preview for RAW).
            if let perfect = await loader.thumbnail(for: group.previewURL, maxPixel: plan.maxPixel, fullQuality: plan.fullQuality) {
                image = perfect
                isSharp = true
            }
        }
        .task(id: group.id) {
            let url = group.files.first ?? group.previewURL
            metadata = await Task.detached { MetadataService.metadata(for: url) }.value
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
