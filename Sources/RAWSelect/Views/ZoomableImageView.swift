import SwiftUI
import AppKit

/// Zoom/percent state shared between the loupe UI (buttons, keyboard) and the
/// AppKit scroll view. Commands are forwarded to the live view via `command`.
final class ZoomController: ObservableObject {
    /// Current zoom as a percentage of the image's native pixel size.
    @Published var percent: Int = 100
    /// True while zoomed in past the fit-to-window level (enables panning).
    @Published var zoomed: Bool = false
    /// Zoom mode (toggled with the space bar): shows the vertical zoom slider.
    @Published var sliderActive: Bool = false
    /// Slider position, 0 = fit … 1 = maximum magnification.
    @Published var fraction: Double = 0
    /// Normalised centre (0…1 in image coordinates) of what is visible, reported by the live
    /// view while panning/zooming. Compare A|B mirrors it between the two panes.
    @Published var viewCenter = CGPoint(x: 0.5, y: 0.5)

    enum Command { case zoomIn, zoomOut, toggle100, fit, zoomTo100, spaceToggle, setFraction(Double), centerOn(CGPoint) }
    var command: ((Command) -> Void)?
    func centerOn(_ c: CGPoint) { command?(.centerOn(c)) }

    func zoomIn()    { command?(.zoomIn) }
    func zoomOut()   { command?(.zoomOut) }
    func toggle100() { command?(.toggle100) }
    func fit()       { command?(.fit) }
    func setFraction(_ f: Double) { fraction = f; command?(.setFraction(f)) }

    /// Space bar: native ⇄ fit toggle. At native (100%) → fit; from fit OR any other
    /// magnification (e.g. pinched) → native. The live view decides from the exact
    /// magnification and updates `sliderActive` accordingly.
    func spaceToggle() { command?(.spaceToggle) }

    /// Leave zoom mode (used by Escape): hide slider and fit.
    func setZoomMode(_ on: Bool) {
        sliderActive = on
        command?(on ? .zoomTo100 : .fit)
    }
}

/// A smooth, native pan/zoom image view backed by `NSScrollView`. Trackpad pinch,
/// scroll-to-zoom and drag-pan come for free from AppKit; buttons/keys route
/// through `ZoomController`. `imageID` identifies the photo: a change resets to
/// fit, while a mere sharper re-decode of the same photo keeps the zoom.
struct ZoomableImageView: NSViewRepresentable {
    let imageID: String
    let image: NSImage
    @ObservedObject var controller: ZoomController

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeNSView(context: Context) -> ZoomScrollView {
        let scroll = ZoomScrollView()
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.allowsMagnification = true
        scroll.maxMagnification = 8
        scroll.minMagnification = 0.02
        scroll.drawsBackground = false
        scroll.contentView = CenteringClipView()

        let iv = NSImageView()
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.imageAlignment = .alignCenter
        iv.animates = false
        iv.wantsLayer = true          // GPU-composited → smooth pan even for big images
        scroll.documentView = iv

        let coord = context.coordinator
        coord.scroll = scroll
        coord.imageView = iv
        scroll.onLayout = { [weak coord] in coord?.layoutTick() }
        scroll.onWheelZoom = { [weak coord] factor, point in
            coord?.wheelZoom(by: factor, anchorWindowPoint: point)
        }
        controller.command = { [weak coord] cmd in coord?.handle(cmd) }
        NotificationCenter.default.addObserver(
            coord, selector: #selector(Coordinator.magnifyEnded(_:)),
            name: NSScrollView.didEndLiveMagnifyNotification, object: scroll)
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            coord, selector: #selector(Coordinator.boundsChanged(_:)),
            name: NSView.boundsDidChangeNotification, object: scroll.contentView)

        // Click-and-drag to pan (hand tool), in addition to trackpad scrolling.
        let pan = NSPanGestureRecognizer(target: coord, action: #selector(Coordinator.handlePan(_:)))
        iv.addGestureRecognizer(pan)

        coord.setImage(image, id: imageID, resetToFit: true)
        return scroll
    }

