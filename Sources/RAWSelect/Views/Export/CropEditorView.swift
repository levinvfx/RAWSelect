import SwiftUI
import AppKit
import CoreImage
import CoreGraphics

enum AspectPreset: String, CaseIterable, Identifiable {
    case free, r1x1, r2x3, r3x4, r4x5, r5x7, r16x9
    var id: String { rawValue }
    var label: String { switch self {
        case .free: return "Frei"; case .r1x1: return "1:1"; case .r2x3: return "2:3"; case .r3x4: return "3:4"
        case .r4x5: return "4:5"; case .r5x7: return "5:7"; case .r16x9: return "16:9" } }
    /// Width / height, landscape orientation. nil = free.
    var ratio: CGFloat? { switch self {
        case .free: return nil; case .r1x1: return 1; case .r2x3: return 3.0/2; case .r3x4: return 4.0/3
        case .r4x5: return 5.0/4; case .r5x7: return 7.0/5; case .r16x9: return 16.0/9 } }
}

/// Which part of the crop a drag/hover targets.
fileprivate enum CropZone: Equatable { case tl, tr, bl, br, top, bottom, left, right, move, rotate }

enum EditorTab: String, CaseIterable { case crop = "Zuschneiden", develop = "Entwickeln" }

/// State of the optional Lightroom-rendered preset preview (export step only).
fileprivate enum PresetPreviewStatus: Equatable { case none, rendering, ready, failed }

/// Lightroom-style crop: the image stays fixed, the crop **grid** shrinks. Corner
/// & edge handles resize the grid (anchored on the opposite side), dragging inside
/// moves the grid, dragging in the **margin outside** rotates the whole image.
/// One unified gesture decides the mode from where the drag starts.
struct CropEditorView: View {
    let previewURL: URL
    @Binding var edit: ImageEdit
    /// Optional: when set (export crop step), the base image is the Lightroom-rendered
    /// preview WITH the preset applied, so tweaks are made in the near-final look.
    /// Left nil in the standalone editor → plain preview as before.
    var rawURL: URL? = nil
    var presetURL: URL? = nil
    var lightroomPath: String = ""
    @State private var presetStatus: PresetPreviewStatus = .none
    /// Develop values the preset already sets (crs key → value). Sliders display
    /// `presetValue + user delta`, so the preset's changes are shown right away.
    @State private var presetVals: [String: Double] = [:]
    // Exact Adobe render of preset+develop (tone-complete). When it matches the
    // current develop values, it's shown directly (DevelopEngine bypassed); otherwise
    // the fast approximation is shown until a fresh exact render lands on release.
    @State private var exactCI: CIImage?
    @State private var exactKey: String?
    @State private var exactTask: Task<Void, Never>?
    // Cached tone-complete (develop-applied, UN-rotated) image. Rotation/straighten
    // then only re-rotates this instead of re-running the whole filter chain → live.
    @State private var toneCG: CGImage?
    @State private var toneKey: String?
    /// Frozen layout captured at drag start so the image/crop mapping stays stable
    /// during a drag (Lightroom-style: move pans the image, resize keeps it fixed).
    @State private var activeLayout: CropLayout?

    @State private var baseCI: CIImage?
    @State private var displayImage: NSImage?
    /// The straighten angle currently baked into `displayImage`. While a straighten gesture is
    /// live, the delta to `edit.straighten` is shown as a cheap GPU layer rotation (rotationEffect)
    /// instead of re-baking the pixels every tick — smooth and never distorted.
    @State private var renderedStraighten: Double = 0
    @State private var straightenLive = false
    /// Debounces the crisp full-res render while the straighten angle is being dragged.
    @State private var straightenSettleTask: Task<Void, Never>?

    // Zoom inspector for the Develop preview: pinch/scroll like the browsing loupe, but it
    // magnifies the DEVELOPED image so an adjustment can be judged on real detail.
    @StateObject private var previewZoom = ZoomController()
    @State private var cropNorm = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var aspect: AspectPreset = .free
    @State private var portrait = false
    @State private var locked = true                 // default: original aspect

    @Binding var editorTab: EditorTab
    @State private var dragZone: CropZone?
    @State private var startCrop: CGRect?
    @State private var startStraighten: Double = 0
    @State private var startAngle: CGFloat = 0
    @State private var hoveredZone: CropZone?

    // Live-preview render pump: only ever one render in flight, and it always
    // renders the *latest* edit (rapid slider drags coalesce into one job).
    @State private var isRendering = false
    @State private var pendingRender = false

    /// White balance Camera Raw resolved for this photo (as-shot, unless the preset sets
    /// WB), learned from the Lightroom render. Seeds the WB slider base so it shows the
    /// value the RAW was shot with instead of a fixed guess. nil until known.
    @State private var asShotTemp: Double?

    /// Currently selected hue band in the color-mixer section (index into ImageEdit.hslBands).
    @State private var hslBand = 0
    /// Representative swatch colors for the eight HSL bands.
    private static let hslBandColors: [Color] = [
        Color(red: 0.90, green: 0.24, blue: 0.28), Color(red: 0.95, green: 0.55, blue: 0.20),
        Color(red: 0.93, green: 0.83, blue: 0.25), Color(red: 0.36, green: 0.78, blue: 0.38),
        Color(red: 0.30, green: 0.78, blue: 0.80), Color(red: 0.28, green: 0.50, blue: 0.92),
        Color(red: 0.55, green: 0.38, blue: 0.88), Color(red: 0.88, green: 0.36, blue: 0.78)]

