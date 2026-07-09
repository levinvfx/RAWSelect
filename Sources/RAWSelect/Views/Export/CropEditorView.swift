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

/// Non-destructive crop + rotate + straighten (+ optional live exposure) editor
/// for one image. All values are stored in `edit`; nothing touches the original.
struct CropEditorView: View {
    let previewURL: URL
    @Binding var edit: ImageEdit

    @State private var baseCI: CIImage?
    @State private var displayImage: NSImage?
    @State private var cropNorm = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var aspect: AspectPreset = .free
    @State private var portrait = false
    // Default: keep the original RAW aspect ratio locked (not free-form).
    @State private var locked = true

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let full = CGRect(x: 0, y: 0, width: 1, height: 1)

    /// Crop aspect (normalised w/h) enforced while dragging, or nil for free.
    private var aspectNorm: CGFloat? {
        guard let img = displayImage, img.size.height > 0 else { return nil }
        let imgAspect = img.size.width / img.size.height
        if var r = aspect.ratio {
            if portrait { r = 1 / r }
            return r / imgAspect
        }
        if locked, cropNorm.height > 0 { return cropNorm.width / cropNorm.height }
        return nil
    }

    var body: some View {
        VStack(spacing: 12) {
            // Crop tools live ABOVE the image (rotate / aspect / lock / reset).
            topControls

            GeometryReader { geo in
                ZStack {
                    if let img = displayImage {
                        let frame = fittedRect(imageSize: img.size, in: geo.size)
                        Image(nsImage: img).resizable()
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                        CropRectOverlay(cropNorm: $cropNorm, imageFrame: frame, aspectNorm: aspectNorm)
                    } else { ProgressView() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Neutral dark surround like Lightroom's crop workspace – keeps the
            // eye on the photo regardless of app theme.
            .background(Color(white: 0.11))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.06), lineWidth: 1))

            // Only the fine-adjust sliders live BELOW the image.
            sliderControls
        }
        .task(id: previewURL) { await loadImage() }
        .onChange(of: cropNorm) { _, v in edit.crop = (v == full) ? nil : v }
    }

    private var topControls: some View {
        HStack(spacing: 10) {
            Button { rotate(-1) } label: { Image(systemName: "rotate.left") }
            Button { rotate(1) } label: { Image(systemName: "rotate.right") }
            Picker("", selection: $aspect) { ForEach(AspectPreset.allCases) { Text($0.label).tag($0) } }
                .frame(width: 90).labelsHidden()
                .onChange(of: aspect) { _, _ in applyAspect() }
            Button { portrait.toggle(); applyAspect() } label: { Image(systemName: "rotate.right.fill") }
                .help("Hoch-/Querformat").disabled(aspect == .free)
            Toggle(isOn: $locked) { Image(systemName: locked ? "lock.fill" : "lock.open") }
                .toggleStyle(.button).help("Seitenverhältnis sperren")
            Spacer()
            Button("Zurücksetzen") { cropNorm = full; aspect = .free; locked = true }
                .disabled(cropNorm == full && edit.straighten == 0)
        }
        .buttonStyle(.bordered)
    }