    func updateNSView(_ scroll: ZoomScrollView, context: Context) {
        let coord = context.coordinator
        controller.command = { [weak coord] cmd in coord?.handle(cmd) }
        if coord.currentID != imageID {
            // Photo change: refit as usual — UNLESS the loupe is currently zoomed in, then hold
            // the same magnification and centre so a burst can be checked at the AF point while
            // stepping (Photo-Mechanic-style). Escape/Space still return to fit.
            coord.setImage(image, id: imageID, resetToFit: !controller.zoomed)
        } else if coord.currentImage !== image {
            coord.setImage(image, id: imageID, resetToFit: false)  // sharper re-decode → keep zoom
        }
    }

    static func dismantleNSView(_ scroll: ZoomScrollView, coordinator: Coordinator) {
        coordinator.animTimer?.invalidate()
        NotificationCenter.default.removeObserver(coordinator)
    }

    final class Coordinator: NSObject {
        let controller: ZoomController
        weak var scroll: ZoomScrollView?
        weak var imageView: NSImageView?
        var currentImage: NSImage?
        var currentID: String?
        private var pendingFit = false
        var animTimer: Timer?

        init(controller: ZoomController) { self.controller = controller }

        func setImage(_ img: NSImage, id: String, resetToFit: Bool) {
            animTimer?.invalidate(); animTimer = nil
            guard let scroll, let imageView else { currentImage = img; currentID = id; return }

            // Capture the current on-screen scale + centre so a mere resolution
            // swap (preview → hi-res) doesn't visually jump.
            let oldFrame = imageView.frame
            let oldMag = scroll.magnification
            var normCenter = CGPoint(x: 0.5, y: 0.5)
            if oldFrame.width > 1, oldFrame.height > 1 {
                let vis = scroll.contentView.bounds
                normCenter = CGPoint(x: min(max(vis.midX / oldFrame.width, 0), 1),
                                     y: min(max(vis.midY / oldFrame.height, 0), 1))
            }

            currentImage = img
            currentID = id
            let newSize = pixelSize(img)
            imageView.image = img
            imageView.frame = NSRect(origin: .zero, size: newSize)

            if resetToFit || oldFrame.width < 2 {
                pendingFit = true
                layoutTick()
                return
            }

            // Same photo, replacement image → preserve visual scale and centre.
            let newFit = fitMagnification()
            scroll.minMagnification = newFit
            let targetMag = oldMag * (oldFrame.width / newSize.width)
            scroll.magnification = max(newFit, min(scroll.maxMagnification, targetMag))
            let centerDoc = CGPoint(x: normCenter.x * newSize.width, y: normCenter.y * newSize.height)
            let vis = scroll.contentView.bounds.size
            scroll.contentView.scroll(to: NSPoint(x: centerDoc.x - vis.width / 2,
                                                  y: centerDoc.y - vis.height / 2))
            scroll.reflectScrolledClipView(scroll.contentView)
            updatePercent()
        }

        private func pixelSize(_ img: NSImage) -> NSSize {
            if let rep = img.representations.first, rep.pixelsWide > 0 {
                return NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
            }
            return img.size
        }

        /// Called when the scroll view first gets a real size (or on demand).
        func layoutTick() {
            guard pendingFit, let scroll, scroll.bounds.width > 1, scroll.bounds.height > 1 else { return }
            pendingFit = false
            fitInstant()
        }

        private func fitMagnification() -> CGFloat {
            guard let scroll, let doc = scroll.documentView else { return 1 }
            // The clip view's FRAME is the fixed viewport in points; its BOUNDS
            // scale with magnification (so must NOT be used to compute fit).
            let cs = scroll.contentView.frame.size
            let ds = doc.frame.size                      // image pixel size
            guard ds.width > 0, ds.height > 0, cs.width > 0, cs.height > 0 else { return 1 }
            return min(cs.width / ds.width, cs.height / ds.height)
        }

        func fitInstant() {
            guard let scroll else { return }
            let m = fitMagnification()
            scroll.minMagnification = m
            scroll.magnification = m
            recenter()
            updatePercent()
        }

        /// Current mouse position in window coords, or nil if it's not over the
        /// image (then zoom falls back to centring on the viewport).
        private func currentMouseWindowPoint() -> NSPoint? {
            guard let scroll, let win = scroll.window else { return nil }
            let winPt = win.convertPoint(fromScreen: NSEvent.mouseLocation)
            let inScroll = scroll.convert(winPt, from: nil)
            return scroll.bounds.contains(inScroll) ? winPt : nil
        }

