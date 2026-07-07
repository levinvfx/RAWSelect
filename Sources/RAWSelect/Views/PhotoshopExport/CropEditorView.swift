import SwiftUI
import AppKit
import CoreGraphics

/// Simple, non-destructive crop + 90° rotate editor for one image. The crop is
/// stored as a normalised rect in the ROTATED image space; rotation as 90° steps.
struct CropEditorView: View {
    let previewURL: URL
    @Binding var edit: ImageEdit

    @State private var baseImage: NSImage?      // upright preview
    @State private var rotatedImage: NSImage?   // display image (rotated)
    @State private var cropNorm = CGRect(x: 0, y: 0, width: 1, height: 1)

    private let full = CGRect(x: 0, y: 0, width: 1, height: 1)

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                ZStack {
                    if let img = rotatedImage {
                        let frame = fittedRect(imageSize: img.size, in: geo.size)
                        Image(nsImage: img)
                            .resizable()
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                        CropRectOverlay(cropNorm: $cropNorm, imageFrame: frame)
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 12) {
                Button { rotate(-1) } label: { Image(systemName: "rotate.left") }
                Button { rotate(1) } label: { Image(systemName: "rotate.right") }
                Spacer()
                Button("Zuschnitt zurücksetzen") { cropNorm = full }
                    .disabled(cropNorm == full)
            }
            .buttonStyle(.bordered)
        }
        .task(id: previewURL) {
            baseImage = await ThumbnailLoader.shared.thumbnail(for: previewURL, maxPixel: 1600)
            updateRotated()
            cropNorm = edit.crop ?? full
        }
        .onChange(of: cropNorm) { _, v in edit.crop = (v == full) ? nil : v }
    }

    private func rotate(_ dir: Int) {
        if dir < 0 { edit.rotateLeft() } else { edit.rotateRight() }
        cropNorm = full            // crop is relative to the rotated frame → reset
        updateRotated()
    }

    private func updateRotated() {
        rotatedImage = baseImage?.rotatedClockwise(steps: edit.rotation)
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

/// Draggable crop rectangle (4 corner handles + move) over a fixed image frame.
private struct CropRectOverlay: View {
    @Binding var cropNorm: CGRect
    let imageFrame: CGRect
    @State private var start: CGRect?

    private enum Corner { case tl, tr, bl, br, move }
    private let minSize: CGFloat = 0.06
    private let handle: CGFloat = 16

    private var screenRect: CGRect {
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
                .mask(
                    ZStack {
                        Rectangle().frame(width: imageFrame.width, height: imageFrame.height)
                            .position(x: imageFrame.midX, y: imageFrame.midY)
                        Rectangle().frame(width: screenRect.width, height: screenRect.height)
                            .position(x: screenRect.midX, y: screenRect.midY)
                            .blendMode(.destinationOut)
                    }
                )
                .allowsHitTesting(false)

            Rectangle().strokeBorder(.white, lineWidth: 1.5)
                .frame(width: screenRect.width, height: screenRect.height)
                .position(x: screenRect.midX, y: screenRect.midY)
                .contentShape(Rectangle())
                .gesture(drag(.move))

            corner(.tl, at: CGPoint(x: screenRect.minX, y: screenRect.minY))
            corner(.tr, at: CGPoint(x: screenRect.maxX, y: screenRect.minY))
            corner(.bl, at: CGPoint(x: screenRect.minX, y: screenRect.maxY))
            corner(.br, at: CGPoint(x: screenRect.maxX, y: screenRect.maxY))
        }
    }

    private func corner(_ c: Corner, at p: CGPoint) -> some View {
        Circle().fill(.white).frame(width: handle, height: handle)
            .shadow(radius: 1)
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
                case .tl:
                    let nx = min(max(0, s.minX + dx), s.maxX - minSize)
                    let ny = min(max(0, s.minY + dy), s.maxY - minSize)
                    r = CGRect(x: nx, y: ny, width: s.maxX - nx, height: s.maxY - ny)
                case .tr:
                    let mx = min(max(s.minX + minSize, s.maxX + dx), 1)
                    let ny = min(max(0, s.minY + dy), s.maxY - minSize)
                    r = CGRect(x: s.minX, y: ny, width: mx - s.minX, height: s.maxY - ny)
                case .bl:
                    let nx = min(max(0, s.minX + dx), s.maxX - minSize)
                    let my = min(max(s.minY + minSize, s.maxY + dy), 1)
                    r = CGRect(x: nx, y: s.minY, width: s.maxX - nx, height: my - s.minY)
                case .br:
                    let mx = min(max(s.minX + minSize, s.maxX + dx), 1)
                    let my = min(max(s.minY + minSize, s.maxY + dy), 1)
                    r = CGRect(x: s.minX, y: s.minY, width: mx - s.minX, height: my - s.minY)
                }
                cropNorm = r
            }
            .onEnded { _ in start = nil }
    }
}

extension NSImage {
    /// Returns a copy rotated clockwise by `steps` × 90°.
    func rotatedClockwise(steps: Int) -> NSImage {
        let s = ((steps % 4) + 4) % 4
        guard s != 0,
              let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return self }
        let w = cg.width, h = cg.height
        let newW = (s % 2 == 1) ? h : w
        let newH = (s % 2 == 1) ? w : h
        guard let ctx = CGContext(data: nil, width: newW, height: newH, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return self }
        ctx.translateBy(x: CGFloat(newW) / 2, y: CGFloat(newH) / 2)
        ctx.rotate(by: -CGFloat(s) * (.pi / 2))   // clockwise in CG's y-up space
        ctx.translateBy(x: -CGFloat(w) / 2, y: -CGFloat(h) / 2)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage() else { return self }
        return NSImage(cgImage: out, size: NSSize(width: newW, height: newH))
    }
}