    private var sliderControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "angle").foregroundStyle(.secondary).frame(width: 16)
                Slider(value: Binding(get: { edit.straighten }, set: { edit.straighten = $0; updateDisplay() }), in: -15...15)
                Text(String(format: "%+.1f°", edit.straighten)).monospacedDigit().frame(width: 52, alignment: .trailing)
                Button("0") { edit.straighten = 0; updateDisplay() }
                    .buttonStyle(.borderless).disabled(edit.straighten == 0)
                    .help("Ausrichtung zurücksetzen")
            }

            // Manuelle Belichtung – wie Lightrooms Exposure-Regler (−5…+5 Blenden).
            // Der Wert wird 1:1 als crs:Exposure2012 exportiert (+1.0 = +1.00 in LR).
            HStack(spacing: 10) {
                Image(systemName: "sun.max").foregroundStyle(.secondary)
                Slider(value: Binding(get: { edit.exposure }, set: { edit.exposure = $0; updateDisplay() }), in: -5...5)
                Text(String(format: "%+.2f", edit.exposure)).monospacedDigit().frame(width: 52, alignment: .trailing)
                Button("0") { edit.exposure = 0; updateDisplay() }
                    .buttonStyle(.borderless).disabled(edit.exposure == 0)
                    .help("Belichtung zurücksetzen")
            }
        }
    }

    // MARK: image pipeline

    private func loadImage() async {
        let img = await ThumbnailLoader.shared.thumbnail(for: previewURL, maxPixel: 1600)
        if let cg = img?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            baseCI = CIImage(cgImage: cg)
        }
        cropNorm = edit.crop ?? full
        updateDisplay()
    }

    private func updateDisplay() {
        guard let base = baseCI else { return }
        var ci = base
        if edit.exposure != 0 {
            // Approximates Lightroom's stop-based Exposure for WYSIWYG preview.
            let f = CIFilter(name: "CIExposureAdjust")
            f?.setValue(ci, forKey: kCIInputImageKey)
            f?.setValue(edit.exposure, forKey: kCIInputEVKey)
            ci = f?.outputImage ?? ci
        }
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return }
        let ns = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        displayImage = ns.rotatedClockwise(byDegrees: edit.totalAngle)
    }

    private func rotate(_ dir: Int) {
        if dir < 0 { edit.rotateLeft() } else { edit.rotateRight() }
        cropNorm = full
        updateDisplay()
    }

    private func applyAspect() {
        guard let r = aspectNorm else { return }
        // Centered max-fit rect with the wanted normalised ratio (r = w/h).
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
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }
}

/// Draggable crop rectangle (4 corner handles + move), optionally aspect-locked.
private struct CropRectOverlay: View {
    @Binding var cropNorm: CGRect
    let imageFrame: CGRect
    var aspectNorm: CGFloat?
    @State private var start: CGRect?

    private enum Corner { case tl, tr, bl, br, top, bottom, left, right, move }
    private let minSize: CGFloat = 0.06
    private let bracketLen: CGFloat = 20      // L-shaped corner arm length
    private let bracketWidth: CGFloat = 3
    private let hitSlop: CGFloat = 30         // invisible drag target around a handle

    private var screenRect: CGRect {
        CGRect(x: imageFrame.minX + cropNorm.minX * imageFrame.width,
               y: imageFrame.minY + cropNorm.minY * imageFrame.height,
               width: cropNorm.width * imageFrame.width,
               height: cropNorm.height * imageFrame.height)
    }

    var body: some View {
        let dragging = start != nil
        return ZStack(alignment: .topLeading) {
            // Dim everything outside the crop rectangle. Darkens a touch while
            // dragging to emphasise the framed area (Lightroom behaviour).
            Rectangle().fill(.black.opacity(dragging ? 0.6 : 0.45))
                .frame(width: imageFrame.width, height: imageFrame.height)
                .position(x: imageFrame.midX, y: imageFrame.midY)
                .mask(
                    ZStack {
                        Rectangle().frame(width: imageFrame.width, height: imageFrame.height)
                            .position(x: imageFrame.midX, y: imageFrame.midY)
                        Rectangle().frame(width: screenRect.width, height: screenRect.height)
                            .position(x: screenRect.midX, y: screenRect.midY).blendMode(.destinationOut)
                    })
                .allowsHitTesting(false)

            // Rule-of-thirds grid. Thin lines with a faint dark shadow so they
            // stay visible over bright skies; brighter while actively dragging.
            gridLines(opacity: dragging ? 0.55 : 0.3)

            // Frame border: subtle dark halo under a thin white line for contrast.
            Rectangle().strokeBorder(.black.opacity(0.35), lineWidth: 3)
                .frame(width: screenRect.width, height: screenRect.height)
                .position(x: screenRect.midX, y: screenRect.midY)
                .allowsHitTesting(false)
            Rectangle().strokeBorder(.white.opacity(0.9), lineWidth: 1)
                .frame(width: screenRect.width, height: screenRect.height)
                .position(x: screenRect.midX, y: screenRect.midY)
                .contentShape(Rectangle()).gesture(drag(.move))

            // Edge handles (mid-side bars) then corner brackets on top.
            edgeHandle(.top,    CGPoint(x: screenRect.midX, y: screenRect.minY), horizontal: true)
            edgeHandle(.bottom, CGPoint(x: screenRect.midX, y: screenRect.maxY), horizontal: true)
            edgeHandle(.left,   CGPoint(x: screenRect.minX, y: screenRect.midY), horizontal: false)
            edgeHandle(.right,  CGPoint(x: screenRect.maxX, y: screenRect.midY), horizontal: false)

            cornerBracket(.tl, CGPoint(x: screenRect.minX, y: screenRect.minY))
            cornerBracket(.tr, CGPoint(x: screenRect.maxX, y: screenRect.minY))
            cornerBracket(.bl, CGPoint(x: screenRect.minX, y: screenRect.maxY))
            cornerBracket(.br, CGPoint(x: screenRect.maxX, y: screenRect.maxY))
        }
    }

