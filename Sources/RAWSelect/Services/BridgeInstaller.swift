// DEVELOPMENT ONLY — not part of the public (release) app. The public product is a pure
// culling tool; the Lightroom export/editor stack stays available in `swift build` (debug).
#if DEBUG
import Foundation

/// Keeps the Lightroom bridge plug-in in sync with the app.
///
/// The plug-in ships inside the app bundle and is kept current at a stable location. The app
/// can then never end up talking to an outdated plug-in — a stale one doesn't fail loudly, it
/// simply stops reporting the photo's white balance, and the WB controls quietly do nothing.
///
/// ⚠️ Lightroom Classic 15.x no longer runs a Modules-folder plug-in's scripts on auto-load
/// (measured 02.08.2026: it "half-loads" — the plug-in shows as activated, but Init.lua and the
/// menus never run, so the watcher stays dead). The plug-in must therefore be ADDED ONCE by hand
/// via Datei → Zusatzmodul-Manager → Hinzufügen from `installedURL`. The app only keeps the files
/// at that path in sync; it deliberately does NOT touch Lightroom's Modules folder anymore.
enum BridgeInstaller {
    static let pluginName = "RAWSelectBridge.lrplugin"

    /// Stable path the plug-in is kept in sync at, and the folder the user adds once in the
    /// Zusatzmodul-Manager. NOT Lightroom's Modules folder (that path half-loads on LrC 15.x).
    static var installedURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/RAW Select")
            .appendingPathComponent(pluginName)
    }

    /// The copy inside the app bundle. nil in a plain `swift build` run (no bundle).
    static var bundledURL: URL? {
        guard let res = Bundle.main.resourceURL else { return nil }
        let u = res.appendingPathComponent(pluginName)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    /// Installs the bundled plug-in when it's missing or differs from what's installed.
    /// Returns true if it actually (re)installed. Safe to call on every launch: it does
    /// nothing when the two already match, and nothing at all in dev builds.
    @discardableResult
    static func installIfNeeded() -> Bool {
        guard let src = bundledURL else { return false }
        let dst = installedURL
        if scriptsMatch(src, dst) { return false }
        let fm = FileManager.default
        try? fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: dst)
        do { try fm.copyItem(at: src, to: dst) } catch { return false }
        return true
    }

    /// True when both folders hold the same `.lua` scripts, byte for byte. Comparing the
    /// actual files beats a version number, which can drift from what is really installed —
    /// and this plug-in has already been out of sync with the repo once.
    static func scriptsMatch(_ a: URL, _ b: URL) -> Bool {
        let fm = FileManager.default
        guard let aNames = try? fm.contentsOfDirectory(atPath: a.path),
              let bNames = try? fm.contentsOfDirectory(atPath: b.path) else { return false }
        let aLua = Set(aNames.filter { $0.hasSuffix(".lua") })
        let bLua = Set(bNames.filter { $0.hasSuffix(".lua") })
        guard !aLua.isEmpty, aLua == bLua else { return false }
        for n in aLua {
            let x = try? Data(contentsOf: a.appendingPathComponent(n))
            let y = try? Data(contentsOf: b.appendingPathComponent(n))
            guard let x, let y, x == y else { return false }
        }
        return true
    }
}
#endif