        /// Smoothly animates the magnification, keeping the anchor point (the
        /// mouse, if given) pinned under the cursor throughout — otherwise it
        /// zooms around the centre.
        private func animateMagnification(to target: CGFloat, anchorWindowPoint wp: NSPoint?,
                                          duration: TimeInterval = 0.22) {
            guard let scroll else { return }
            animTimer?.invalidate()
            scroll.minMagnification = fitMagnification()
            let start = scroll.magnification
            let end = max(scroll.minMagnification, min(scroll.maxMagnification, target))
            if abs(end - start) < 0.0001 { scroll.magnification = end; recenter(); updatePercent(); return }

            let viewport = scroll.contentView.frame            // fixed, points
            var anchorDoc: NSPoint?
            var fx: CGFloat = 0.5, fy: CGFloat = 0.5
            if let wp, let doc = scroll.documentView, viewport.width > 0, viewport.height > 0 {
                anchorDoc = doc.convert(wp, from: nil)
                let p = scroll.convert(wp, from: nil)
                fx = min(max((p.x - viewport.minX) / viewport.width, 0), 1)
                fy = min(max((p.y - viewport.minY) / viewport.height, 0), 1)
            }

            let startTime = CACurrentMediaTime()
            animTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] t in
                guard let self, let scroll = self.scroll else { t.invalidate(); return }
                let progress = min((CACurrentMediaTime() - startTime) / duration, 1)
                let eased = 1 - pow(1 - progress, 3)              // ease-out cubic
                let m = start + (end - start) * CGFloat(eased)
                scroll.magnification = m
                if let a = anchorDoc {
                    let visW = viewport.width / m, visH = viewport.height / m
                    scroll.contentView.scroll(to: NSPoint(x: a.x - fx * visW, y: a.y - fy * visH))
                    scroll.reflectScrolledClipView(scroll.contentView)
                }
                self.updatePercent()
                if progress >= 1 { t.invalidate(); self.animTimer = nil }
            }
        }

        /// One mouse-wheel step: instant, anchored under the pointer. Deliberately NOT animated —
        /// a wheel fires a rapid burst of ticks, and animating each one would make them fight
        /// each other and feel laggy instead of direct.
        func wheelZoom(by factor: CGFloat, anchorWindowPoint wp: NSPoint) {
            guard let scroll else { return }
            animTimer?.invalidate(); animTimer = nil
            scroll.minMagnification = fitMagnification()
            let start = scroll.magnification
            let end = max(scroll.minMagnification, min(scroll.maxMagnification, start * factor))
            guard abs(end - start) > 0.00001 else { return }

            let viewport = scroll.contentView.frame           // fixed viewport, in points
            if let doc = scroll.documentView, viewport.width > 0, viewport.height > 0 {
                let anchorDoc = doc.convert(wp, from: nil)
                let p = scroll.convert(wp, from: nil)
                let fx = min(max((p.x - viewport.minX) / viewport.width, 0), 1)
                let fy = min(max((p.y - viewport.minY) / viewport.height, 0), 1)
                scroll.magnification = end
                let visW = viewport.width / end, visH = viewport.height / end
                scroll.contentView.scroll(to: NSPoint(x: anchorDoc.x - fx * visW, y: anchorDoc.y - fy * visH))
                scroll.reflectScrolledClipView(scroll.contentView)
            } else {
                scroll.magnification = end
                recenter()
            }
            updatePercent()
        }

        private func recenter() {
            guard let scroll, let doc = scroll.documentView else { return }
            let mid = NSPoint(x: doc.frame.midX, y: doc.frame.midY)
            let vis = scroll.contentView.bounds.size
            scroll.contentView.scroll(to: NSPoint(x: mid.x - vis.width / 2, y: mid.y - vis.height / 2))
            scroll.reflectScrolledClipView(scroll.contentView)
        }

        func handle(_ cmd: ZoomController.Command) {
            guard let scroll else { return }
            switch cmd {
            case .zoomIn:  setMagnification(scroll.magnification * 1.5)
            case .zoomOut: setMagnification(scroll.magnification / 1.5)
            case .fit:     animateMagnification(to: fitMagnification(), anchorWindowPoint: nil)
            case .zoomTo100:
                animateMagnification(to: 1.0, anchorWindowPoint: currentMouseWindowPoint())
            case .toggle100:
                if abs(scroll.magnification - 1.0) < 0.01 {
                    animateMagnification(to: fitMagnification(), anchorWindowPoint: nil)
                } else {
                    animateMagnification(to: 1.0, anchorWindowPoint: currentMouseWindowPoint())
                }
            case .spaceToggle:
                // Only from the fitted (unzoomed) state does space zoom IN to 100%.
                // From ANY zoomed-in state — manual/trackpad, intermediate, or exactly
                // 100% — it always zooms OUT to fit. Never zooms further in when already
                // zoomed. (Same "zoomed" threshold as updatePercent.)
                let fitM = fitMagnification()
                if scroll.magnification > fitM + 0.001 {   // already zoomed in → out to fit
                    controller.sliderActive = false
                    animateMagnification(to: fitM, anchorWindowPoint: nil)
                } else {                                    // at fit → in to native 100%
                    controller.sliderActive = true
                    animateMagnification(to: 1.0, anchorWindowPoint: currentMouseWindowPoint())
                }
            case .centerOn(let c): centerOn(c)
            case .setFraction(let f):
                let fitM = fitMagnification()
                let maxM = scroll.maxMagnification
                guard maxM > fitM else { return }
                setMagnification(fitM * pow(maxM / fitM, CGFloat(f)))   // perceptually even
            }
        }

        private func setMagnification(_ target: CGFloat) {
            guard let scroll else { return }
            let clamped = max(scroll.minMagnification, min(scroll.maxMagnification, target))
            let center = NSPoint(x: scroll.contentView.bounds.midX, y: scroll.contentView.bounds.midY)
            scroll.setMagnification(clamped, centeredAt: center)
            updatePercent()
        }

        @objc func handlePan(_ g: NSPanGestureRecognizer) {
            guard let scroll else { return }
            let clip = scroll.contentView
            switch g.state {
            case .began: NSCursor.closedHand.push()
            case .ended, .cancelled, .failed: NSCursor.pop()
            default: break
            }
            let t = g.translation(in: clip)          // in document (scaled) coords
            var origin = clip.bounds.origin
            origin.x -= t.x
            origin.y -= t.y
            clip.scroll(to: origin)
            scroll.reflectScrolledClipView(clip)
            g.setTranslation(.zero, in: clip)
        }

        @objc func magnifyEnded(_ n: Notification) { updatePercent() }

        private var suppressCenterReport = false

        /// Reports the visible centre so compare mode can pan the other pane along.
        @objc func boundsChanged(_ n: Notification) {
            guard !suppressCenterReport, let scroll, let doc = scroll.documentView,
                  doc.frame.width > 1, doc.frame.height > 1 else { return }
            let vis = scroll.contentView.bounds
            let c = CGPoint(x: min(max(vis.midX / doc.frame.width, 0), 1),
                            y: min(max(vis.midY / doc.frame.height, 0), 1))
            let old = controller.viewCenter
            guard abs(old.x - c.x) > 0.002 || abs(old.y - c.y) > 0.002 else { return }
            DispatchQueue.main.async { self.controller.viewCenter = c }
        }

        private func centerOn(_ c: CGPoint) {
            guard let scroll, let doc = scroll.documentView, doc.frame.width > 1 else { return }
            suppressCenterReport = true
            let vis = scroll.contentView.bounds.size
            scroll.contentView.scroll(to: NSPoint(x: c.x * doc.frame.width - vis.width / 2,
                                                  y: c.y * doc.frame.height - vis.height / 2))
            scroll.reflectScrolledClipView(scroll.contentView)
            suppressCenterReport = false
        }

        private func updatePercent() {
            guard let scroll else { return }
            let fitM = fitMagnification()
            let maxM = scroll.maxMagnification
            let p = Int((scroll.magnification * 100).rounded())
            let isZoomed = scroll.magnification > fitM + 0.001
            let frac = (maxM > fitM) ? Double(log(scroll.magnification / fitM) / log(maxM / fitM)) : 0
            DispatchQueue.main.async {
                self.controller.percent = p
                self.controller.zoomed = isZoomed
                self.controller.fraction = min(max(frac, 0), 1)
            }
        }
    }
}

