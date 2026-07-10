import Foundation
import AppKit

/// Headless verification of the core workflow, runnable without the GUI:
///   scan → RAW+JPG grouping → XMP sidecars → mark persistence (volume identity)
///   → flat copy with/without XMP and conflict handling.
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

        let realJPG = sub.appendingPathComponent("IMG_0001.JPG")
        writePNG(to: realJPG, size: 64)
        let fakeRAW = sub.appendingPathComponent("IMG_0001.ARW")
        try? Data("fake-raw".utf8).write(to: fakeRAW)
        // Two common XMP naming styles for the same photo.
        try? Data("<xmp/>".utf8).write(to: sub.appendingPathComponent("IMG_0001.xmp"))
        try? Data("<xmp/>".utf8).write(to: sub.appendingPathComponent("IMG_0001.ARW.xmp"))
        writePNG(to: sub.appendingPathComponent("IMG_0002.JPG"), size: 48)
        try? Data("nope".utf8).write(to: sub.appendingPathComponent("notes.txt"))

        // 1. Scan + grouping + sidecars
        let groups = PhotoScanner.scan(root: root)
        check(groups.count == 2, "scan groups into 2 photos (got \(groups.count))")
        let paired = groups.first { $0.baseName == "IMG_0001" }
        check(paired?.files.count == 2, "IMG_0001 pairs ARW+JPG (got \(paired?.files.count ?? 0))")
        check(paired?.sidecars.count == 2, "both XMP sidecars attached (got \(paired?.sidecars.count ?? 0))")
        check(paired?.previewURL.pathExtension.lowercased() == "jpg", "preview prefers JPG over RAW")
        check(paired?.displayName.hasSuffix(".ARW") == true, "display name prefers RAW")

        // 2. Thumbnail from the real image
        check(ThumbnailLoader.makeThumbnail(url: realJPG, maxPixel: 1280) != nil, "ImageIO produces a preview")

        // 3. Mark persistence via volume identity
        let identity = FolderIdentity(root: root)
        let key = identity.persistKey(directory: paired!.directory, baseName: paired!.baseName)
        SessionStore.save(identityID: identity.id, states: [key: .init(mark: 3)])
        let loadedState = SessionStore.load(identityID: identity.id)[key]
        check(loadedState?.mark == 3, "mark persists under volume-identity key")
        // Same physical volume, different subfolder opened later → still remembered.
        let identity2 = FolderIdentity(root: sub)
        let key2 = identity2.persistKey(directory: paired!.directory, baseName: paired!.baseName)
        check(SessionStore.load(identityID: identity2.id)[key2]?.mark == 3, "state survives opening a different subfolder")

        // 4. Flat copy WITH sidecars, twice, to exercise conflicts
        let target = root.appendingPathComponent("out")
        do {
            let first = try FileOperationService.perform(.copy, groups: [paired!], targetRoot: target,
                                                         includeSidecars: true, progress: { _, _ in }, isCancelled: { false })
            _ = try FileOperationService.perform(.copy, groups: [paired!], targetRoot: target,
                                                 includeSidecars: true, progress: { _, _ in }, isCancelled: { false })
            check(first.files == 4, "first copy writes 4 files (2 images + 2 xmp), got \(first.files)")
            let contents = Set((try? fm.contentsOfDirectory(atPath: target.path)) ?? [])
            check(contents.contains("IMG_0001.ARW"), "original file kept its name")
            check(contents.contains("IMG_0001_1.ARW"), "conflict appended _1 instead of overwriting")
            check(contents.count == 8, "no overwrite: 8 files after two copies (got \(contents.count))")
        } catch { check(false, "copy threw: \(error.localizedDescription)") }

        // 5. Flat copy WITHOUT sidecars
        let target2 = root.appendingPathComponent("out_noxmp")
        do {
            let out = try FileOperationService.perform(.copy, groups: [paired!], targetRoot: target2,
                                                       includeSidecars: false, progress: { _, _ in }, isCancelled: { false })
            let contents = Set((try? fm.contentsOfDirectory(atPath: target2.path)) ?? [])
            check(out.files == 2, "without XMP copies only the 2 images (got \(out.files))")
            check(!contents.contains(where: { $0.hasSuffix(".xmp") }), "no XMP copied when excluded")
        } catch { check(false, "copy(no xmp) threw: \(error.localizedDescription)") }

        // 6. Tag filter on/off logic
        var untagged = PhotoGroup(id: "u", directory: root, baseName: "u", files: [realJPG],
                                  previewURL: realJPG, displayName: "u")
        var marked5 = untagged; marked5.mark = 5
        var filter = TagFilter()
        check(filter.matches(untagged) && filter.matches(marked5), "default: everything shown")
        filter.toggle(0)   // hide "Alle" (untagged)
        check(!filter.matches(untagged) && filter.matches(marked5), "toggling 'Alle' hides only untagged")
        filter.toggle(0); filter.toggle(5)   // show all again, then hide mark 5
        check(filter.matches(untagged) && !filter.matches(marked5), "toggling mark 5 hides only mark-5 photos")

        // 7. Smart Exposure (local histogram analysis)
        let dark = sub.appendingPathComponent("dark.png"); writeGrayPNG(to: dark, size: 64, level: 40)
        let bright = sub.appendingPathComponent("bright.png"); writeGrayPNG(to: bright, size: 64, level: 210)
        let midGray = sub.appendingPathComponent("mid.png"); writeGrayPNG(to: midGray, size: 64, level: 118)
        let cfg = SmartExposureAnalyzer.Config()
        let rd = SmartExposureAnalyzer.analyze(url: dark, config: cfg)
        let rb = SmartExposureAnalyzer.analyze(url: bright, config: cfg)
        let rm = SmartExposureAnalyzer.analyze(url: midGray, config: cfg)
        check(rd.clampedEV > 0.05, "dark image → positive EV (\(rd.evLabel))")
        check(rb.clampedEV < -0.05, "bright image → negative EV (\(rb.evLabel))")
        check(abs(rm.clampedEV) < 0.15, "mid-grey image → ~0 EV (\(rm.evLabel))")
        check(abs(rd.clampedEV) <= cfg.maxEV + 0.001, "EV clamped to max")

        // 8. XMP sidecar builder never needs the original; produces valid crs block
        let xmp = XMPPresetBuilder.sidecarXMP(presetURL: nil, evDelta: 0.35)
        check(xmp.contains("crs:Exposure2012=\"+0.35\""), "sidecar embeds exposure delta")

        // 9. Originals protected
        check(fm.fileExists(atPath: fakeRAW.path), "source RAW untouched after copy")

        // 10. ImageEdit geometry
        var edit = ImageEdit()
        edit.rotateRight(); edit.rotateRight()
        check(edit.rotation == 2, "rotateRight cycles (got \(edit.rotation))")
        edit.rotateLeft()
        check(edit.rotation == 1 && abs(edit.totalAngle - 90) < 0.001, "totalAngle = rotation*90 + straighten")
        check(ImageEdit().isIdentity && !edit.isIdentity, "isIdentity reflects edits")

        // 11. TagFilter solo (⌥-Klick, V1.1)
        var solo = TagFilter()
        solo.solo(4)
        check(solo.isShown(4) && !solo.isShown(1) && !solo.isShown(0), "solo shows only that colour")
        solo.solo(4)
        check(solo.allShown, "second solo restores all")

        // 12. Conflict naming avoids disk AND the in-batch used set (Paket-3 fix)
        let uniqDir = root.appendingPathComponent("uniq"); try? fm.createDirectory(at: uniqDir, withIntermediateDirectories: true)
        let u0 = FileOperationService.uniqueDestination(for: "A.jpg", in: uniqDir)
        fm.createFile(atPath: u0.path, contents: Data())
        let u1 = FileOperationService.uniqueDestination(for: "A.jpg", in: uniqDir)
        let u2 = FileOperationService.uniqueDestination(for: "A.jpg", in: uniqDir, avoiding: [u1.path])
        check(u0.lastPathComponent == "A.jpg" && u1.lastPathComponent == "A_1.jpg" && u2.lastPathComponent == "A_2.jpg",
              "uniqueDestination avoids disk + in-batch collisions")

        // 13. Overwrite must NOT collapse two same-named photos in one batch (Paket-3/4b fix)
        let sub2 = root.appendingPathComponent("day2"); try? fm.createDirectory(at: sub2, withIntermediateDirectories: true)
        let clashA = sub.appendingPathComponent("CLASH.JPG"); writePNG(to: clashA, size: 32)
        let clashB = sub2.appendingPathComponent("CLASH.JPG"); writePNG(to: clashB, size: 32)
        let gA = PhotoGroup(id: "a", directory: sub, baseName: "CLASH", files: [clashA], previewURL: clashA, displayName: "CLASH")
        let gB = PhotoGroup(id: "b", directory: sub2, baseName: "CLASH", files: [clashB], previewURL: clashB, displayName: "CLASH")
        let clashTarget = root.appendingPathComponent("clash")
        do {
            let out = try FileOperationService.perform(.copy, groups: [gA, gB], targetRoot: clashTarget,
                                                       includeSidecars: false, conflict: .overwrite,
                                                       progress: { _, _ in }, isCancelled: { false })
            let c = Set((try? fm.contentsOfDirectory(atPath: clashTarget.path)) ?? [])
            check(out.files == 2 && c.count == 2, "overwrite keeps both same-named batch photos (got \(c.count) files)")
        } catch { check(false, "clash copy threw: \(error.localizedDescription)") }

        // 14) Update version comparison handles multi-digit + differing lengths.
        check(UpdateService.isNewer("1.3", than: "1.2"), "1.3 > 1.2")
        check(UpdateService.isNewer("1.10", than: "1.9"), "1.10 > 1.9 (numeric, not lexical)")
        check(UpdateService.isNewer("2", than: "1.9"), "2 > 1.9")
        check(!UpdateService.isNewer("1.2", than: "1.2"), "1.2 == 1.2 → not newer")
        check(!UpdateService.isNewer("1.1", than: "1.2"), "1.1 < 1.2 → not newer")

        try? fm.removeItem(at: root)
        print(failures == 0 ? "\nALL PASSED ✅" : "\n\(failures) FAILED ❌")
        if failures > 0 { exit(1) }
    }

    private static func writeGrayPNG(to url: URL, size: Int, level: Int) {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = ctx
        let g = CGFloat(level) / 255.0
        NSColor(red: g, green: g, blue: g, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
        ctx.flushGraphics()
        if let data = rep.representation(using: .png, properties: [:]) { try? data.write(to: url) }
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
        if let data = rep.representation(using: .png, properties: [:]) { try? data.write(to: url) }
    }
}
