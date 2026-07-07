import Foundation
import AppKit

/// Drives Adobe Photoshop as a LOCAL rendering engine to export JPEGs from RAW
/// files with an optional Camera-Raw preset and a Smart-Exposure delta.
///
/// Safety: works entirely inside a temporary folder. Original RAWs and the user's
/// preset/XMP files are never modified. No network is used anywhere.
struct PhotoshopExportService {

    struct Config {
        var presetURL: URL?
        var jpegQualityPS: Int          // Photoshop scale 0…12
        var colorProfile: String        // e.g. "sRGB IEC61966-2.1"
        var longEdge: Int               // 0 = keep original size
        var sharpenAmount: Double       // 0 = none
        var sharpenRadius: Double
        var targetRoot: URL
        var folderStructure: ExportFolderStructure
        var sourceRoot: URL?
        var conflict: ConflictMode
        var deleteTemp: Bool
        var closePhotoshop: Bool
        var saveLog: Bool
        var photoshopPath: String
    }

    struct Outcome {
        var success: Int
        var failures: [ExportFailure]
        var targetRoot: URL
        var logURL: URL?
        var tempWarning: String?
    }

    static let photoshopBundleID = "com.adobe.Photoshop"

    /// Locates Photoshop: manual path → bundle id → /Applications scan.
    static func photoshopURL(preferredPath: String) -> URL? {
        if !preferredPath.isEmpty {
            let u = URL(fileURLWithPath: preferredPath)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: photoshopBundleID) { return u }
        let apps = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: "/Applications"),
                                                                 includingPropertiesForKeys: nil)) ?? []
        return apps.first { $0.lastPathComponent.hasPrefix("Adobe Photoshop") }
    }

    static func isAvailable(preferredPath: String) -> Bool { photoshopURL(preferredPath: preferredPath) != nil }

    // MARK: Export

    static func export(items: [PhotoshopExportItem],
                       config: Config,
                       progress: @escaping (Int, Int, String, ExportStage) -> Void,
                       isCancelled: @escaping () -> Bool) async -> Outcome {

        let fm = FileManager.default
        progress(0, items.count, "", .preparing)

        guard photoshopURL(preferredPath: config.photoshopPath) != nil else {
            return Outcome(success: 0, failures: [ExportFailure(fileName: "—", message: "Photoshop wurde nicht gefunden.")],
                           targetRoot: config.targetRoot, logURL: nil, tempWarning: nil)
        }

        // Temp working folder.
        let tempDir = fm.temporaryDirectory.appendingPathComponent("RAWSelectPS-\(UUID().uuidString)", isDirectory: true)
        let logURL = tempDir.appendingPathComponent("export.log")
        do {
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try Data().write(to: logURL)
            try? fm.createDirectory(at: config.targetRoot, withIntermediateDirectories: true)

            // Build manifest: copy RAW + write sidecar + resolve unique output path.
            var manifest: [(raw: URL, out: URL, name: String)] = []
            var usedOut = Set<String>()
            for (idx, item) in items.enumerated() {
                let base = item.rawURL.deletingPathExtension().lastPathComponent
                let ext = item.rawURL.pathExtension
                let tempRaw = tempDir.appendingPathComponent("\(idx)_\(base).\(ext)")
                try fm.copyItem(at: item.rawURL, to: tempRaw)
                let sidecar = tempDir.appendingPathComponent("\(idx)_\(base).xmp")
                let xmp = XMPPresetBuilder.sidecarXMP(presetURL: config.presetURL, evDelta: item.evDelta)
                try xmp.data(using: .utf8)?.write(to: sidecar)

                let dir = outputDir(for: item.group, config: config, item: item)
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
                if let out = resolveOutput(base: base, in: dir, conflict: config.conflict, used: &usedOut) {
                    usedOut.insert(out.path)
                    manifest.append((tempRaw, out, item.rawURL.lastPathComponent))
                }
            }

            if manifest.isEmpty {
                return Outcome(success: 0, failures: [], targetRoot: config.targetRoot, logURL: nil, tempWarning: nil)
            }

            // Generate + run the Photoshop script.
            let jsxURL = tempDir.appendingPathComponent("job.jsx")
            try makeJSX(manifest: manifest, config: config, logURL: logURL).data(using: .utf8)?.write(to: jsxURL)
            let scptURL = tempDir.appendingPathComponent("run.applescript")
            try makeAppleScript(jsxURL: jsxURL).data(using: .utf8)?.write(to: scptURL)

            progress(0, manifest.count, manifest.first?.name ?? "", .rendering)
            let (exitCode, stderr) = await runAndTrack(scriptURL: scptURL, logURL: logURL, total: manifest.count,
                                                       progress: progress, isCancelled: isCancelled)

            // Parse results from the Photoshop log.
            let logText = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            let ran = logText.contains("PROG ")
            var success = 0
            var failures: [ExportFailure] = []
            for line in logText.split(separator: "\n") {
                if line.hasPrefix("OK ") { success += 1 }
                else if line.hasPrefix("ERR ") {
                    let comps = String(line.dropFirst(4)).components(separatedBy: " || ")
                    failures.append(ExportFailure(fileName: comps.first ?? "?", message: comps.count > 1 ? comps[1] : "Fehler"))
                }
            }
            if !ran {
                let lower = stderr.lowercased()
                let permission = stderr.contains("-1743") || lower.contains("not authorized")
                    || lower.contains("nicht berechtigt") || lower.contains("automation") || exitCode != 0
                let msg = permission
                    ? "RAW Select darf Photoshop (noch) nicht steuern.\n\nBitte in Systemeinstellungen → Datenschutz & Sicherheit → Automation den Eintrag „RAW Select“ → „Adobe Photoshop“ aktivieren und erneut exportieren."
                    : "Photoshop hat das Skript nicht ausgeführt. Läuft Photoshop und ist es aktiviert?"
                failures = [ExportFailure(fileName: "Photoshop-Automation", message: msg)]
            }

            // Cleanup.
            var tempWarning: String?
            var savedLog: URL? = nil
            if config.saveLog {
                let dest = config.targetRoot.appendingPathComponent("RAWSelect-Export-Log.txt")
                try? fm.copyItem(at: logURL, to: dest); savedLog = dest
            }
            if config.deleteTemp {
                do { try fm.removeItem(at: tempDir) }
                catch { tempWarning = "Temporäre Dateien konnten nicht gelöscht werden: \(tempDir.path)" }
            } else {
                tempWarning = "Temporäre Dateien behalten: \(tempDir.path)"
            }

            return Outcome(success: success, failures: failures, targetRoot: config.targetRoot,
                           logURL: savedLog, tempWarning: tempWarning)
        } catch {
            try? fm.removeItem(at: tempDir)
            return Outcome(success: 0, failures: [ExportFailure(fileName: "—", message: error.localizedDescription)],
                           targetRoot: config.targetRoot, logURL: nil, tempWarning: nil)
        }
    }

    // MARK: Helpers

    private static func outputDir(for group: PhotoGroup, config: Config, item: PhotoshopExportItem) -> URL {
        switch config.folderStructure {
        case .single:
            return config.targetRoot
        case .perMark:
            guard group.mark != 0 else { return config.targetRoot }
            let name = String(format: "%02d_", group.mark) + AppSettings.shared.markName(group.mark)
                .components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
            return config.targetRoot.appendingPathComponent(name, isDirectory: true)
        case .mirror:
            guard let root = config.sourceRoot else { return config.targetRoot }
            let rel = item.rawURL.deletingLastPathComponent().path.replacingOccurrences(of: root.path, with: "")
            return config.targetRoot.appendingPathComponent(rel.trimmingCharacters(in: CharacterSet(charactersIn: "/")), isDirectory: true)
        }
    }

    private static func resolveOutput(base: String, in dir: URL, conflict: ConflictMode, used: inout Set<String>) -> URL? {
        let first = dir.appendingPathComponent("\(base).jpg")
        let exists = FileManager.default.fileExists(atPath: first.path) || used.contains(first.path)
        if !exists { return first }
        switch conflict {
        case .skip: return nil
        case .overwrite: return first
        case .rename, .ask:
            var i = 1
            while true {
                let u = dir.appendingPathComponent("\(base)_\(i).jpg")
                if !FileManager.default.fileExists(atPath: u.path) && !used.contains(u.path) { return u }
                i += 1
            }
        }
    }

    private static func jsEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func makeJSX(manifest: [(raw: URL, out: URL, name: String)], config: Config, logURL: URL) -> String {
        let itemsJS = manifest.map {
            "{raw:\"\(jsEscape($0.raw.path))\",out:\"\(jsEscape($0.out.path))\",name:\"\(jsEscape($0.name))\"}"
        }.joined(separator: ",\n")

        return """
        #target photoshop
        var LOG = new File("\(jsEscape(logURL.path))");
        function log(s){ try{ LOG.open("a"); LOG.encoding="UTF-8"; LOG.writeln(s); LOG.close(); }catch(e){} }
        var items = [\n\(itemsJS)\n];
        var quality = \(config.jpegQualityPS);
        var profile = "\(jsEscape(config.colorProfile))";
        var longEdge = \(config.longEdge);
        var sharpen = \(Int(config.sharpenAmount));
        var sharpenRadius = \(config.sharpenRadius);
        var savedRulerUnits = app.preferences.rulerUnits;
        app.preferences.rulerUnits = Units.PIXELS;
        app.displayDialogs = DialogModes.NO;
        for (var i=0; i<items.length; i++){
          var it = items[i];
          log("PROG " + (i+1) + " " + items.length + " " + it.name);
          try {
            var desc = new ActionDescriptor();
            desc.putPath(charIDToTypeID("null"), new File(it.raw));
            executeAction(charIDToTypeID("Opn "), desc, DialogModes.NO);
            var doc = app.activeDocument;
            if (profile.length > 0){ try { doc.convertProfile(profile, Intent.RELATIVECOLORIMETRIC, true, true); } catch(e){} }
            if (longEdge > 0){
              var wpx = doc.width.as("px"); var hpx = doc.height.as("px");
              var scale = longEdge / Math.max(wpx, hpx);
              if (scale < 1){ doc.resizeImage(UnitValue(wpx*scale,"px"), UnitValue(hpx*scale,"px"), doc.resolution, ResampleMethod.BICUBICSHARPER); }
            }
            if (sharpen > 0){ try { doc.flatten(); doc.artLayers[0].applyUnSharpMask(sharpen, sharpenRadius, 0); } catch(e){} }
            var opt = new JPEGSaveOptions();
            opt.quality = quality; opt.embedColorProfile = true; opt.formatOptions = FormatOptions.STANDARDBASELINE;
            doc.saveAs(new File(it.out), opt, true, Extension.LOWERCASE);
            doc.close(SaveOptions.DONOTSAVECHANGES);
            log("OK " + it.name);
          } catch(e){
            log("ERR " + it.name + " || " + e.toString());
            try { app.activeDocument.close(SaveOptions.DONOTSAVECHANGES); } catch(e2){}
          }
        }
        app.preferences.rulerUnits = savedRulerUnits;
        log("FINISHED");
        \(config.closePhotoshop ? "try { executeAction(charIDToTypeID(\"quit\"), undefined, DialogModes.NO); } catch(e){}" : "")
        """
    }

    private static func makeAppleScript(jsxURL: URL) -> String {
        """
        set jsxText to read (POSIX file "\(jsxURL.path)") as «class utf8»
        tell application id "\(photoshopBundleID)"
            activate
            do javascript jsxText
        end tell
        """
    }

    /// Runs osascript in the background, polls the log for progress, and returns
    /// the osascript exit code + stderr (used to detect permission problems).
    private static func runAndTrack(scriptURL: URL, logURL: URL, total: Int,
                                    progress: @escaping (Int, Int, String, ExportStage) -> Void,
                                    isCancelled: @escaping () -> Bool) async -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [scriptURL.path]
        let errPipe = Pipe()
        process.standardError = errPipe
        let done = CancellationToken()

        let runner = Task.detached {
            do { try process.run(); process.waitUntilExit() } catch { }
            done.cancel()
        }

        while !done.isCancelled {
            if isCancelled() { process.terminate(); break }
            if let (completed, name) = lastProgress(logURL: logURL) {
                progress(completed, total, name, .rendering)
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        _ = await runner.value

        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = String(data: errData, encoding: .utf8) ?? ""
        return (process.terminationStatus, stderr)
    }

    private static func lastProgress(logURL: URL) -> (Int, String)? {
        guard let text = try? String(contentsOf: logURL, encoding: .utf8) else { return nil }
        var last: (Int, String)?
        for line in text.split(separator: "\n") where line.hasPrefix("PROG ") {
            let parts = line.dropFirst(5).split(separator: " ", maxSplits: 2)
            if parts.count >= 3, let i = Int(parts[0]) { last = (i, String(parts[2])) }
        }
        return last
    }

}