/// NSScrollView that reports when it first receives a real layout size, so the
/// initial fit can be computed once the view is actually on screen.
final class ZoomScrollView: NSScrollView {
    var onLayout: (() -> Void)?

    /// Mouse-wheel zoom: (factor, anchor point in window coords).
    var onWheelZoom: ((CGFloat, NSPoint) -> Void)?

    override func layout() {
        super.layout()
        onLayout?()
    }

    /// A classic mouse wheel zooms in/out at the pointer (requested by users culling with a
    /// mouse). Only the wheel: trackpads and the Magic Mouse send PRECISE deltas and keep
    /// their normal two-finger panning — they zoom by pinching, so hijacking their scroll
    /// would break panning for them.
    override func scrollWheel(with event: NSEvent) {
        guard !event.hasPreciseScrollingDeltas, let onWheelZoom else {
            super.scrollWheel(with: event)
            return
        }
        let dy = event.scrollingDeltaY
        guard dy != 0 else { return }
        // Clamped so one flick of a fast/free-spinning wheel can't jump the whole zoom range.
        let steps = max(-3, min(3, dy))
        onWheelZoom(pow(1.15, steps), event.locationInWindow)
    }
}

/// Keeps the document view centred when it is smaller than the viewport
/// (otherwise NSScrollView pins it to the bottom-left corner).
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let doc = documentView else { return rect }
        let df = doc.frame
        if rect.width > df.width  { rect.origin.x = (df.width  - rect.width)  / 2 }
        if rect.height > df.height { rect.origin.y = (df.height - rect.height) / 2 }
        return rect
    }
}

