import SwiftUI
import AppKit

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
    @State private var zoomLevel: CGFloat = 2      // 1× = fit … maxZoom
    private let maxZoom: CGFloat = 8

    var body: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor).opacity(0.4)
            if let image {
                if app.loupeZoom {
                    // Native zoom: pinch/scroll magnifies at the cursor, scroll pans,
                    // and the slider drives the level. Great for sharpness/focus checks.
                    ZoomableImageView(image: image, zoom: $zoomLevel, maxZoom: maxZoom)
                } else {
                    // Two-stage preview: never a spinner. Instant (soft) shows first,
                    // then Perfect swaps in directly (no fade) for fast browsing.
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(isSharp ? .high : .medium)
                        .aspectRatio(contentMode: .fit)
                        .padding(16)
                }
            }

            VStack {
                HStack(alignment: .top) {
                    if app.showInfo && settings.metadataPanel { infoOverlay }
                    Spacer()
                    if group.mark != 0 { markPill }
                }
                Spacer()
                zoomControl
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { app.loupeZoom.toggle() }   // click image = zoom (space also works)
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

    /// Bottom bar: a hint chip when fitted, a zoom slider when zoomed in.
    @ViewBuilder private var zoomControl: some View {
        HStack {
            Spacer()
            if app.loupeZoom {
                HStack(spacing: 10) {
                    Button { app.loupeZoom = false } label: { Image(systemName: "arrow.down.right.and.arrow.up.left") }
                        .buttonStyle(.plain).help("Zoom beenden (Leertaste)")
                    Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
                    Slider(value: $zoomLevel, in: 1...maxZoom)
                        .frame(width: 180)
                    Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
                    Text("\(Int(zoomLevel * 100)) %").font(.caption.monospacedDigit())
                        .frame(width: 52, alignment: .trailing)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
            } else {
                Label("Zoom", systemImage: "plus.magnifyingglass")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
                    .opacity(0.85)
            }
        }
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

// MARK: - Zoomable image (native magnification + scroll-to-pan + zoom at cursor)

/// Wraps an `NSScrollView` so the loupe gets buttery, Apple-native zooming:
/// pinch/scroll magnifies at the pointer, scrolling pans, and the SwiftUI slider
/// drives the magnification (centred on the last cursor position).
private struct ZoomableImageView: NSViewRepresentable {
    let image: NSImage
    @Binding var zoom: CGFloat
    let maxZoom: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.allowsMagnification = true
        scroll.minMagnification = 1
        scroll.maxMagnification = maxZoom
        scroll.drawsBackground = false
        scroll.contentView.postsBoundsChangedNotifications = true

        let iv = TrackingImageView()
        iv.image = image
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.imageAlignment = .alignCenter
        iv.autoresizingMask = [.width, .height]
        iv.onMouseMoved = { [weak coordinator = context.coordinator] p in coordinator?.lastMouse = p }
        scroll.documentView = iv

        context.coordinator.scroll = scroll
        NotificationCenter.default.addObserver(context.coordinator,
            selector: #selector(Coordinator.liveMagnifyEnded),
            name: NSScrollView.didEndLiveMagnifyNotification, object: scroll)

        DispatchQueue.main.async {
            iv.frame = scroll.contentView.bounds
            scroll.magnification = zoom
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        if let iv = scroll.documentView as? NSImageView, iv.image !== image { iv.image = image }
        // Slider (or programmatic) change → magnify, centred on the pointer.
        if abs(scroll.magnification - zoom) > 0.001 {
            let center = context.coordinator.lastMouse
                ?? CGPoint(x: scroll.contentView.bounds.midX, y: scroll.contentView.bounds.midY)
            scroll.setMagnification(zoom, centeredAt: center)
        }
    }

    final class Coordinator: NSObject {
        let parent: ZoomableImageView
        weak var scroll: NSScrollView?
        var lastMouse: CGPoint?
        init(_ parent: ZoomableImageView) { self.parent = parent }

        @objc func liveMagnifyEnded() {
            guard let scroll else { return }
            parent.zoom = scroll.magnification
        }
    }
}

/// NSImageView that forwards mouse-move locations (in its own coordinates).
private final class TrackingImageView: NSImageView {
    var onMouseMoved: ((CGPoint) -> Void)?
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        onMouseMoved?(convert(event.locationInWindow, from: nil))
    }
}