    private func gridLines(opacity: Double) -> some View {
        ForEach(1..<3) { i in
            let x = screenRect.minX + screenRect.width * CGFloat(i) / 3
            let y = screenRect.minY + screenRect.height * CGFloat(i) / 3
            Group {
                Rectangle().fill(.white.opacity(opacity)).frame(width: 0.75, height: screenRect.height)
                    .position(x: x, y: screenRect.midY)
                Rectangle().fill(.white.opacity(opacity)).frame(width: screenRect.width, height: 0.75)
                    .position(x: screenRect.midX, y: y)
            }
            .shadow(color: .black.opacity(0.3), radius: 0.5)
            .allowsHitTesting(false)
        }
    }

    // L-shaped corner handle whose vertex sits exactly on the crop corner.
    private func cornerBracket(_ c: Corner, _ p: CGPoint) -> some View {
        let len = bracketLen
        // Offset the frame so the L's vertex lands on point `p`.
        let cx: CGFloat = (c == .tl || c == .bl) ? p.x + len / 2 : p.x - len / 2
        let cy: CGFloat = (c == .tl || c == .tr) ? p.y + len / 2 : p.y - len / 2
        return ZStack {
            CornerBracket(corner: c)
                .stroke(.white, style: StrokeStyle(lineWidth: bracketWidth, lineCap: .round))
                .frame(width: len, height: len)
                .shadow(color: .black.opacity(0.5), radius: 1)
                .position(x: cx, y: cy)
                .allowsHitTesting(false)
            hitTarget(size: len + hitSlop, at: p, for: c)
        }
    }

    // Mid-edge handle: a small rounded bar centred on `p`.
    private func edgeHandle(_ c: Corner, _ p: CGPoint, horizontal: Bool) -> some View {
        let long: CGFloat = 26, short: CGFloat = 4
        return ZStack {
            RoundedRectangle(cornerRadius: short / 2).fill(.white)
                .frame(width: horizontal ? long : short, height: horizontal ? short : long)
                .shadow(color: .black.opacity(0.5), radius: 1)
                .position(x: p.x, y: p.y)
                .allowsHitTesting(false)
            hitTarget(size: long + hitSlop, at: p, for: c)
        }
    }

    // Invisible, generously sized drag target centred on a handle point.
    private func hitTarget(size: CGFloat, at p: CGPoint, for c: Corner) -> some View {
        Color.clear
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .position(x: p.x, y: p.y)
            .gesture(drag(c))
    }