/// Compact zoom controls shown at the bottom of the loupe (buttons mirror the
/// keyboard: −/+ zoom, 1:1 jumps to 100%, and it flips to "fit" once zoomed in).
struct ZoomControls: View {
    @ObservedObject var zoom: ZoomController

    var body: some View {
        HStack(spacing: 2) {
            button("minus.magnifyingglass") { zoom.zoomOut() }
            Text("\(zoom.percent)%")
                .font(.caption.monospacedDigit())
                .frame(width: 46)
            button("plus.magnifyingglass") { zoom.zoomIn() }
            Divider().frame(height: 16).padding(.horizontal, 2)
            button(zoom.zoomed ? "arrow.down.right.and.arrow.up.left" : "1.magnifyingglass") {
                if zoom.zoomed { zoom.fit() } else { zoom.toggle100() }
            }
            .help(zoom.zoomed ? "Einpassen (Esc)" : "100% (Z)")
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
    }

    private func button(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Vertical zoom slider shown on the right of the loupe while zoom mode (space
/// bar) is active. The filled track doubles as a live "how far zoomed" gauge;
/// drag it (mouse or trackpad) to zoom between fit (bottom) and maximum (top).
struct ZoomSlider: View {
    @ObservedObject var zoom: ZoomController
    private let trackH: CGFloat = 190
    private let trackW: CGFloat = 6
    private let thumb: CGFloat = 16

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "plus.magnifyingglass").font(.caption).foregroundStyle(.secondary)
            GeometryReader { geo in
                let h = geo.size.height
                let f = CGFloat(min(max(zoom.fraction, 0), 1))
                ZStack(alignment: .bottom) {
                    Capsule().fill(Color.primary.opacity(0.18)).frame(width: trackW, height: h)
                    Capsule().fill(Color.accentColor).frame(width: trackW, height: max(trackW, h * f))
                    Circle().fill(.white).frame(width: thumb, height: thumb).shadow(radius: 1)
                        .offset(y: -((h - thumb) * f))
                }
                .frame(width: geo.size.width, height: h)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    zoom.setFraction(1 - Double(min(max(v.location.y / h, 0), 1)))
                })
            }
            .frame(width: 26, height: trackH)
            Image(systemName: "minus.magnifyingglass").font(.caption).foregroundStyle(.secondary)
            Text("\(zoom.percent)%")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 14).padding(.horizontal, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.12), lineWidth: 1))
    }
}