    /// One CIContext shared across all editor previews — creating one per view is
    /// expensive, and CIContext rendering is thread-safe.
    private static let sharedContext = CIContext(options: [.useSoftwareRenderer: false])
    private let full = CGRect(x: 0, y: 0, width: 1, height: 1)
    private let minSize: CGFloat = 0.06
    private let handleRadius: CGFloat = 28

    /// Custom rotate cursor (white disc + rotate arrow) – there is no built-in one.
    private static let rotateCursor: NSCursor = {
        let d: CGFloat = 26
        let img = NSImage(size: NSSize(width: d, height: d))
        img.lockFocus()
        let disc = NSRect(x: 2, y: 2, width: d - 4, height: d - 4)
        NSColor.white.setFill(); NSBezierPath(ovalIn: disc).fill()
        NSColor.black.withAlphaComponent(0.3).setStroke()
        let ring = NSBezierPath(ovalIn: disc); ring.lineWidth = 1; ring.stroke()
        if let sym = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .bold)) {
            let s = sym.size
            sym.draw(in: NSRect(x: (d - s.width) / 2, y: (d - s.height) / 2, width: s.width, height: s.height))
        }
        img.unlockFocus()
        return NSCursor(image: img, hotSpot: NSPoint(x: d / 2, y: d / 2))
    }()

    private var aspectNorm: CGFloat? {
        guard let img = displayImage, img.size.height > 0 else { return nil }
        let A = img.size.width / img.size.height
        if var r = aspect.ratio { if portrait { r = 1 / r }; return r / A }
        if locked, cropNorm.height > 0 { return cropNorm.width / cropNorm.height }
        return nil
    }

    var body: some View {
        VStack(spacing: 12) {
            Picker("", selection: $editorTab) {
                ForEach(EditorTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 260)

            if editorTab == .crop { topControls }
            GeometryReader { geo in workspace(in: geo.size) }
                .background(Color(white: 0.11))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.06), lineWidth: 1))
                .overlay(alignment: .top) { presetStatusPill.padding(.top, 10) }
                .animation(.easeOut(duration: 0.15), value: presetStatus == .rendering)
            if editorTab == .crop { sliderControls } else { developControls }
        }
        .task(id: previewURL) { await loadImage() }
        // Sync the crop into the binding only when NOT actively dragging — writing it on every
        // drag tick re-rendered the whole editor (and its parent) and made cropping feel laggy.
        // Programmatic changes (aspect, reset, rotate) still sync here; a drag syncs on release.
        .onChange(of: cropNorm) { _, v in if dragZone == nil { edit.crop = (v == full) ? nil : v } }
    }

    /// In the Develop tab the preview shows the FINAL composition — the base image
    /// cropped to `cropNorm` (rotation/straighten are already baked into displayImage).
    private var developPreviewImage: NSImage? {
        guard let img = displayImage else { return nil }
        return (cropNorm == full) ? img : cropped(img, to: cropNorm)
    }

    private func cropped(_ img: NSImage, to c: CGRect) -> NSImage {
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return img }
        let W = CGFloat(cg.width), H = CGFloat(cg.height)
        let rect = CGRect(x: (c.minX * W).rounded(), y: (c.minY * H).rounded(),
                          width: (c.width * W).rounded(), height: (c.height * H).rounded())
            .intersection(CGRect(x: 0, y: 0, width: W, height: H))
        guard rect.width >= 1, rect.height >= 1, let out = cg.cropping(to: rect) else { return img }
        return NSImage(cgImage: out, size: NSSize(width: out.width, height: out.height))
    }

    // MARK: Lightroom-style crop layout (frame fixed & centred, image pans behind)

    private func imgRectFor(_ crop: CGRect, in cropView: CGRect) -> CGRect {
        let dw = cropView.width / max(crop.width, 0.0001), dh = cropView.height / max(crop.height, 0.0001)
        return CGRect(x: cropView.minX - crop.minX * dw, y: cropView.minY - crop.minY * dh, width: dw, height: dh)
    }
    private func cropViewFor(_ crop: CGRect, in imgRect: CGRect) -> CGRect {
        CGRect(x: imgRect.minX + crop.minX * imgRect.width, y: imgRect.minY + crop.minY * imgRect.height,
               width: crop.width * imgRect.width, height: crop.height * imgRect.height)
    }
    /// Centred, max-fit crop frame for `crop`, with the image sized to map onto it.
    private func centeredLayout(imgSize: CGSize, crop: CGRect, in c: CGSize) -> CropLayout {
        let aspect = max(crop.width * imgSize.width, 1) / max(crop.height * imgSize.height, 1)
        let availW = c.width * 0.82, availH = c.height * 0.82
        var vw = availW, vh = availW / aspect
        if vh > availH { vh = availH; vw = availH * aspect }
        let cv = CGRect(x: (c.width - vw) / 2, y: (c.height - vh) / 2, width: vw, height: vh)
        return CropLayout(cropView: cv, imgRect: imgRectFor(crop, in: cv))
    }
    /// Layout to render right now: while dragging, `move` keeps the frame fixed (image
    /// pans), resize keeps the image fixed (frame follows); otherwise centred.
    private func liveLayout(imgSize: CGSize, in c: CGSize) -> CropLayout {
        if let a = activeLayout, let z = dragZone {
            switch z {
            case .move:   return CropLayout(cropView: a.cropView, imgRect: imgRectFor(cropNorm, in: a.cropView))
            case .rotate: return a
            default:      return CropLayout(cropView: cropViewFor(cropNorm, in: a.imgRect), imgRect: a.imgRect)
            }
        }
        return centeredLayout(imgSize: imgSize, crop: cropNorm, in: c)
    }

    @ViewBuilder
    private func workspace(in c: CGSize) -> some View {
        if editorTab == .crop, let img = displayImage {
            cropWorkspace(img: img, in: c)
        } else if let img = developPreviewImage {
            // Zooms the DEVELOPED image, not the original file: the whole point of zooming here
            // is watching an adjustment land on real detail. `developPreviewImage` is rebuilt on
            // every slider move, and ZoomableImageView swaps it in while holding the zoom level
            // and centre — so white balance or exposure changes show up live, magnified.
            ZoomableImageView(imageID: previewURL.path, image: img, controller: previewZoom)
                .frame(width: c.width, height: c.height)
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }


    @ViewBuilder
    private func cropWorkspace(img: NSImage, in c: CGSize) -> some View {
        let L = liveLayout(imgSize: img.size, in: c)
        let showRotate = hoveredZone == .rotate || dragZone == .rotate
        ZStack {
            Image(nsImage: img).resizable()
                .frame(width: L.imgRect.width, height: L.imgRect.height)
                // While straightening, show the angle as a live layer rotation (delta to what's
                // baked in the image). No pixel work, aspect preserved → smooth, no distortion.
                .rotationEffect(.degrees(straightenLive ? (edit.straighten - renderedStraighten) : 0))
                .position(x: L.imgRect.midX, y: L.imgRect.midY)
            CropVisual(cropRect: L.cropView, bounds: CGRect(origin: .zero, size: c), hovered: hoveredZone)
                .allowsHitTesting(false)
            if showRotate {
                rotateHint.position(x: L.cropView.midX, y: L.cropView.maxY - 24).allowsHitTesting(false)
            }
        }
        .frame(width: c.width, height: c.height)
        .clipped()
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { dragChanged($0, in: c, imgSize: img.size) }
                .onEnded { _ in
                    let wasRotate = dragZone == .rotate
                    dragZone = nil; startCrop = nil; activeLayout = nil
                    edit.crop = (cropNorm == full) ? nil : cropNorm   // sync the deferred crop now
                    if wasRotate { straightenSettleTask?.cancel(); updateDisplay() }  // crisp full-res
                }
        )
        .onContinuousHover { hover($0, cropRect: L.cropView) }
        .animation(.easeOut(duration: 0.15), value: showRotate)
    }

    @ViewBuilder private var presetStatusPill: some View {
        switch presetStatus {
        case .rendering:
            statusPill { HStack(spacing: 7) { ProgressView().controlSize(.small); Text("Preset-Vorschau wird gerendert…") } }
        case .failed:
            statusPill { Label("Preset-Vorschau nicht verfügbar – zeigt Basisbild", systemImage: "exclamationmark.triangle") }
        case .ready, .none:
            EmptyView()
        }
    }

    private func statusPill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(.caption.weight(.medium))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .transition(.opacity)
    }

    private var rotateHint: some View {
        HStack(spacing: 6) { Image(systemName: "rotate.right"); Text("Ziehen zum Drehen") }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
    }

    // MARK: Hit testing

    private func zone(at p: CGPoint, rect r: CGRect) -> CropZone {
        func near(_ x: CGFloat, _ y: CGFloat) -> Bool { hypot(p.x - x, p.y - y) < handleRadius }
        if near(r.minX, r.minY) { return .tl }
        if near(r.maxX, r.minY) { return .tr }
        if near(r.minX, r.maxY) { return .bl }
        if near(r.maxX, r.maxY) { return .br }
        if near(r.midX, r.minY) { return .top }
        if near(r.midX, r.maxY) { return .bottom }
        if near(r.minX, r.midY) { return .left }
        if near(r.maxX, r.midY) { return .right }
        if r.contains(p) { return .move }
        return .rotate
    }

    // MARK: Drag

    private func dragChanged(_ v: DragGesture.Value, in c: CGSize, imgSize: CGSize) {
        if dragZone == nil {
            let start = centeredLayout(imgSize: imgSize, crop: cropNorm, in: c)
            activeLayout = start
            startCrop = cropNorm
            startStraighten = edit.straighten
            dragZone = zone(at: v.startLocation, rect: start.cropView)
            startAngle = atan2(v.startLocation.y - start.cropView.midY, v.startLocation.x - start.cropView.midX)
        }
        guard let z = dragZone, let A = activeLayout else { return }

        if z == .rotate {
            let ang = atan2(v.location.y - A.cropView.midY, v.location.x - A.cropView.midX)
            var deg = startStraighten + Double((ang - startAngle) * 180 / .pi)
            deg = min(max(deg, -15), 15)
            if abs(deg - edit.straighten) > 0.01 { edit.straighten = deg; straightenChanged() }
            return
        }

        guard let s = startCrop, A.imgRect.width > 0, A.imgRect.height > 0 else { return }
        // Deltas are normalised against the FIXED image (start layout).
        let dx = v.translation.width / A.imgRect.width
        let dy = v.translation.height / A.imgRect.height
        let a = aspectNorm
        var r = s
        switch z {
        case .move:
            // Dragging pans the image → the crop region moves the opposite way.
            r.origin.x = min(max(0, s.minX - dx), 1 - s.width)
            r.origin.y = min(max(0, s.minY - dy), 1 - s.height)
            if cropInsideContent(r) { cropNorm = r }
            return
        case .tl:
            let nx = min(max(0, s.minX + dx), s.maxX - minSize)
            var ny = min(max(0, s.minY + dy), s.maxY - minSize)
            if let a { ny = s.maxY - (s.maxX - nx) / a }
            r = CGRect(x: nx, y: ny, width: s.maxX - nx, height: s.maxY - ny)
        case .tr:
            let mx = min(max(s.minX + minSize, s.maxX + dx), 1)
            var ny = min(max(0, s.minY + dy), s.maxY - minSize)
            if let a { ny = s.maxY - (mx - s.minX) / a }
            r = CGRect(x: s.minX, y: ny, width: mx - s.minX, height: s.maxY - ny)
        case .bl:
            let nx = min(max(0, s.minX + dx), s.maxX - minSize)
            var my = min(max(s.minY + minSize, s.maxY + dy), 1)
            if let a { my = s.minY + (s.maxX - nx) / a }
            r = CGRect(x: nx, y: s.minY, width: s.maxX - nx, height: my - s.minY)
        case .br:
            let mx = min(max(s.minX + minSize, s.maxX + dx), 1)
            var my = min(max(s.minY + minSize, s.maxY + dy), 1)
            if let a { my = s.minY + (mx - s.minX) / a }
            r = CGRect(x: s.minX, y: s.minY, width: mx - s.minX, height: my - s.minY)
        case .left:
            let nx = min(max(0, s.minX + dx), s.maxX - minSize)
            let w = s.maxX - nx
            if let a { let h = w / a; r = CGRect(x: nx, y: s.midY - h / 2, width: w, height: h) }
            else { r = CGRect(x: nx, y: s.minY, width: w, height: s.height) }
        case .right:
            let mx = min(max(s.minX + minSize, s.maxX + dx), 1)
            let w = mx - s.minX
            if let a { let h = w / a; r = CGRect(x: s.minX, y: s.midY - h / 2, width: w, height: h) }
            else { r = CGRect(x: s.minX, y: s.minY, width: w, height: s.height) }
        case .top:
            let ny = min(max(0, s.minY + dy), s.maxY - minSize)
            let h = s.maxY - ny
            if let a { let w = h * a; r = CGRect(x: s.midX - w / 2, y: ny, width: w, height: h) }
            else { r = CGRect(x: s.minX, y: ny, width: s.width, height: h) }
        case .bottom:
            let my = min(max(s.minY + minSize, s.maxY + dy), 1)
            let h = my - s.minY
            if let a { let w = h * a; r = CGRect(x: s.midX - w / 2, y: s.minY, width: w, height: h) }
            else { r = CGRect(x: s.minX, y: s.minY, width: s.width, height: h) }
        case .rotate: return
        }
        if r.minX >= 0, r.minY >= 0, r.maxX <= 1, r.maxY <= 1, r.width >= minSize, r.height >= minSize,
           cropInsideContent(r) {
            cropNorm = r
        }
    }

    /// True if `crop` (normalised on the rotated display bounding box) stays inside
    /// the real image content — i.e. never touches the transparent corners that a
    /// straighten angle creates. Always true when there is no straighten.
    private func cropInsideContent(_ crop: CGRect) -> Bool {
        guard let img = displayImage, let base = baseCI else { return true }
        let phi = edit.straighten * .pi / 180
        if abs(phi) < 0.0002 { return true }
        let bb = img.size
        let odd = edit.rotation % 2 != 0
        let w1 = odd ? base.extent.height : base.extent.width      // content size after 90° steps
        let h1 = odd ? base.extent.width  : base.extent.height
        let c = cos(phi), s = sin(phi)
        for (nx, ny) in [(crop.minX, crop.minY), (crop.maxX, crop.minY),
                         (crop.minX, crop.maxY), (crop.maxX, crop.maxY)] {
            let px = (nx - 0.5) * bb.width, py = (ny - 0.5) * bb.height
            let qx = px * c + py * s, qy = -px * s + py * c        // un-rotate into content frame
            if abs(qx) > w1 / 2 + 0.5 || abs(qy) > h1 / 2 + 0.5 { return false }
        }
        return true
    }

    /// After a straighten change, shrink the crop around its centre until it fits
    /// inside the rotated content (so the export never bakes transparent wedges).
    /// Binary-searches the *largest* concentric rectangle of the same aspect ratio
    /// that fits, so it always lands on a fitting crop (never leaves a wedge, even
    /// for a large, off-centre selection).
    private func constrainCropToContent() {
        guard !cropInsideContent(cropNorm) else { return }
        let cx = cropNorm.midX, cy = cropNorm.midY
        let ar = cropNorm.height > 0 ? cropNorm.width / cropNorm.height : 1
        var lo: CGFloat = 0, hi = cropNorm.width
        var best = CGRect.null
        for _ in 0..<24 {
            let w = (lo + hi) / 2, h = w / ar
            let r = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
            if cropInsideContent(r) { best = r; lo = w } else { hi = w }
        }
        if !best.isNull, best.width >= minSize, best.height >= minSize { cropNorm = best }
    }

    private func hover(_ phase: HoverPhase, cropRect: CGRect) {
        switch phase {
        case .active(let p):
            let z = zone(at: p, rect: cropRect)
            if z != hoveredZone { hoveredZone = z }
            switch z {
            case .rotate: Self.rotateCursor.set()
            case .move: NSCursor.openHand.set()
            default: NSCursor.crosshair.set()
            }
        case .ended:
            hoveredZone = nil
            NSCursor.arrow.set()
        }
    }

    // MARK: Controls

    private var topControls: some View {
        HStack(spacing: 10) {
            Button { rotate90(-1) } label: { Image(systemName: "rotate.left") }
            Button { rotate90(1) } label: { Image(systemName: "rotate.right") }
            Picker("", selection: $aspect) { ForEach(AspectPreset.allCases) { Text($0.label).tag($0) } }
                .frame(width: 90).labelsHidden()
                .onChange(of: aspect) { _, _ in applyAspect() }
            Button { portrait.toggle(); applyAspect() } label: { Image(systemName: "rotate.right.fill") }
                .help("Hoch-/Querformat").disabled(aspect == .free)
            Toggle(isOn: $locked) { Image(systemName: locked ? "lock.fill" : "lock.open") }
                .toggleStyle(.button).help("Seitenverhältnis sperren (Standard: Originalformat)")
            Spacer()
            Button("Zurücksetzen") { cropNorm = full; aspect = .free; locked = true; edit.straighten = 0; updateDisplay() }
                .disabled(cropNorm == full && edit.straighten == 0)
        }
        .buttonStyle(.bordered)
    }

    // Crop tab: purely geometry — straighten only. Tone/exposure lives in „Entwickeln".
    private var sliderControls: some View {
        LRSlider(title: "Ausrichten", value: $edit.straighten, range: -15...15, neutral: 0,
                 format: { String(format: "%+.1f°", $0) }, onEdit: { straightenChanged() })
            .padding(.horizontal, 6).padding(.top, 2)
    }

    // MARK: Develop panel

    private func dev() { updateDisplay() }

    /// A develop slider that shows `presetValue + user delta` — so the preset's own
    /// value appears immediately and „Zurücksetzen" returns to the preset value. The
    /// binding maps the displayed absolute value back to the stored delta.
    private func toneSlider(_ title: String, _ field: WritableKeyPath<ImageEdit, Double>, _ key: String,
                            range: ClosedRange<Double> = -100...100,
                            format: @escaping (Double) -> String = { String(format: "%+.0f", $0) },
                            gradient: [Color]? = nil) -> some View {
        // Fall back to a sensible neutral (e.g. 6500 K for WB) when the preset doesn't
        // define this value, so the slider shows a real number instead of 0.
        let base = presetVals[key] ?? 0
        return LRSlider(title: title,
                        value: Binding(get: { base + edit[keyPath: field] },
                                       set: { edit[keyPath: field] = $0 - base }),
                        range: range, neutral: base, format: format, gradient: gradient, onEdit: dev)
    }

    /// A white-balance slider: a plain relative nudge around 0, so it never has to wait for
    /// Lightroom to reveal the photo's actual Kelvin. The stored value IS the delta.
    ///
    /// Disabled without a preset — and that is not cosmetic. Camera Raw only honours ABSOLUTE
    /// Kelvin on a RAW, so the nudge needs a base, and the base only ever arrives with a
    /// Lightroom render. No preset means no render, which means no base, which means the
    /// export silently writes no white balance at all — while the live preview happily shows
    /// the picture getting warmer. Better to say "not available" than to lie.
    private func wbSlider(_ title: String, _ field: WritableKeyPath<ImageEdit, Double>,
                          range: ClosedRange<Double>, gradient: [Color]) -> some View {
        LRSlider(title: title,
                 value: Binding(get: { edit[keyPath: field] }, set: { edit[keyPath: field] = $0 }),
                 range: range, neutral: 0,
                 format: { String(format: "%+.0f", $0) }, gradient: gradient, onEdit: dev)
            .disabled(!wbAvailable)
            .opacity(wbAvailable ? 1 : 0.4)
    }

    /// The WB sliders only work once Lightroom has told us the photo's Kelvin, which only
    /// happens on a preset render.
    private var wbAvailable: Bool { rawURL != nil && presetURL != nil }

    /// One color-mixer slider for the selected band. Like `toneSlider`, the value shows
    /// the preset's own HSL value + the user delta; the delta is stored in `edit.hsl`
    /// (zero deltas are pruned so an untouched mixer leaves `developIsZero` true).
    private func hslSlider(_ title: String, _ channel: String) -> some View {
        let key = channel + ImageEdit.hslBands[hslBand]
        let base = presetVals[key] ?? 0
        return LRSlider(title: title,
                        value: Binding(get: { base + (edit.hsl[key] ?? 0) },
                                       set: { v in
                                           let d = v - base
                                           if d == 0 { edit.hsl[key] = nil } else { edit.hsl[key] = d }
                                       }),
                        range: -100...100, neutral: base,
                        format: { String(format: "%+.0f", $0) }, onEdit: dev)
    }

    private var developControls: some View {
        VStack(spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    // The WB sliders nudge relative to wherever the photo already is (cooler ↔
                    // warmer), rather than showing an absolute Kelvin. The absolute value only
                    // becomes known once Lightroom has rendered the photo once, so an absolute
                    // slider would sit on a placeholder until then — and Camera Raw ignores
                    // relative WB on RAW, so the delta is turned into absolute Kelvin on the
                    // way out (see XMPPresetBuilder).
                    LRSection(title: "Weissabgleich") {
                        wbSlider("Temperatur", \.temp, range: -2000...2000,
                                 gradient: [Color(red: 0.30, green: 0.52, blue: 0.95), Color(red: 0.96, green: 0.86, blue: 0.36)])
                        wbSlider("Tönung", \.tint, range: -60...60,
                                 gradient: [Color(red: 0.36, green: 0.85, blue: 0.42), Color(red: 0.90, green: 0.36, blue: 0.86)])
                        if !wbAvailable {
                            Text("Ohne Preset nicht verfügbar – Lightroom verrät den Weissabgleich des Bildes nur beim Rendern.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    LRSection(title: "Licht") {
                        toneSlider("Belichtung", \.exposure, "Exposure2012", range: -5...5,
                                   format: { String(format: "%+.2f", $0) })
                        toneSlider("Kontrast", \.contrast, "Contrast2012")
                        toneSlider("Lichter", \.highlights, "Highlights2012")
                        toneSlider("Tiefen", \.shadows, "Shadows2012")
                        toneSlider("Weiss", \.whites, "Whites2012")
                        toneSlider("Schwarz", \.blacks, "Blacks2012")
                    }
                    LRSection(title: "Farbmischer") {
                        HStack(spacing: 6) {
                            ForEach(0..<ImageEdit.hslBands.count, id: \.self) { i in
                                Circle().fill(Self.hslBandColors[i])
                                    .frame(width: 18, height: 18)
                                    .overlay(Circle().strokeBorder(.white.opacity(hslBand == i ? 0.95 : 0.15),
                                                                   lineWidth: hslBand == i ? 2 : 1))
                                    .contentShape(Circle())
                                    .onTapGesture { hslBand = i }
                            }
                        }
                        .padding(.bottom, 2)
                        hslSlider("Farbton", "HueAdjustment")
                        hslSlider("Sättigung", "SaturationAdjustment")
                        hslSlider("Luminanz", "LuminanceAdjustment")
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 300)
            .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.06), lineWidth: 1))

            HStack {
                Text(developNote).font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button("Entwicklung zurücksetzen") { resetDevelop() }
                    .buttonStyle(.borderless).controlSize(.small)
                    .disabled(edit.developIsZero && edit.exposure == 0)
            }
        }
    }

    private var developNote: String {
        switch presetStatus {
        case .ready:     return "Vorschau MIT Preset · deine Regler sind eine Annäherung darüber. Final rendert Adobe beim Export."
        case .rendering: return "Preset-Vorschau wird gerendert… Regler wirken bereits (Annäherung)."
        case .failed:    return "Preset-Vorschau nicht verfügbar – Basisbild. Final: Preset + Regler via Adobe beim Export."
        case .none:      return "Live-Vorschau ist eine Annäherung – finale Entwicklung durch Adobe beim Export."
        }
    }

    private func resetDevelop() {
        edit.exposure = 0; edit.contrast = 0; edit.highlights = 0; edit.shadows = 0
        edit.whites = 0; edit.blacks = 0; edit.temp = 0; edit.tint = 0
        edit.hsl.removeAll()
        updateDisplay()
    }

    // MARK: Actions & pipeline

    private func rotate90(_ dir: Int) {
        if dir < 0 { edit.rotateLeft() } else { edit.rotateRight() }
        cropNorm = full
        updateDisplay()
    }

    private func applyAspect() {
        guard let r = aspectNorm else { return }
        var w: CGFloat = 1, h: CGFloat = 1
        if r >= 1 { h = 1 / r } else { w = r }
        cropNorm = CGRect(x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h)
    }

    private func fittedRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let ia = imageSize.width / imageSize.height
        let ca = container.width / max(container.height, 1)
        var w = container.width, h = container.height
        if ia > ca { h = w / ia } else { w = h * ia }
        // Small margin so the rotate-outside zone always has room.
        w *= 0.92; h *= 0.92
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }

    private func loadImage() async {
        exactTask?.cancel(); exactCI = nil; exactKey = nil; toneCG = nil; toneKey = nil   // reset per photo
        asShotTemp = nil
        previewZoom.fit()
        presetVals = XMPPresetBuilder.presetValues(presetURL)   // preset baseline for the sliders
        // Instant WB base if this RAW was rendered before (survives across sessions).
        if let rawURL, let wb = await LightroomPreviewService.shared.asShotWB(rawURL: rawURL) {
            applyAsShotWB(wb)
        }
        let img = await ThumbnailLoader.shared.thumbnail(for: previewURL, maxPixel: 1600)
        if let cg = img?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            baseCI = CIImage(cgImage: cg)
        }
        cropNorm = edit.crop ?? full
        updateDisplay()
        await loadPresetBaseIfNeeded()
    }

    /// Export step only: swap the plain base for Lightroom's preset-rendered preview
    /// once it's ready (cached previews are instant). Manual tweaks then sit on top of
    /// the near-final look. Silent, non-blocking fallback to the plain base on failure.
    private func loadPresetBaseIfNeeded() async {
        guard let rawURL, let presetURL else { presetStatus = .none; return }
        let target = previewURL
        presetStatus = .rendering
        let url = await LightroomPreviewService.shared.preview(
            rawURL: rawURL, presetURL: presetURL, maxEdge: 2048, lightroomPath: lightroomPath)
        guard previewURL == target else { return }   // navigated away → ignore stale result
        if let url, let cg = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            baseCI = CIImage(cgImage: cg)
            toneCG = nil; toneKey = nil          // base changed → invalidate tone cache
            // The preset base is rendered at develop=0, so it IS the exact render for a
            // zero edit. Mark it as such; non-zero edits then trigger a fresh exact render.
            exactCI = baseCI
            exactKey = ImageEdit().developSignature
            presetStatus = .ready
            updateDisplay()
        } else {
            presetStatus = .failed
        }
        // The render reports the photo's actual white balance — adopt it as the slider base.
        if let wb = await LightroomPreviewService.shared.asShotWB(rawURL: rawURL) { applyAsShotWB(wb) }
    }

    /// Remembers the photo's real Kelvin. The sliders don't show it — they are relative — but
    /// the live preview anchors its white-balance maths there, because colour temperature is
    /// reciprocal: the same nudge means a different colour shift at 4000 K than at 7000 K.
    private func applyAsShotWB(_ wb: LightroomPreviewService.WB) {
        asShotTemp = wb.temp
    }

    /// After develop values settle (debounced), render the EXACT Adobe image with
    /// those values via Lightroom and show it — so the resting preview equals the
    /// export for all sliders. Export step only. Silent fallback keeps the approximation.
    private func scheduleExactIfNeeded() {
        guard let rawURL, let presetURL else { return }
        let wanted = edit
        if exactKey == wanted.developSignature, exactCI != nil { return }   // already exact
        exactTask?.cancel()
        let target = previewURL
        exactTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)   // debounce rapid drags
            if Task.isCancelled { return }
            presetStatus = .rendering
            let url = await LightroomPreviewService.shared.preview(
                rawURL: rawURL, presetURL: presetURL, edit: wanted, maxEdge: 2048, lightroomPath: lightroomPath)
            guard previewURL == target, edit.developSignature == wanted.developSignature else { return }
            if let url, let cg = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                exactCI = CIImage(cgImage: cg)
                exactKey = wanted.developSignature
                presetStatus = .ready
                renderOnce()   // swap in the exact Adobe image
            } else {
                presetStatus = .failed
            }
        }
    }

    /// Live straighten: the angle is shown instantly via a GPU layer rotation in the view (see
    /// `rotationEffect` in cropWorkspace), so nothing is re-rendered per tick. This just flags the
    /// live state and debounces one crisp full-res bake after the angle settles.
    private func straightenChanged() {
        straightenLive = true
        // During an active rotate DRAG the frame is frozen — baking or an exact preset render
        // landing mid-gesture would swap in an image with a different bounding box and stretch it
        // into that frozen frame (the "verzieht" with a preset). So while dragging, do NOTHING but
        // the live layer rotation, and cancel anything that could swap the image; the crisp bake
        // happens once on release (.onEnded). The Ausrichten SLIDER has no frozen frame (its layout
        // follows the image), so it debounces a crisp bake as before.
        guard dragZone == nil else {
            exactTask?.cancel()
            straightenSettleTask?.cancel()
            return
        }
        straightenSettleTask?.cancel()
        straightenSettleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 140_000_000)
            if Task.isCancelled { return }
            updateDisplay()   // bake the crisp full-res render at the settled angle
        }
    }

    /// Requests a fresh preview. The heavy work (filter chain + rasterise +
    /// rotate) runs off the main thread; while a render is in flight, further
    /// changes just flag a re-render so we always end on the latest edit without
    /// blocking the UI or piling up jobs.
    private func updateDisplay() {
        guard baseCI != nil else { return }
        if isRendering { pendingRender = true } else { renderOnce() }
        scheduleExactIfNeeded()
    }

    private func renderOnce() {
        guard let approxBase = baseCI else { return }
        let snapshot = edit
        let ctx = Self.sharedContext
        // Exact Adobe render if it matches the current develop values (tone already
        // baked → skip DevelopEngine); else the fast approximation over the preset base.
        let useExact = (exactCI != nil && exactKey == snapshot.developSignature)
        let sourceCI = useExact ? exactCI! : approxBase
        // Only the DEVELOP values change the tone image; straighten/rotation don't. So
        // reuse the cached tone when develop is unchanged → dragging the angle just
        // re-rotates (fast), no filter chain.
        let key = (useExact ? "e:" : "a:") + snapshot.developSignature
        let reuse = (toneKey == key) ? toneCG : nil
        let angle = snapshot.totalAngle
        // The Kelvin the picture currently sits at — the WB preview is anchored there.
        let wbBase = presetVals["Temperature"] ?? asShotTemp ?? 5500
        isRendering = true
        pendingRender = false
        Task { @MainActor in
            let out = await Task.detached(priority: .userInitiated) { () -> ToneOut in
                let tone: CGImage?
                if let reuse { tone = reuse }
                else {
                    let ci = useExact ? sourceCI : DevelopEngine.apply(snapshot, to: sourceCI, wbBase: wbBase)
                    tone = ctx.createCGImage(ci, from: ci.extent)
                }
                guard let t = tone else { return ToneOut(tone: nil, image: nil) }
                let ns = NSImage(cgImage: t, size: NSSize(width: t.width, height: t.height))
                    .rotatedClockwise(byDegrees: angle)
                return ToneOut(tone: t, image: ns)
            }.value
            if reuse == nil, let t = out.tone { self.toneCG = t; self.toneKey = key }
            // Never swap the image WHILE a drag is in progress — the frame is frozen, so a new
            // bounding box would be stretched into it (distortion). The bake on release runs with
            // dragZone == nil, so it applies then.
            if let ns = out.image, self.dragZone == nil {
                self.displayImage = ns
                self.renderedStraighten = snapshot.straighten   // this straighten is now baked in
                self.straightenLive = false                     // stop the live layer rotation
            }
            self.constrainCropToContent()   // keep the crop off the transparent corners
            self.isRendering = false
            if self.pendingRender { self.renderOnce() }
        }
    }
}

