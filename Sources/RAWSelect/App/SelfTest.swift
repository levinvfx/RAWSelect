import Foundation
import AppKit
import CoreImage

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

        // 3. Mark persistence via volume identity.
        //    NEVER save under the real `identity.id`: this test root lives in the temp folder,
        //    which sits on the boot volume — so its id is the exact same one every real folder
        //    on the internal disk uses. Saving here overwrote the user's own marks on every
        //    single build (measured). The identity LOGIC is still tested, just not by clobbering.
        let identity = FolderIdentity(root: root)
        let identity2 = FolderIdentity(root: sub)
        let key = identity.persistKey(directory: paired!.directory, baseName: paired!.baseName)
        let key2 = identity2.persistKey(directory: paired!.directory, baseName: paired!.baseName)
        check(identity.id == identity2.id, "same volume → same identity from a subfolder")
        check(key == key2, "same photo → same persist key from either folder")

        let testID = "selftest-" + UUID().uuidString
        SessionStore.save(identityID: testID, states: [key: .init(mark: 3)], scope: [key])
        check(SessionStore.load(identityID: testID)[key]?.mark == 3, "mark persists under volume-identity key")
        check(SessionStore.load(identityID: testID)[key2]?.mark == 3, "state survives opening a different subfolder")

        // 3b) The whole point of `scope`: one file holds a whole VOLUME, and saving one folder
        //     must not wipe another. Before this, opening a second folder and pressing a single
        //     key erased every mark made in the first one.
        let folderA = ["A/img_0001": SessionStore.PhotoState(mark: 1),
                       "A/img_0002": SessionStore.PhotoState(mark: 2)]
        SessionStore.save(identityID: testID, states: folderA, scope: Set(folderA.keys))
        SessionStore.save(identityID: testID, states: ["B/img_0001": .init(mark: 5)], scope: ["B/img_0001"])
        let both = SessionStore.load(identityID: testID)
        check(both["A/img_0001"]?.mark == 1 && both["A/img_0002"]?.mark == 2, "other folder's marks survive a save")
        check(both["B/img_0001"]?.mark == 5, "new folder's marks are stored")
        // …but clearing a mark inside the scope must still remove it.
        SessionStore.save(identityID: testID, states: [:], scope: Set(folderA.keys))
        let afterClear = SessionStore.load(identityID: testID)
        check(afterClear["A/img_0001"] == nil, "unmarking inside the scope removes the entry")
        check(afterClear["B/img_0001"]?.mark == 5, "…without touching the other folder")

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

        // 14) Develop adjustments map to Camera-Raw sidecar attributes (non-zero only).
        var dev = ImageEdit()
        dev.contrast = 40; dev.temp = -25; dev.whites = 60; dev.highlights = -100
        let devXMP = XMPPresetBuilder.sidecarXMP(presetURL: nil, evDelta: 0, edit: dev,
                                                 asShotWB: (temp: 5500, tint: 0))
        check(devXMP.contains("crs:Contrast2012=\"40\""), "Contrast2012 written")
        check(devXMP.contains("crs:Temperature=\"5475\""), "absolute Temperature = as-shot 5500 + (-25)")
        check(devXMP.contains("crs:WhiteBalance=\"Custom\""), "WhiteBalance forced Custom for absolute WB")
        check(devXMP.contains("crs:Whites2012=\"60\""), "Whites2012 written")
        check(devXMP.contains("crs:Highlights2012=\"-100\""), "Highlights2012 written")
        check(!devXMP.contains("crs:Blacks2012"), "zero adjustment (Blacks) NOT written")
        check(ImageEdit().isIdentity && !dev.isIdentity, "develop breaks isIdentity")

        // 14a) Präsenz/Detail are gone: the app never writes those keys itself, so a preset's
        //      own Clarity/Vibrance/Saturation/Sharpness survive untouched.
        let presenceXMP = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
        <rdf:Description rdf:about="" xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
          crs:Clarity2012="+22" crs:Vibrance="+15" crs:Saturation="-8" crs:Sharpness="55">
        </rdf:Description></rdf:RDF></x:xmpmeta>
        """
        let presenceFile = root.appendingPathComponent("selftest_presence.xmp")
        try? presenceXMP.data(using: .utf8)?.write(to: presenceFile)
        var pv = ImageEdit(); pv.contrast = 10
        let pvXMP = XMPPresetBuilder.sidecarXMP(presetURL: presenceFile, evDelta: 0, edit: pv)
        for k in ["Clarity2012=\"+22\"", "Vibrance=\"+15\"", "Saturation=\"-8\"", "Sharpness=\"55\""] {
            check(pvXMP.contains("crs:" + k), "preset keeps its own crs:\(k.split(separator: "=")[0])")
        }
        try? fm.removeItem(at: presenceFile)

        // 14b) Preset WB is absolute: slider delta adds onto the preset's Temperature/Tint.
        //      Preview render strips local corrections (AI masks); export keeps them.
        let presetXMP = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
        <rdf:Description rdf:about="" xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
          crs:WhiteBalance="Custom" crs:Temperature="6172" crs:Tint="+12">
        <crs:MaskGroupBasedCorrections><rdf:Seq><rdf:li>AI</rdf:li></rdf:Seq></crs:MaskGroupBasedCorrections>
        </rdf:Description></rdf:RDF></x:xmpmeta>
        """
        let presetFile = root.appendingPathComponent("selftest_preset.xmp")
        try? presetXMP.data(using: .utf8)?.write(to: presetFile)
        var wb = ImageEdit(); wb.temp = 300; wb.tint = -5
        let wbXMP = XMPPresetBuilder.sidecarXMP(presetURL: presetFile, evDelta: 0, edit: wb)
        check(wbXMP.contains("crs:Temperature=\"6472\""), "absolute Temperature = preset 6172 + 300")
        check(wbXMP.contains("crs:Tint=\"7\""), "absolute Tint = preset 12 + (-5)")
        let prevXMP = XMPPresetBuilder.sidecarXMP(presetURL: presetFile, evDelta: 0, stripMasks: true)
        check(!prevXMP.contains("MaskGroupBasedCorrections"), "preview strips AI mask block")
        check(wbXMP.contains("MaskGroupBasedCorrections"), "export keeps AI mask block")
        check(XMPPresetBuilder.presetValues(presetFile)["Temperature"] == 6172, "presetValues reads absolute Temperature")
        try? fm.removeItem(at: presetFile)

        // 14b-2) "As Shot" preset (no crs:Temperature at all): the WB base must come from the
        //        RAW's as-shot value, never from an implicit 0 — a +300 delta once exported as
        //        an absolute 300 K (deep blue) while the slider read 6472.
        let asShotPreset = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
        <rdf:Description rdf:about="" xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
          crs:WhiteBalance="As Shot" crs:Contrast2012="-2">
        </rdf:Description></rdf:RDF></x:xmpmeta>
        """
        let asShotFile = root.appendingPathComponent("selftest_asshot.xmp")
        try? asShotPreset.data(using: .utf8)?.write(to: asShotFile)
        var wb2 = ImageEdit(); wb2.temp = 300
        let wbAsShot = XMPPresetBuilder.sidecarXMP(presetURL: asShotFile, evDelta: 0, edit: wb2,
                                                   asShotWB: (temp: 6172, tint: 12))
        check(wbAsShot.contains("crs:Temperature=\"6472\""), "As-Shot preset: WB base = RAW as-shot 6172 + 300")
        check(wbAsShot.contains("crs:Tint=\"12\""), "As-Shot preset: Tint written alongside (Custom needs both)")
        check(wbAsShot.contains("crs:WhiteBalance=\"Custom\""), "As-Shot preset: WhiteBalance switched to Custom")
        // No known base anywhere → writing a bare delta as absolute Kelvin would be wrong.
        // WhiteBalance still goes to Custom: without a Temperature of its own that leaves the
        // picture untouched, and it is the only mode Lightroom reports the Kelvin back from —
        // which is exactly how the base gets discovered in the first place.
        let wbNoBase = XMPPresetBuilder.sidecarXMP(presetURL: asShotFile, evDelta: 0, edit: wb2)
        check(!wbNoBase.contains("crs:Temperature"), "unknown WB base → no absolute Temperature written")
        check(wbNoBase.contains("crs:WhiteBalance=\"Custom\""), "unknown WB base → Custom (probes the Kelvin, image unchanged)")
        check(wbNoBase.contains("crs:Contrast2012=\"-2\""), "unknown WB base → other sliders still apply")

        // An untouched edit must ALSO switch to Custom — that identity render is the probe.
        let probe = XMPPresetBuilder.sidecarXMP(presetURL: asShotFile, evDelta: 0, edit: ImageEdit())
        check(probe.contains("crs:WhiteBalance=\"Custom\""), "identity render probes WB via Custom")
        check(!probe.contains("crs:Temperature"), "identity render writes no Temperature (image must not change)")
        try? fm.removeItem(at: asShotFile)

        // 14b-3) preset base + delta must stay inside Camera Raw's range. ACR DISCARDS an
        //        out-of-range value and resets that control to 0 — measured: three different
        //        Highlights deltas on a -87 preset all landed as "Highlights 0", brightening
        //        the image instead of darkening it.
        let steepPreset = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
        <rdf:Description rdf:about="" xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
          crs:Highlights2012="-87" crs:Blacks2012="+90">
        </rdf:Description></rdf:RDF></x:xmpmeta>
        """
        let steepFile = root.appendingPathComponent("selftest_steep.xmp")
        try? steepPreset.data(using: .utf8)?.write(to: steepFile)
        var over = ImageEdit(); over.highlights = -80; over.blacks = 40
        let overXMP = XMPPresetBuilder.sidecarXMP(presetURL: steepFile, evDelta: 0, edit: over)
        check(overXMP.contains("crs:Highlights2012=\"-100\""), "under-range (-167) clamped to -100, not discarded")
        check(overXMP.contains("crs:Blacks2012=\"100\""), "over-range (+130) clamped to +100, not discarded")
        var wbOver = ImageEdit(); wbOver.tint = -200
        let wbOverXMP = XMPPresetBuilder.sidecarXMP(presetURL: steepFile, evDelta: 0, edit: wbOver,
                                                    asShotWB: (temp: 6000, tint: 0))
        check(wbOverXMP.contains("crs:Tint=\"-150\""), "Tint clamped to its own -150 limit")
        try? fm.removeItem(at: steepFile)

        // 14e) The bridge plug-in ships with the app and must be replaced whenever it differs —
        //      a stale one silently stops reporting the white balance, which kills the WB
        //      sliders without a single error message.
        let pluginA = root.appendingPathComponent("plugA", isDirectory: true)
        let pluginB = root.appendingPathComponent("plugB", isDirectory: true)
        try? fm.createDirectory(at: pluginA, withIntermediateDirectories: true)
        try? fm.createDirectory(at: pluginB, withIntermediateDirectories: true)
        func writeLua(_ dir: URL, _ name: String, _ body: String) {
            try? body.data(using: .utf8)?.write(to: dir.appendingPathComponent(name))
        }
        writeLua(pluginA, "Init.lua", "-- v2"); writeLua(pluginA, "Info.lua", "return {}")
        writeLua(pluginB, "Init.lua", "-- v2"); writeLua(pluginB, "Info.lua", "return {}")
        check(BridgeInstaller.scriptsMatch(pluginA, pluginB), "identical plug-ins → no reinstall")
        writeLua(pluginB, "Init.lua", "-- v1")
        check(!BridgeInstaller.scriptsMatch(pluginA, pluginB), "changed script → reinstall")
        try? fm.removeItem(at: pluginB.appendingPathComponent("Init.lua"))
        check(!BridgeInstaller.scriptsMatch(pluginA, pluginB), "missing script → reinstall")
        check(!BridgeInstaller.scriptsMatch(pluginA, root.appendingPathComponent("nope")),
              "no plug-in installed at all → install")
        try? fm.removeItem(at: pluginA); try? fm.removeItem(at: pluginB)

        // 14c) Color mixer (HSL): only non-zero bands are written; identity mixer stays default.
        var hslEdit = ImageEdit(); hslEdit.hsl["SaturationAdjustmentOrange"] = -30; hslEdit.hsl["HueAdjustmentBlue"] = 0
        let hslXMP = XMPPresetBuilder.sidecarXMP(presetURL: nil, evDelta: 0, edit: hslEdit)
        check(hslXMP.contains("crs:SaturationAdjustmentOrange=\"-30\""), "HSL Saturation/Orange written")
        check(!hslXMP.contains("HueAdjustmentBlue"), "HSL zero band NOT written")
        check(!hslEdit.isIdentity && ImageEdit.hslKeys.count == 24, "HSL breaks identity; 24 HSL keys")

        // 14d) DevelopEngine live approximation moves each control in the CORRECT direction.
        let ctx = CIContext()
        func patch(_ r: Double, _ g: Double, _ b: Double) -> CIImage {
            CIImage(color: CIColor(red: r, green: g, blue: b)).cropped(to: CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        func px(_ img: CIImage) -> (Double, Double, Double) {
            var bmp = [UInt8](repeating: 0, count: 4)
            ctx.render(img, toBitmap: &bmp, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
            return (Double(bmp[0]), Double(bmp[1]), Double(bmp[2]))
        }
        func lum(_ e: ImageEdit, _ p: CIImage) -> Double { let c = px(DevelopEngine.apply(e, to: p)); return c.0 * 0.3 + c.1 * 0.59 + c.2 * 0.11 }
        var eSh = ImageEdit(); eSh.shadows = 100
        check(lum(eSh, patch(0.25, 0.25, 0.25)) > 64, "Shadows+ brightens shadows")
        var eHiN = ImageEdit(); eHiN.highlights = -100
        check(lum(eHiN, patch(0.75, 0.75, 0.75)) < 191, "Highlights− darkens highlights")
        var eWh = ImageEdit(); eWh.whites = 100
        check(lum(eWh, patch(0.75, 0.75, 0.75)) > 191, "Whites+ brightens (no longer a no-op)")
        // WB: +temp must WARM (red up, blue down); +tint must go MAGENTA (green down).
        var eWarm = ImageEdit(); eWarm.temp = 2000
        let warm = px(DevelopEngine.apply(eWarm, to: patch(0.5, 0.5, 0.5)))
        check(warm.0 > warm.2, "Temp+ warms (red > blue), matches gradient")
        var eMag = ImageEdit(); eMag.tint = 100
        let mag = px(DevelopEngine.apply(eMag, to: patch(0.5, 0.5, 0.5)))
        check(mag.0 > mag.1 && mag.2 > mag.1, "Tint+ → magenta (green lowest), matches gradient")
        // HSL: desaturating the red band pulls a red patch toward neutral.
        var eDesat = ImageEdit(); eDesat.hsl["SaturationAdjustmentRed"] = -100
        let red0 = px(patch(0.8, 0.1, 0.1)), redD = px(DevelopEngine.apply(eDesat, to: patch(0.8, 0.1, 0.1)))
        check((redD.0 - redD.1) < (red0.0 - red0.1), "HSL Saturation− desaturates the red band")

        // 15) Update version comparison handles multi-digit + differing lengths.
        check(UpdateService.isNewer("1.3", than: "1.2"), "1.3 > 1.2")
        check(UpdateService.isNewer("1.10", than: "1.9"), "1.10 > 1.9 (numeric, not lexical)")
        check(UpdateService.isNewer("2", than: "1.9"), "2 > 1.9")
        check(!UpdateService.isNewer("1.2", than: "1.2"), "1.2 == 1.2 → not newer")
        check(!UpdateService.isNewer("1.1", than: "1.2"), "1.1 < 1.2 → not newer")

        // 16) Non-destructive edits persist per photo and survive a reload; an
        //     identity edit counts as "default" so untouched photos aren't stored.
        var editState = ImageEdit(); editState.contrast = 30; editState.temp = -20
        check(!SessionStore.PhotoState(mark: 0, edit: editState).isDefault, "edited-but-unmarked photo is not default")
        check(SessionStore.PhotoState(mark: 0, edit: ImageEdit()).isDefault, "identity edit → default (not stored)")
        let editKey = "edit-roundtrip"
        SessionStore.save(identityID: testID, states: [
            key: .init(mark: 3),
            editKey: .init(mark: 0, edit: editState)
        ], scope: [key, editKey])
        let reloaded = SessionStore.load(identityID: testID)
        check(reloaded[editKey]?.edit == editState, "ImageEdit round-trips through the session store")
        check(reloaded[key]?.edit == nil, "mark-only photo reloads without an edit")

        // 15a) Placing an export must never destroy the user's existing file before the new
        //      one is safely there. The old code did `removeItem` then `moveItem` — a failed
        //      write (disk full, share gone) left the photo deleted and nothing in its place.
        let placeDir = root.appendingPathComponent("place", isDirectory: true)
        try? fm.createDirectory(at: placeDir, withIntermediateDirectories: true)
        let placeTarget = placeDir.appendingPathComponent("photo.jpg")
        try? Data("ALT".utf8).write(to: placeTarget)
        let fresh = placeDir.appendingPathComponent("fresh.jpg")
        try? Data("NEU".utf8).write(to: fresh)
        try? LightroomExportService.place(fresh, at: placeTarget)
        check((try? String(contentsOf: placeTarget, encoding: .utf8)) == "NEU", "place() replaces an existing file")
        check(!fm.fileExists(atPath: fresh.path), "place() consumes the produced file")

        // The regression itself: the source is gone (render failed) → the original must survive.
        let missing = placeDir.appendingPathComponent("does-not-exist.jpg")
        let threw = (try? LightroomExportService.place(missing, at: placeTarget)) == nil
        check(threw, "place() reports failure when there is nothing to place")
        check((try? String(contentsOf: placeTarget, encoding: .utf8)) == "NEU", "failed place() leaves the user's file intact")
        check((try? fm.contentsOfDirectory(atPath: placeDir.path))?
                .contains(where: { $0.hasPrefix(".rawselect-") }) == false, "place() leaves no staging files behind")

        // 15b) A damaged file must never be silently overwritten — the marks in it may still
        //      be rescuable. It gets moved aside, and work continues on a fresh one.
        let brokenID = "selftest-broken-" + UUID().uuidString
        SessionStore.save(identityID: brokenID, states: ["x": .init(mark: 1)], scope: ["x"])
        check(SessionStore.read(identityID: brokenID) != .none, "precondition: file exists")
        // Corrupt it the way a half-finished write or a bad sector would.
        if case .states = SessionStore.read(identityID: brokenID) {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("RAW Select/Sessions", isDirectory: true)
            if let f = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
                .first(where: { $0.lastPathComponent.hasSuffix(".json") &&
                                (try? String(contentsOf: $0, encoding: .utf8))?.contains(brokenID) == true }) {
                try? Data("{ kaputt".utf8).write(to: f)
            }
        }
        check(SessionStore.read(identityID: brokenID) == .unreadable, "damaged file is reported unreadable, not empty")
        let res = SessionStore.save(identityID: brokenID, states: ["y": .init(mark: 2)], scope: ["y"])
        if case .quarantined(let name) = res {
            check(true, "damaged file is quarantined, not clobbered")
            // Clean up after ourselves — leaving a file per run is the very habit being fixed.
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("RAW Select/Sessions", isDirectory: true)
            try? fm.removeItem(at: dir.appendingPathComponent(name))
        } else {
            check(false, "damaged file is quarantined, not clobbered (got \(res))")
        }
        check(SessionStore.load(identityID: brokenID)["y"]?.mark == 2, "work continues on a fresh file")
        SessionStore.delete(identityID: brokenID)

        // 17) Embedded-JPEG byte parser (zoom fallback for RAWs macOS can't develop natively).
        //     This byte-scanning code has no GUI test path; a wrong SOI/EOI or SOF read means a
        //     wrong zoom resolution or a crash on a new camera format.
        func jpegStream(w: Int, h: Int) -> [UInt8] {
            // SOI (FF D8) + SOF0 (FF C0) with a 17-byte frame header, then EOI (FF D9).
            // largestJPEGRange looks for the 3-byte signature FF D8 FF, so SOF's FF follows SOI.
            var b: [UInt8] = [0xFF, 0xD8,
                              0xFF, 0xC0,                 // SOF0
                              0x00, 0x11,                 // segment length = 17
                              0x08,                       // sample precision
                              UInt8((h >> 8) & 0xFF), UInt8(h & 0xFF),
                              UInt8((w >> 8) & 0xFF), UInt8(w & 0xFF),
                              0x03]                       // component count
            b += Array(repeating: 0x00, count: 12)        // rest of the SOF body + padding
            b += [0xFF, 0xD9]                             // EOI
            return b
        }
        let valid = ThumbnailLoader.embeddedJPEGDimensions(in: jpegStream(w: 1600, h: 1000))
        check(valid?.0 == 1600 && valid?.1 == 1000, "parser reads embedded JPEG size (got \(valid.map { "\($0.0)×\($0.1)" } ?? "nil"))")
        check(ThumbnailLoader.embeddedJPEGDimensions(in: jpegStream(w: 256, h: 256)) == nil,
              "tiny stream below the 800px floor is ignored (no thumbnail chosen as preview)")
        check(ThumbnailLoader.embeddedJPEGDimensions(in: [UInt8]("not a jpeg at all".utf8)) == nil,
              "garbage with no SOI marker returns nil, not a crash")
        let two = ThumbnailLoader.embeddedJPEGDimensions(in: jpegStream(w: 900, h: 900) + jpegStream(w: 2000, h: 1500))
        check(two?.0 == 2000 && two?.1 == 1500, "of two embedded JPEGs the larger one wins (got \(two.map { "\($0.0)×\($0.1)" } ?? "nil"))")

        // 18) Reject → Trash: files leave the source (recoverable), whole groups are reported,
        //     and a missing file never aborts the batch. Cleans up the trashed items afterwards
        //     so the run leaves nothing behind in the user's Trash.
        let trashDir = root.appendingPathComponent("trashsrc", isDirectory: true)
        try? fm.createDirectory(at: trashDir, withIntermediateDirectories: true)
        let tImg = trashDir.appendingPathComponent("REJECT.JPG"); writePNG(to: tImg, size: 24)
        let tXmp = trashDir.appendingPathComponent("REJECT.xmp"); try? Data("<xmp/>".utf8).write(to: tXmp)
        let tGroup = PhotoGroup(id: "t", directory: trashDir, baseName: "REJECT",
                                files: [tImg], sidecars: [tXmp], previewURL: tImg, displayName: "REJECT")
        let tOut = FileOperationService.trash(groups: [tGroup])
        check(tOut.files == 2 && tOut.photos == 1, "trash moves image + sidecar (got \(tOut.files) files)")
        check(tOut.trashedGroupIDs.contains("t"), "fully-trashed group is reported for removal")
        check(!fm.fileExists(atPath: tImg.path) && !fm.fileExists(atPath: tXmp.path), "source files are gone after trash")
        check(tOut.failures.isEmpty, "clean trash reports no failures")
        for u in tOut.trashedURLs { try? fm.removeItem(at: u) }   // don't litter the real Trash
        // A group whose only file is already gone must be a no-op failure, not a crash.
        let goneGroup = PhotoGroup(id: "g", directory: trashDir, baseName: "GONE",
                                   files: [trashDir.appendingPathComponent("GONE.JPG")],
                                   previewURL: trashDir.appendingPathComponent("GONE.JPG"), displayName: "GONE")
        let gOut = FileOperationService.trash(groups: [goneGroup])
        check(gOut.files == 0 && gOut.trashedGroupIDs.isEmpty, "trashing an already-missing file is a safe no-op")

        // 19) Thumbnail loader coalescing: a repeat request for the same key is served from the
        //     cache instead of decoding again (the decodeCount counter also backs the in-flight
        //     de-dup that shares one decode between a prefetch and a visible request).
        let loaderBase = ThumbnailLoader.shared.decodeCount
        let loaderSem = DispatchSemaphore(value: 0)
        Task {
            _ = await ThumbnailLoader.shared.thumbnail(for: realJPG, maxPixel: 997)
            _ = await ThumbnailLoader.shared.thumbnail(for: realJPG, maxPixel: 997)  // now from cache
            loaderSem.signal()
        }
        loaderSem.wait()
        check(ThumbnailLoader.shared.decodeCount - loaderBase == 1, "repeat thumbnail request decodes once, then hits cache")

        SessionStore.delete(identityID: testID)
        try? fm.removeItem(at: root)
        print(failures == 0 ? "\nALL PASSED ✅" : "\n\(failures) FAILED ❌")
        if failures > 0 { exit(1) }
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
