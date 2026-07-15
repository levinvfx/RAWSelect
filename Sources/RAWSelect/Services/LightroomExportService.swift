import Foundation
import AppKit
import CoreGraphics

/// Drives Adobe Lightroom Classic as a LOCAL rendering engine to export JPEGs from
/// RAW files with a Camera-Raw/Lightroom preset (INCLUDING local masks — AI subject
/// & gradients) plus a manual/Smart-Exposure delta.
///
/// Lightroom cannot be driven headlessly. Instead a background
/// watcher plugin (`RAWSelectBridge.lrplugin`) runs inside Lightroom and processes
/// job files this service drops into a spool folder. This service:
///   1. auto-launches Lightroom (so the watcher is running),
///   2. copies each RAW + writes a temp sidecar `.xmp` (preset + absolute exposure),
///   3. writes one `<id>.job` per image into the spool and waits for `<id>.done`,
///   4. moves the rendered JPEG into the target folder under RAW Select's own naming.
///
/// Safety: works entirely inside a temporary folder + the app-support spool. Original
/// RAWs and the user's preset are never modified. No network is used anywhere.
struct LightroomExportService {

    struct Config {
        var presetURL: URL?
        var jpegQuality01: Double        // Lightroom scale 0…1
        var colorSpace: String           // "sRGB" | "AdobeRGB" | "ProPhotoRGB"
        var longEdge: Int                // 0 = keep original size
        var targetRoot: URL
        var folderStructure: ExportFolderStructure
        var sourceRoot: URL?
        var conflict: ConflictMode
        var deleteTemp: Bool
        var lightroomPath: String
        var autoConfirmDialogs: Bool
        var denoise: Double = 0          // noise reduction strength 0…100 (0 = off)
        var denoiseUseEnhance: Bool = false   // true = real Adobe AI Enhance-Denoise (slow)
    }

    struct Outcome {
        var success: Int
        var failures: [ExportFailure]
        var targetRoot: URL
        var tempWarning: String?
    }

    static let bundleID = "com.adobe.LightroomClassicCC7"

