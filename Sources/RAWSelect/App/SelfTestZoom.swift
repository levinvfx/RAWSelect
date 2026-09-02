import AppKit

// Dev/test-only (see SelfTest.swift): exercises the loupe's AppKit zoom view headlessly —
// fit, mouse-wheel zoom anchored under the pointer, photo swap while zoomed — and verifies
// the image never scrolls out of the viewport (regression: black loupe after wheel zoom).
#if DEBUG

extension SelfTest {

    static func zoomTests(_ check: (Bool, String) -> Void) {
        _ = NSApplication.shared
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                           styleMask: [.titled], backing: .buffered, defer: false)
        let controller = ZoomController()
        let scroll = ZoomScrollView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.allowsMagnification = true
        scroll.maxMagnification = 8
        scroll.minMagnification = 0.02
        scroll.drawsBackground = false
        scroll.contentView = CenteringClipView()
        let iv = NSImageView()
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.wantsLayer = true
        scroll.documentView = iv
        let coord = ZoomableImageView.Coordinator(controller: controller)
        coord.scroll = scroll
        coord.imageView = iv
        scroll.onLayout = { [weak coord] in coord?.layoutTick() }
        scroll.onWheelZoom = { [weak coord] f, p in coord?.wheelZoom(by: f, anchorWindowPoint: p) }
        win.contentView = scroll
        scroll.layoutSubtreeIfNeeded()

        func img(_ w: Int, _ h: Int) -> NSImage {
            let i = NSImage(size: NSSize(width: w, height: h))
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            i.addRepresentation(rep)
            return i
        }
        /// Fraction of the viewport that shows image (1 = fully covered, 0 = black).
        func coverage() -> CGFloat {
            let vis = scroll.contentView.bounds
            let doc = iv.frame
            let inter = vis.intersection(doc)
            guard !inter.isNull, vis.width > 0, vis.height > 0 else { return 0 }
            return (inter.width * inter.height) / (vis.width * vis.height)
        }
        func fitCoverage() -> CGFloat {   // at fit the image fills one axis: coverage == docArea/visArea
            let vis = scroll.contentView.bounds, doc = iv.frame
            return (doc.width * doc.height) / (vis.width * vis.height)
        }
        let mid = NSPoint(x: 500, y: 350)

        coord.setImage(img(6000, 4000), id: "a", resetToFit: true)
        coord.layoutTick()
        let fitM = scroll.magnification
        check(abs(fitM - 1000.0 / 6000.0) < 0.001, "zoom: fit magnification 1000/6000 (got \(fitM))")
        check(abs(coverage() - fitCoverage()) < 0.02, "zoom: image centred and fully visible at fit (\(coverage()))")

        for _ in 0..<6 { coord.wheelZoom(by: 1.15, anchorWindowPoint: mid) }
        check(scroll.magnification > fitM * 2, "zoom: 6 wheel steps zoom in (\(scroll.magnification))")
        check(coverage() > 0.98, "zoom: viewport fully covered after wheel-in at centre (\(coverage()))")

        for _ in 0..<12 { coord.wheelZoom(by: 1 / 1.15, anchorWindowPoint: mid) }
        check(abs(scroll.magnification - fitM) < 0.001, "zoom: wheel-out clamps at fit (\(scroll.magnification))")
        check(abs(coverage() - fitCoverage()) < 0.02, "zoom: image visible again after wheel-out (\(coverage()))")

        // Wheel near the window corner: anchor must stay inside the image.
        for _ in 0..<5 { coord.wheelZoom(by: 1.15, anchorWindowPoint: NSPoint(x: 12, y: 12)) }
        check(coverage() > 0.9, "zoom: wheel-in at corner keeps image on screen (\(coverage()))")
        for _ in 0..<5 { coord.wheelZoom(by: 1.15, anchorWindowPoint: NSPoint(x: 990, y: 690)) }
        check(coverage() > 0.98, "zoom: wheel-in at far corner keeps image on screen (\(coverage()))")

        // Step to the next photo while zoomed (loupe keeps magnification + centre).
        coord.setImage(img(6000, 4000), id: "b", resetToFit: false)
        check(coverage() > 0.98, "zoom: photo swap while zoomed keeps image on screen (\(coverage()))")
        // Portrait photo of a different size, same path.
        coord.setImage(img(4000, 6000), id: "c", resetToFit: false)
        check(coverage() > 0.98, "zoom: portrait swap while zoomed keeps image on screen (\(coverage()))")
        // Zoom-out to fit on the new photo.
        for _ in 0..<30 { coord.wheelZoom(by: 1 / 1.15, anchorWindowPoint: mid) }
        check(abs(coverage() - fitCoverage()) < 0.02, "zoom: wheel-out on portrait returns to a centred fit (\(coverage()))")

        // Very small image (tiny thumbnail shown before the preview arrives) → then hi-res swap.
        coord.setImage(img(256, 170), id: "d", resetToFit: true)
        coord.layoutTick()
        for _ in 0..<4 { coord.wheelZoom(by: 1.15, anchorWindowPoint: mid) }
        coord.setImage(img(6000, 4000), id: "d", resetToFit: false)
        check(coverage() > 0.98, "zoom: hi-res swap after wheel on tiny preview keeps image on screen (\(coverage()))")

        // Real wheel events through the NSScrollView override (line deltas = classic mouse).
        coord.setImage(img(6000, 4000), id: "e", resetToFit: true)
        coord.layoutTick()
        if let cg = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 3, wheel2: 0, wheel3: 0),
           let ev = NSEvent(cgEvent: cg) {
            let before = scroll.magnification
            scroll.scrollWheel(with: ev)
            check(scroll.magnification > before, "zoom: NSScrollView.scrollWheel with line deltas zooms (\(before) → \(scroll.magnification))")
            check(coverage() > 0.98, "zoom: image on screen after real wheel event (\(coverage()))")
        } else {
            check(false, "zoom: could not synthesise wheel event")
        }
    }
}

#endif