    private func drag(_ c: Corner) -> some Gesture {
        DragGesture()
            .onChanged { v in
                if start == nil { start = cropNorm }
                guard let s = start, imageFrame.width > 0, imageFrame.height > 0 else { return }
                let dx = v.translation.width / imageFrame.width
                let dy = v.translation.height / imageFrame.height
                var r = s
                switch c {
                case .move:
                    r.origin.x = min(max(0, s.minX + dx), 1 - s.width)
                    r.origin.y = min(max(0, s.minY + dy), 1 - s.height)
                    cropNorm = r; return
                case .tl:
                    let nx = min(max(0, s.minX + dx), s.maxX - minSize)
                    var ny = min(max(0, s.minY + dy), s.maxY - minSize)
                    if let a = aspectNorm { ny = s.maxY - (s.maxX - nx) / a }
                    r = CGRect(x: nx, y: ny, width: s.maxX - nx, height: s.maxY - ny)
                case .tr:
                    let mx = min(max(s.minX + minSize, s.maxX + dx), 1)
                    var ny = min(max(0, s.minY + dy), s.maxY - minSize)
                    if let a = aspectNorm { ny = s.maxY - (mx - s.minX) / a }
                    r = CGRect(x: s.minX, y: ny, width: mx - s.minX, height: s.maxY - ny)
                case .bl:
                    let nx = min(max(0, s.minX + dx), s.maxX - minSize)
                    var my = min(max(s.minY + minSize, s.maxY + dy), 1)
                    if let a = aspectNorm { my = s.minY + (s.maxX - nx) / a }
                    r = CGRect(x: nx, y: s.minY, width: s.maxX - nx, height: my - s.minY)
                case .br:
                    let mx = min(max(s.minX + minSize, s.maxX + dx), 1)
                    var my = min(max(s.minY + minSize, s.maxY + dy), 1)
                    if let a = aspectNorm { my = s.minY + (mx - s.minX) / a }
                    r = CGRect(x: s.minX, y: s.minY, width: mx - s.minX, height: my - s.minY)
                case .left:
                    let nx = min(max(0, s.minX + dx), s.maxX - minSize)
                    let w = s.maxX - nx
                    if let a = aspectNorm { let h = w / a; r = CGRect(x: nx, y: s.midY - h / 2, width: w, height: h) }
                    else { r = CGRect(x: nx, y: s.minY, width: w, height: s.height) }
                case .right:
                    let mx = min(max(s.minX + minSize, s.maxX + dx), 1)
                    let w = mx - s.minX
                    if let a = aspectNorm { let h = w / a; r = CGRect(x: s.minX, y: s.midY - h / 2, width: w, height: h) }
                    else { r = CGRect(x: s.minX, y: s.minY, width: w, height: s.height) }
                case .top:
                    let ny = min(max(0, s.minY + dy), s.maxY - minSize)
                    let h = s.maxY - ny
                    if let a = aspectNorm { let w = h * a; r = CGRect(x: s.midX - w / 2, y: ny, width: w, height: h) }
                    else { r = CGRect(x: s.minX, y: ny, width: s.width, height: h) }
                case .bottom:
                    let my = min(max(s.minY + minSize, s.maxY + dy), 1)
                    let h = my - s.minY
                    if let a = aspectNorm { let w = h * a; r = CGRect(x: s.midX - w / 2, y: s.minY, width: w, height: h) }
                    else { r = CGRect(x: s.minX, y: s.minY, width: s.width, height: h) }
                }
                // Clamp inside [0,1].
                if r.minX >= 0, r.minY >= 0, r.maxX <= 1, r.maxY <= 1, r.width >= minSize, r.height >= minSize {
                    cropNorm = r
                }
            }
            .onEnded { _ in start = nil }
    }

    /// L-shaped path for a corner handle, drawn in a `len × len` box with its
    /// vertex at the box corner matching `corner`.
    private struct CornerBracket: Shape {
        let corner: Corner
        func path(in rect: CGRect) -> Path {
            let x0 = rect.minX, y0 = rect.minY, x1 = rect.maxX, y1 = rect.maxY
            var p = Path()
            switch corner {
            case .tl: p.move(to: CGPoint(x: x0, y: y1)); p.addLine(to: CGPoint(x: x0, y: y0)); p.addLine(to: CGPoint(x: x1, y: y0))
            case .tr: p.move(to: CGPoint(x: x0, y: y0)); p.addLine(to: CGPoint(x: x1, y: y0)); p.addLine(to: CGPoint(x: x1, y: y1))
            case .bl: p.move(to: CGPoint(x: x0, y: y0)); p.addLine(to: CGPoint(x: x0, y: y1)); p.addLine(to: CGPoint(x: x1, y: y1))
            case .br: p.move(to: CGPoint(x: x1, y: y0)); p.addLine(to: CGPoint(x: x1, y: y1)); p.addLine(to: CGPoint(x: x0, y: y1))
            default: break
            }
            return p
        }
    }
}

extension NSImage {
    /// Rotated clockwise by an arbitrary angle, expanded to the bounding box
    /// (expands to bounding box). Transparent corners for non-90° angles.
    func rotatedClockwise(byDegrees deg: Double) -> NSImage {
        if deg == 0 { return self }
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return self }
        let rad = -deg * .pi / 180                      // clockwise
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
