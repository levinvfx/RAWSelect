import Foundation

/// Keeps the Lightroom bridge plug-in in sync with the app.
///
/// The plug-in ships inside the app bundle and is copied into Lightroom's `Modules` folder,
/// which Lightroom scans by itself at startup — so a fresh install needs nothing but a
/// Lightroom restart, and an updated app can never end up talking to an outdated plug-in.
///
/// That last part is the whole point. A stale plug-in doesn't fail loudly: it simply never
/// reports the photo's white balance back, the app then has no base to add the slider's
/// nudge to, and the white-balance controls quietly do nothing at all. Shipping the app
/// without shipping its plug-in makes that the default experience for everyone who installed
/// the plug-in by hand once and never touched it again.
enum BridgeInstaller {
    static let pluginName = "RAWSelectBridge.lrplugin"

    /// Where Lightroom Classic auto-loads plug-ins from.
    static var installedURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Adobe/Lightroom/Modules")
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
