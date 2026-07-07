import Foundation
import AppKit

/// Headless verification of the core workflow, runnable without the GUI:
///   scan → RAW+JPG grouping → session save/load → copy with conflict handling.
/// Invoked via `RAWSelect --selftest`.
enum SelfTest {

    static func run() {
        var failures = 0
        func check(_ condition: Bool, _ label: String) {
            if condition { print("  ✓ \(label)") }
            else { print("  ✗ \(label)"); failures += 1 }
        }

        print("RAW Select self-test")
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rawselect-selftest-\(UUID().uuidString)")
        let sub = root.appendingPathComponent("day1")
        try? fm.createDirectory(at: sub, withIntermediateDirectories: true)

        // A real PNG (so ImageIO thumbnailing has something valid to chew on)…
        let realPNG = sub.appendingPathComponent("IMG_0001.JPG")
        writePNG(to: realPNG, size: 64)
        // …plus a fake RAW sibling (same base name -> should group together).
        let fakeRAW = sub.appendingPathComponent("IMG_0001.ARW")
        try? Data("fake-raw".utf8).write(to: fakeRAW)
        // A standalone JPG and an unsupported file.
        writePNG(to: sub.appendingPathComponent("IMG_0002.JPG"), size: 48)
        try? Data("nope".utf8).write(to: sub.appendingPathComponent("notes.txt"))

        // 1. Scan + grouping
        let groups = PhotoScanner.scan(root: root)
        check(groups.count == 2, "scan groups RAW+JPG into 2 photos (got \(groups.count))")
        let paired = groups.first { $0.baseName == "IMG_0001" }
        check(paired?.files.count == 2, "IMG_0001 pairs ARW+JPG (got \(paired?.files.count ?? 0))")
        check(paired?.previewURL.pathExtension.lowercased() == "jpg", "preview prefers JPG over RAW")
        check(paired?.displayName.hasSuffix(".ARW") == true, "display name prefers RAW")

        // 2. Thumbnail from the real image
        let thumb = ThumbnailLoader.makeThumbnail(url: realPNG, maxPixel: 128)
        check(thumb != nil, "ImageIO produces a thumbnail")

        // 3. Session save/load round-trip
        SessionStore.save(root: root, marks: [paired!.id: 3])
        let loaded = SessionStore.load(root: root)
        check(loaded[paired!.id] == 3, "session persists mark 3 for the photo")

        // 4. Copy marked into per-mark subfolder, twice, to exercise conflicts
        var marked = groups
        for i in marked.indices where marked[i].id == paired!.id { marked[i].mark = 3 }
        let target = root.appendingPathComponent("out")
        try? fm.createDirectory(at: target, withIntermediateDirectories: true)

        do {
            let first = try FileOperationService.perform(.copy, groups: marked, targetRoot: target,
                                                         progress: { _, _ in }, isCancelled: { false })
            let second = try FileOperationService.perform(.copy, groups: marked, targetRoot: target,
                                                          progress: { _, _ in }, isCancelled: { false })
            check(first.files == 2, "first copy writes 2 files")
            let markDir = target.appendingPathComponent("03_Mark_3")
            let contents = (try? fm.contentsOfDirectory(atPath: markDir.path)) ?? []
            check(contents.contains("IMG_0001.ARW"), "original file kept its name")
            check(contents.contains("IMG_0001_1.ARW"), "conflict appended _1 instead of overwriting")
            check(contents.count == 4, "no overwrite: 4 files after two copies (got \(contents.count))")
            _ = second
        } catch {
            check(false, "copy threw: \(error.localizedDescription)")
        }

        // 5. Source files untouched (originals protected)
        check(fm.fileExists(atPath: fakeRAW.path), "source RAW untouched after copy")

        try? fm.removeItem(at: root)
        print(failures == 0 ? "\nALL PASSED ✅" : "\n\(failures) FAILED ❌")
    }

    private static func writePNG(to url: URL, size: Int) {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = ctx
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
        ctx.flushGraphics()
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
        }
    }
}