/// Ferries a rendered NSImage across the actor boundary. NSImage isn't `Sendable`,
/// but the instance we pass is freshly created, immutable and handed off exactly
/// once — so the unchecked conformance is safe here.
private struct ToneOut: @unchecked Sendable {
    let tone: CGImage?
    let image: NSImage?
}

/// On-screen crop frame + the image draw rect that maps `cropNorm` onto that frame.
struct CropLayout { let cropView: CGRect; let imgRect: CGRect }

// MARK: - Visual overlay (no gestures)

private struct CropVisual: View {
    let cropRect: CGRect
    let bounds: CGRect
    let hovered: CropZone?

    private let bracketLen: CGFloat = 20
    private let bracketWidth: CGFloat = 3

    private var r: CGRect { cropRect }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Dim everything outside the fixed crop frame.
            Rectangle().fill(.black.opacity(0.55))
                .frame(width: bounds.width, height: bounds.height)
                .position(x: bounds.midX, y: bounds.midY)
                .mask(ZStack {
                    Rectangle().frame(width: bounds.width, height: bounds.height)
                        .position(x: bounds.midX, y: bounds.midY)
                    Rectangle().frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY).blendMode(.destinationOut)
                })

            // Rule of thirds.
            ForEach(1..<3) { i in
                Rectangle().fill(.white.opacity(0.35)).frame(width: 0.75, height: r.height)
                    .position(x: r.minX + r.width * CGFloat(i) / 3, y: r.midY)
                Rectangle().fill(.white.opacity(0.35)).frame(width: r.width, height: 0.75)
                    .position(x: r.midX, y: r.minY + r.height * CGFloat(i) / 3)
            }

            // Border.
            Rectangle().strokeBorder(.black.opacity(0.35), lineWidth: 3)
                .frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY)
            Rectangle().strokeBorder(.white.opacity(0.9), lineWidth: 1)
                .frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY)

            edgeBar(.top, CGPoint(x: r.midX, y: r.minY), horizontal: true)
            edgeBar(.bottom, CGPoint(x: r.midX, y: r.maxY), horizontal: true)
            edgeBar(.left, CGPoint(x: r.minX, y: r.midY), horizontal: false)
            edgeBar(.right, CGPoint(x: r.maxX, y: r.midY), horizontal: false)
            bracket(.tl, CGPoint(x: r.minX, y: r.minY))
            bracket(.tr, CGPoint(x: r.maxX, y: r.minY))
            bracket(.bl, CGPoint(x: r.minX, y: r.maxY))
            bracket(.br, CGPoint(x: r.maxX, y: r.maxY))
        }
    }

    private func bracket(_ z: CropZone, _ p: CGPoint) -> some View {
        let len = bracketLen
        let cx: CGFloat = (z == .tl || z == .bl) ? p.x + len / 2 : p.x - len / 2
        let cy: CGFloat = (z == .tl || z == .tr) ? p.y + len / 2 : p.y - len / 2
        let hot = hovered == z
        return CornerBracket(zone: z)
            .stroke(.white, style: StrokeStyle(lineWidth: bracketWidth, lineCap: .round))
            .frame(width: len, height: len)
            .scaleEffect(hot ? 1.3 : 1)
            .shadow(color: hot ? .white.opacity(0.7) : .black.opacity(0.5), radius: hot ? 3 : 1)
            .position(x: cx, y: cy)
            .animation(.easeOut(duration: 0.12), value: hovered)
    }

    private func edgeBar(_ z: CropZone, _ p: CGPoint, horizontal: Bool) -> some View {
        let long: CGFloat = 26, short: CGFloat = 4
        let hot = hovered == z
        return RoundedRectangle(cornerRadius: short / 2).fill(.white)
            .frame(width: horizontal ? long : short, height: horizontal ? short : long)
            .scaleEffect(hot ? 1.4 : 1)
            .shadow(color: hot ? .white.opacity(0.7) : .black.opacity(0.5), radius: hot ? 3 : 1)
            .position(x: p.x, y: p.y)
            .animation(.easeOut(duration: 0.12), value: hovered)
    }

    private struct CornerBracket: Shape {
        let zone: CropZone
        func path(in rect: CGRect) -> Path {
            let x0 = rect.minX, y0 = rect.minY, x1 = rect.maxX, y1 = rect.maxY
            var p = Path()
            switch zone {
            case .tl: p.move(to: .init(x: x0, y: y1)); p.addLine(to: .init(x: x0, y: y0)); p.addLine(to: .init(x: x1, y: y0))
            case .tr: p.move(to: .init(x: x0, y: y0)); p.addLine(to: .init(x: x1, y: y0)); p.addLine(to: .init(x: x1, y: y1))
            case .bl: p.move(to: .init(x: x0, y: y0)); p.addLine(to: .init(x: x0, y: y1)); p.addLine(to: .init(x: x1, y: y1))
            case .br: p.move(to: .init(x: x1, y: y0)); p.addLine(to: .init(x: x1, y: y1)); p.addLine(to: .init(x: x0, y: y1))
            default: break
            }
            return p
        }
    }
}

extension NSImage {
    func rotatedClockwise(byDegrees deg: Double) -> NSImage {
        if deg == 0 { return self }
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return self }
        let rad = -deg * .pi / 180
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let ac = abs(cos(rad)), asn = abs(sin(rad))
        let newW = Int((w * ac + h * asn).rounded()), newH = Int((w * asn + h * ac).rounded())
        guard newW > 0, newH > 0,
              let ctx = CGContext(data: nil, width: newW, height: newH, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return self }
        ctx.translateBy(x: CGFloat(newW) / 2, y: CGFloat(newH) / 2)
        ctx.rotate(by: rad)
        ctx.translateBy(x: -w / 2, y: -h / 2)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage() else { return self }
        return NSImage(cgImage: out, size: NSSize(width: newW, height: newH))
    }
}
