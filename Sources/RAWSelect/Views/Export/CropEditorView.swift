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

/// Lightroom-style crop: the image stays fixed, the crop **grid** shrinks. Corner
/// & edge handles resize the grid (anchored on the opposite side), dragging inside
/// moves the grid, dragging in the **margin outside** rotates the whole image.
/// One unified gesture decides the mode from where the drag starts.
struct CropEditorView: View {
    let previewURL: URL
    @Binding var edit: ImageEdit

    @State private var baseCI: CIImage?
    @State private var displayImage: NSImage?
    @State private var cropNorm = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var aspect: AspectPreset = .free
    @State private var portrait = false
    @State private var locked = true                 // default: original aspect

    @State private var dragZone: CropZone?
    @State private var startCrop: CGRect?
    @State private var startStraighten: Double = 0
    @State private var startAngle: CGFloat = 0
    @State private var hoveredZone: CropZone?

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
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
            topControls
            GeometryReader { geo in workspace(in: geo.size) }
                .background(Color(white: 0.11))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.06), lineWidth: 1))
            sliderControls
        }
        .task(id: previewURL) { await loadImage() }
        .onChange(of: cropNorm) { _, v in edit.crop = (v == full) ? nil : v }
    }

    @ViewBuilder
    private func workspace(in c: CGSize) -> some View {
        if let img = displayImage {
            let frame = fittedRect(imageSize: img.size, in: c)
            let showRotate = hoveredZone == .rotate || dragZone == .rotate
            ZStack {
                Image(nsImage: img).resizable()
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)

                CropVisual(cropNorm: cropNorm, imageFrame: frame, hovered: hoveredZone)
                    .allowsHitTesting(false)

                if showRotate {
                    rotateHint.position(x: frame.midX, y: frame.maxY - 24).allowsHitTesting(false)
                }
            }
            .frame(width: c.width, height: c.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { dragChanged($0, frame: frame) }
                    .onEnded { _ in dragZone = nil; startCrop = nil }
            )
            .onContinuousHover { hover($0, frame: frame) }
            .animation(.easeOut(duration: 0.15), value: showRotate)
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var rotateHint: some View {
        HStack(spacing: 6) { Image(systemName: "rotate.right"); Text("Ziehen zum Drehen") }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
    }

    // MARK: Hit testing

    private func screenRect(in frame: CGRect) -> CGRect {
        CGRect(x: frame.minX + cropNorm.minX * frame.width,
               y: frame.minY + cropNorm.minY * frame.height,
               width: cropNorm.width * frame.width,
               height: cropNorm.height * frame.height)
    }

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

    private func dragChanged(_ v: DragGesture.Value, frame: CGRect) {
        if dragZone == nil {
            dragZone = zone(at: v.startLocation, rect: screenRect(in: frame))
            startCrop = cropNorm
            startStraighten = edit.straighten
            startAngle = atan2(v.startLocation.y - frame.midY, v.startLocation.x - frame.midX)
        }
        guard let z = dragZone else { return }

        if z == .rotate {
            let ang = atan2(v.location.y - frame.midY, v.location.x - frame.midX)
            var deg = startStraighten + Double((ang - startAngle) * 180 / .pi)
            deg = min(max(deg, -15), 15)
            if abs(deg - edit.straighten) > 0.01 { edit.straighten = deg; updateDisplay() }
            return
        }

        guard let s = startCrop, frame.width > 0, frame.height > 0 else { return }
        let dx = v.translation.width / frame.width
        let dy = v.translation.height / frame.height
        let a = aspectNorm
        var r = s
        switch z {
        case .move:
            r.origin.x = min(max(0, s.minX + dx), 1 - s.width)
            r.origin.y = min(max(0, s.minY + dy), 1 - s.height)
            cropNorm = r; return
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
        if r.minX >= 0, r.minY >= 0, r.maxX <= 1, r.maxY <= 1, r.width >= minSize, r.height >= minSize {
            cropNorm = r
        }
    }

    private func hover(_ phase: HoverPhase, frame: CGRect) {
        switch phase {
        case .active(let p):
            let z = zone(at: p, rect: screenRect(in: frame))
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

    private var sliderControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "angle").foregroundStyle(.secondary).frame(width: 16)
                Slider(value: Binding(get: { edit.straighten }, set: { edit.straighten = $0; updateDisplay() }), in: -15...15)
                Text(String(format: "%+.1f°", edit.straighten)).monospacedDigit().frame(width: 52, alignment: .trailing)
                Button("0") { edit.straighten = 0; updateDisplay() }
                    .buttonStyle(.borderless).disabled(edit.straighten == 0).help("Ausrichtung zurücksetzen")
            }
            HStack(spacing: 10) {
                Image(systemName: "sun.max").foregroundStyle(.secondary).frame(width: 16)
                Slider(value: Binding(get: { edit.exposure }, set: { edit.exposure = $0; updateDisplay() }), in: -5...5)
                Text(String(format: "%+.2f", edit.exposure)).monospacedDigit().frame(width: 52, alignment: .trailing)
                Button("0") { edit.exposure = 0; updateDisplay() }
                    .buttonStyle(.borderless).disabled(edit.exposure == 0).help("Belichtung zurücksetzen")
            }
        }
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
            let f = CIFilter(name: "CIExposureAdjust")
            f?.setValue(ci, forKey: kCIInputImageKey)
            f?.setValue(edit.exposure, forKey: kCIInputEVKey)
            ci = f?.outputImage ?? ci
        }
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return }
        let ns = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        displayImage = ns.rotatedClockwise(byDegrees: edit.totalAngle)
    }
}

// MARK: - Visual overlay (no gestures)

private struct CropVisual: View {
    let cropNorm: CGRect
    let imageFrame: CGRect
    let hovered: CropZone?

    private let bracketLen: CGFloat = 20
    private let bracketWidth: CGFloat = 3

    private var r: CGRect {
        CGRect(x: imageFrame.minX + cropNorm.minX * imageFrame.width,
               y: imageFrame.minY + cropNorm.minY * imageFrame.height,
               width: cropNorm.width * imageFrame.width,
               height: cropNorm.height * imageFrame.height)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Dim outside the crop.
            Rectangle().fill(.black.opacity(0.5))
                .frame(width: imageFrame.width, height: imageFrame.height)
                .position(x: imageFrame.midX, y: imageFrame.midY)
                .mask(ZStack {
                    Rectangle().frame(width: imageFrame.width, height: imageFrame.height)
                        .position(x: imageFrame.midX, y: imageFrame.midY)
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