    /// Locates Lightroom Classic: manual path → bundle id → /Applications scan.
    static func lightroomURL(preferredPath: String) -> URL? {
        if !preferredPath.isEmpty {
            let u = URL(fileURLWithPath: preferredPath)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) { return u }
        let apps = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: "/Applications"),
                                                                 includingPropertiesForKeys: nil)) ?? []
        return apps.first { $0.lastPathComponent.hasPrefix("Adobe Lightroom Classic") }
    }

    static func isAvailable(preferredPath: String) -> Bool { lightroomURL(preferredPath: preferredPath) != nil }

    /// Spool folder shared with the Lightroom watcher plugin.
    static func spoolBase() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("RAW Select/LightroomBridge", isDirectory: true)
    }

    // MARK: Export

    static func export(items: [ExportItem],
                       config: Config,
                       progress: @escaping (Int, Int, String, ExportStage) -> Void,
                       isCancelled: @escaping () -> Bool) async -> Outcome {

        let fm = FileManager.default
        progress(0, items.count, "", .preparing)

        guard let lrURL = lightroomURL(preferredPath: config.lightroomPath) else {
            return Outcome(success: 0, failures: [ExportFailure(fileName: "—", message: "Lightroom Classic wurde nicht gefunden.")],
                           targetRoot: config.targetRoot, tempWarning: nil)
        }

        // Spool folders (must match the watcher plugin).
        let base = spoolBase()
        let jobsDir = base.appendingPathComponent("jobs", isDirectory: true)
        let doneDir = base.appendingPathComponent("done", isDirectory: true)
        let tempDir = fm.temporaryDirectory.appendingPathComponent("RAWSelectLR-\(UUID().uuidString)", isDirectory: true)

        do {
            try fm.createDirectory(at: jobsDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: doneDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try? fm.createDirectory(at: config.targetRoot, withIntermediateDirectories: true)

            // Make sure Lightroom (and thus the watcher) is running.
            await ensureLightroomRunning(url: lrURL)

            // Optionally auto-dismiss Lightroom's "update AI model" dialog during export.
            let confirmer = config.autoConfirmDialogs ? startDialogConfirmer() : nil
            defer { confirmer?.terminate() }

            // Build manifest: per-item input copy + sidecar + private staging dir + desired output.
            struct Entry { let item: ExportItem; let id: String; let raw: URL; let stage: URL; let desired: URL; let name: String }
            var manifest: [Entry] = []
            var usedOut = Set<String>()
            for (idx, item) in items.enumerated() {
                let base0 = item.rawURL.deletingPathExtension().lastPathComponent
                let ext = item.rawURL.pathExtension
                let inDir = tempDir.appendingPathComponent("in/\(idx)", isDirectory: true)
                let stageDir = tempDir.appendingPathComponent("stage/\(idx)", isDirectory: true)
                try fm.createDirectory(at: inDir, withIntermediateDirectories: true)
                try fm.createDirectory(at: stageDir, withIntermediateDirectories: true)

                let tempRaw = inDir.appendingPathComponent("\(base0).\(ext)")
                try fm.copyItem(at: item.rawURL, to: tempRaw)
                let sidecar = inDir.appendingPathComponent("\(base0).xmp")
                // The absolute WB needs the same base the slider showed: the preset's own
                // Temperature, or the RAW's as-shot value harvested by the preview render.
                let wb = await LightroomPreviewService.shared.asShotWB(rawURL: item.rawURL)
                let xmp = XMPPresetBuilder.sidecarXMP(presetURL: config.presetURL, evDelta: item.evDelta,
                                                      edit: item.edit, denoise: config.denoise,
                                                      asShotWB: wb.map { ($0.temp, $0.tint) })
                try xmp.data(using: .utf8)?.write(to: sidecar)

                let dir = outputDir(for: item.group, config: config, item: item)
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
                guard let desired = resolveOutput(base: base0, in: dir, conflict: config.conflict, used: &usedOut) else { continue }
                usedOut.insert(desired.path)

                let id = "RS_\(UUID().uuidString)"
                manifest.append(Entry(item: item, id: id, raw: tempRaw, stage: stageDir, desired: desired, name: item.rawURL.lastPathComponent))
            }

            if manifest.isEmpty {
                cleanup(tempDir, config: config)
                return Outcome(success: 0, failures: [], targetRoot: config.targetRoot, tempWarning: nil)
            }

            // Submit + wait one job at a time (clean progress, no catalog contention).
            var success = 0
            var failures: [ExportFailure] = []
            for (i, e) in manifest.enumerated() {
                if isCancelled() { break }
                progress(i, manifest.count, e.name, .rendering)

                // Crop/rotate/straighten are applied locally AFTER Lightroom renders the
                // full frame (masks stay correct + full resolution). Those images are
                // exported from LR at original size / max quality, then transformed here.
                let needsEdit = e.item.edit.crop != nil || e.item.edit.totalAngle != 0
                let jobQuality = needsEdit ? 1.0 : config.jpegQuality01
                let jobEdge = needsEdit ? 0 : config.longEdge
                writeJob(id: e.id, raw: e.raw, out: e.stage, quality: jobQuality, maxEdge: jobEdge,
                         colorSpace: config.colorSpace, denoise: config.denoise,
                         enhance: config.denoiseUseEnhance, jobsDir: jobsDir)
                // AI Enhance-Denoise renders a whole new DNG per image → allow much longer.
                let timeout: TimeInterval = config.denoiseUseEnhance ? 600 : 180
                let result = await waitForDone(id: e.id, doneDir: doneDir, timeout: timeout, isCancelled: isCancelled)

                switch result {
                case .some(let r) where r.status == "ok":
                    if let produced = firstJPEG(in: e.stage, hint: r.path) {
                        if needsEdit {
                            if applyEdit(from: produced, edit: e.item.edit, longEdge: config.longEdge,
                                         quality: config.jpegQuality01, to: e.desired) {
                                success += 1
                            } else {
                                failures.append(ExportFailure(fileName: e.name, message: "Zuschnitt/Belichtung konnte nicht angewendet werden."))
                            }
                        } else {
                            do {
                                try? fm.removeItem(at: e.desired)
                                try fm.moveItem(at: produced, to: e.desired)
                                success += 1
                            } catch {
                                failures.append(ExportFailure(fileName: e.name, message: "Konnte JPEG nicht ablegen: \(error.localizedDescription)"))
                            }
                        }
                    } else {
                        failures.append(ExportFailure(fileName: e.name, message: "Lightroom meldete Erfolg, aber kein JPEG gefunden."))
                    }
                case .some:
                    failures.append(ExportFailure(fileName: e.name, message: "Lightroom-Export fehlgeschlagen."))
                case nil:
                    if isCancelled() {
                        failures.append(ExportFailure(fileName: e.name, message: "Abgebrochen."))
                    } else {
                        failures.append(ExportFailure(fileName: e.name, message: "Zeitüberschreitung — Lightroom hat nicht geantwortet. Läuft Lightroom Classic mit aktivem „RAW Select Bridge“-Plugin?"))
                    }
                }
                progress(i + 1, manifest.count, e.name, .rendering)
            }

            let warning = cleanup(tempDir, config: config)
            return Outcome(success: success, failures: failures, targetRoot: config.targetRoot, tempWarning: warning)
        } catch {
            _ = cleanup(tempDir, config: config)
            return Outcome(success: 0, failures: [ExportFailure(fileName: "—", message: error.localizedDescription)],
                           targetRoot: config.targetRoot, tempWarning: nil)
        }
    }

    // MARK: Preview render (single small JPEG for the export crop step)

    /// Renders ONE small preset-applied JPEG for a live preview (no crop, no denoise)
    /// and returns a stable temp file the caller owns (move/delete it). Reuses the
    /// same bridge as the export. Returns nil if Lightroom/bridge is unavailable or
    /// the render fails. Exposure is left at the preset's neutral (0) — the crop
    /// step overlays manual exposure approximately on top.
    /// A rendered preview plus the white balance Camera Raw resolved for the photo.
    struct PreviewRender { let url: URL; let asShotTemp: Double?; let asShotTint: Double? }

    static func renderPreview(rawURL: URL, presetURL: URL?, edit: ImageEdit = ImageEdit(),
                              maxEdge: Int, lightroomPath: String,
                              isCancelled: @escaping () -> Bool = { false }) async -> PreviewRender? {
        guard let lrURL = lightroomURL(preferredPath: lightroomPath) else { return nil }
        let fm = FileManager.default
        let base = spoolBase()
        let jobsDir = base.appendingPathComponent("jobs", isDirectory: true)
        let doneDir = base.appendingPathComponent("done", isDirectory: true)
        let tempDir = fm.temporaryDirectory.appendingPathComponent("RAWSelectLRPrev-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: jobsDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: doneDir, withIntermediateDirectories: true)
            let inDir = tempDir.appendingPathComponent("in", isDirectory: true)
            let stageDir = tempDir.appendingPathComponent("stage", isDirectory: true)
            try fm.createDirectory(at: inDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: stageDir, withIntermediateDirectories: true)

            await ensureLightroomRunning(url: lrURL)

            let base0 = rawURL.deletingPathExtension().lastPathComponent
            let ext = rawURL.pathExtension
            let tempRaw = inDir.appendingPathComponent("\(base0).\(ext)")
            try fm.copyItem(at: rawURL, to: tempRaw)
            let sidecar = inDir.appendingPathComponent("\(base0).xmp")
            // Exactly the export sidecar: preset + absolute exposure + Basic-panel
            // develop values → the render matches the export 1:1 (crop/rotate stay local).
            // Identity renders (temp/tint 0) are what harvest the as-shot WB in the first
            // place, so a missing value here is fine — nothing WB-related gets written.
            let wb = await LightroomPreviewService.shared.asShotWB(rawURL: rawURL)
            let xmp = XMPPresetBuilder.sidecarXMP(presetURL: presetURL, evDelta: edit.exposure,
                                                  edit: edit, stripMasks: true,
                                                  asShotWB: wb.map { ($0.temp, $0.tint) })
            try xmp.data(using: .utf8)?.write(to: sidecar)

            let id = "RSPREV_\(UUID().uuidString)"
            writeJob(id: id, raw: tempRaw, out: stageDir, quality: 0.85, maxEdge: maxEdge,
                     colorSpace: "sRGB", denoise: 0, enhance: false, jobsDir: jobsDir)
            let result = await waitForDone(id: id, doneDir: doneDir, timeout: 120, isCancelled: isCancelled)

            guard case let .some(done) = result, done.status == "ok",
                  let produced = firstJPEG(in: stageDir, hint: done.path) else {
                try? fm.removeItem(at: tempDir); return nil
            }
            let outFile = fm.temporaryDirectory.appendingPathComponent("RSPrev-\(id).jpg")
            try? fm.removeItem(at: outFile)
            try fm.moveItem(at: produced, to: outFile)
            try? fm.removeItem(at: tempDir)
            return PreviewRender(url: outFile, asShotTemp: done.temp, asShotTint: done.tint)
        } catch {
            try? fm.removeItem(at: tempDir)
            return nil
        }
    }

    // MARK: Lightroom lifecycle

    private static func ensureLightroomRunning(url: URL) async {
        let isRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
        if isRunning { return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = false
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: cfg)
        // Give Lightroom time to launch and load the watcher plugin before jobs land.
        try? await Task.sleep(nanoseconds: 8_000_000_000)
    }

    // MARK: Spool I/O

    private static func writeJob(id: String, raw: URL, out: URL, quality: Double, maxEdge: Int,
                                 colorSpace: String, denoise: Double, enhance: Bool, jobsDir: URL) {
        let (maxW, maxH) = maxEdge > 0 ? (maxEdge, maxEdge) : (0, 0)
        // `enhance=1` tells the bridge plugin to run Adobe's AI Enhance-Denoise
        // (creates a denoised DNG) before exporting; `denoise` is its 0…100 amount.
        let body = """
        id=\(id)
        raw=\(raw.path)
        out=\(out.path)
        maxwidth=\(maxW)
        maxheight=\(maxH)
        quality=\(String(format: "%.2f", quality))
        colorspace=\(colorSpace)
        denoise=\(Int(denoise.rounded()))
        enhance=\(enhance ? 1 : 0)
        """
        let tmp = jobsDir.appendingPathComponent("\(id).tmp")
        let final = jobsDir.appendingPathComponent("\(id).job")
        try? body.data(using: .utf8)?.write(to: tmp)
        try? FileManager.default.moveItem(at: tmp, to: final)   // atomic → watcher never sees a half file
    }

    /// Parsed `<id>.done` reply. `temp`/`tint` carry the white balance Camera Raw
    /// resolved for the photo (as-shot unless a preset overrides it), when reported.
    struct DoneResult { let status: String; let path: String; let temp: Double?; let tint: Double? }

    /// Polls for `<id>.done`; returns the parsed reply or nil on timeout/cancel.
    private static func waitForDone(id: String, doneDir: URL, timeout: TimeInterval = 180, isCancelled: @escaping () -> Bool) async -> DoneResult? {
        let marker = doneDir.appendingPathComponent("\(id).done")
        let deadline = Date().addingTimeInterval(timeout)   // generous; cold LR / Enhance included
        while Date() < deadline {
            if isCancelled() { return nil }
            if let text = try? String(contentsOf: marker, encoding: .utf8) {
                var status = "", path = "", temp: Double?, tint: Double?
                for line in text.split(whereSeparator: \.isNewline) {
                    if line.hasPrefix("status=") { status = String(line.dropFirst(7)) }
                    else if line.hasPrefix("path=") { path = String(line.dropFirst(5)) }
                    else if line.hasPrefix("temperature=") { temp = Double(line.dropFirst(12)) }
                    else if line.hasPrefix("tint=") { tint = Double(line.dropFirst(5)) }
                }
                try? FileManager.default.removeItem(at: marker)
                return DoneResult(status: status, path: path, temp: temp, tint: tint)
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        return nil
    }

    private static func firstJPEG(in dir: URL, hint: String) -> URL? {
        if !hint.isEmpty, FileManager.default.fileExists(atPath: hint) { return URL(fileURLWithPath: hint) }
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.first { ["jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
    }

    // MARK: Local edit (crop / rotate / straighten / resize)

    /// Applies the non-destructive edit to Lightroom's full-frame render, then encodes
    /// the final JPEG. Rotation/straighten expand to a bounding box (like the crop
    /// editor's preview, expands to a bounding box); crop is normalised on that
    /// rotated frame. Exposure is NOT applied here — Lightroom already baked it in via
    /// the sidecar (crs:Exposure2012), so there is no double correction.
    private static func applyEdit(from jpegURL: URL, edit: ImageEdit, longEdge: Int, quality: Double, to out: URL) -> Bool {
        guard let img = NSImage(contentsOf: jpegURL) else { return false }
        let rotated = img.rotatedClockwise(byDegrees: edit.totalAngle)
        guard var cg = rotated.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }

        if let c = edit.crop {
            let W = CGFloat(cg.width), H = CGFloat(cg.height)
            let rect = CGRect(x: (c.minX * W).rounded(), y: (c.minY * H).rounded(),
                              width: (c.width * W).rounded(), height: (c.height * H).rounded())
                .intersection(CGRect(x: 0, y: 0, width: CGFloat(cg.width), height: CGFloat(cg.height)))
            if rect.width >= 1, rect.height >= 1, let cropped = cg.cropping(to: rect) { cg = cropped }
        }

        var outW = cg.width, outH = cg.height
        if longEdge > 0 {
            let scale = Double(longEdge) / Double(max(outW, outH))
            if scale < 1 { outW = max(1, Int(Double(outW) * scale)); outH = max(1, Int(Double(outH) * scale)) }
        }

        let space = cg.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: outW, height: outH, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: outW, height: outH))
        guard let outCG = ctx.makeImage() else { return false }

        let rep = NSBitmapImageRep(cgImage: outCG)
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: quality]) else { return false }
        do { try? FileManager.default.removeItem(at: out); try data.write(to: out); return true }
        catch { return false }
    }

    // MARK: Auto-confirm Lightroom's AI-model dialog

    /// Starts a background osascript that clicks Lightroom's "download/update AI model"
    /// dialog (by known button labels only — never destructive buttons) for the export
    /// window. Requires Accessibility permission; fails silently otherwise.
    private static func startDialogConfirmer() -> Process? {
        let script = """
        set okLabels to {"Herunterladen", "Download", "Aktualisieren", "Update", "Fortfahren", "Continue", "OK", "Laden", "Jetzt herunterladen", "Verbessern", "Enhance", "Anwenden", "Apply", "Exportieren", "Export", "Weiter"}
        set proceedLabels to {"Exportieren", "Export", "Fortfahren", "Continue", "Weiter"}
        repeat 900 times
          try
            tell application "System Events"
              if exists (process "Adobe Lightroom Classic") then
                tell process "Adobe Lightroom Classic"
                  repeat with w in windows
                    -- Weg 2: AI-update dialog matched by title → click its proceed button
                    try
                      set wn to (name of w) as string
                      if wn contains "KI-Update" or wn contains "empfohlen" or wn contains "recommended" or wn contains "AI-Update" then
                        repeat with b in buttons of w
                          if (name of b) is in proceedLabels then
                            click b
                            exit repeat
                          end if
                        end repeat
                      end if
                    end try
                    -- Weg 1: known button labels (windows)
                    try
                      repeat with b in buttons of w
                        if (name of b) is in okLabels then
                          click b
                          exit repeat
                        end if
                      end repeat
                    end try
                    -- sheets: title-scoped proceed, then known labels
                    try
                      repeat with sh in sheets of w
                        try
                          set sn to (name of sh) as string
                          if sn contains "KI-Update" or sn contains "empfohlen" or sn contains "recommended" or sn contains "AI-Update" then
                            repeat with b in buttons of sh
                              if (name of b) is in proceedLabels then click b
                            end repeat
                          end if
                        end try
                        repeat with b in buttons of sh
                          if (name of b) is in okLabels then click b
                        end repeat
                      end repeat
                    end try
                  end repeat
                end tell
              end if
            end tell
          end try
          delay 1
        end repeat
        """
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("rs-lr-confirm-\(UUID().uuidString).applescript")
        guard (try? script.data(using: .utf8)?.write(to: tmp)) != nil else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = [tmp.path]
        p.standardError = Pipe()
        p.standardOutput = Pipe()
        do { try p.run(); return p } catch { return nil }
    }

    // MARK: Output layout

    /// Always the chosen target folder — RAW Select never creates subfolders on export.
    private static func outputDir(for group: PhotoGroup, config: Config, item: ExportItem) -> URL {
        config.targetRoot
    }

    private static func resolveOutput(base: String, in dir: URL, conflict: ConflictMode, used: inout Set<String>) -> URL? {
        let first = dir.appendingPathComponent("\(base).jpg")
        let onDisk = FileManager.default.fileExists(atPath: first.path)
        let inBatch = used.contains(first.path)
        if !onDisk && !inBatch { return first }
        switch conflict {
        case .skip: return nil
        case .overwrite:
            // Overwrite a pre-existing file on disk, but NEVER clobber our own
            // just-written batch output (same basename twice in one export).
            if !inBatch { return first }
            fallthrough
        case .rename, .ask:
            var i = 1
            while true {
                let u = dir.appendingPathComponent("\(base)_\(i).jpg")
                if !FileManager.default.fileExists(atPath: u.path) && !used.contains(u.path) { return u }
                i += 1
            }
        }
    }

    @discardableResult
    private static func cleanup(_ tempDir: URL, config: Config) -> String? {
        guard config.deleteTemp else { return "Temporäre Dateien behalten: \(tempDir.path)" }
        do { try FileManager.default.removeItem(at: tempDir); return nil }
        catch { return "Temporäre Dateien konnten nicht gelöscht werden: \(tempDir.path)" }
    }
}
