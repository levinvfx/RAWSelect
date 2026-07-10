import Foundation
import AppKit

/// A newer release available on GitHub Releases.
struct UpdateInfo: Equatable {
    let version: String
    let notes: String
    let dmgURL: URL
}

/// Talks to the GitHub "latest release" API. No separate appcast file to host:
/// the release's tag becomes the version, its body the notes, and the attached
/// `.dmg` asset the download. Works unauthenticated for a PUBLIC repository.
enum UpdateService {
    enum UpdateError: LocalizedError {
        case http(Int), parse, noAsset
        var errorDescription: String? {
            switch self {
            case .http(let c): return "Server antwortete mit Status \(c)."
            case .parse:       return "Antwort konnte nicht gelesen werden."
            case .noAsset:     return "Im neuesten Release wurde kein DMG gefunden."
            }
        }
    }

    private static var latestReleaseURL: URL {
        URL(string: "https://api.github.com/repos/\(AppInfo.githubRepo)/releases/latest")!
    }

    /// Returns update info only if the latest published release is newer than the
    /// running build; `nil` if already up to date. Throws on network/parse errors.
    static func fetchLatest() async throws -> UpdateInfo? {
        var req = URLRequest(url: latestReleaseURL)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("RAWSelect-Updater", forHTTPHeaderField: "User-Agent")
        req.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw UpdateError.parse }
        guard http.statusCode == 200 else { throw UpdateError.http(http.statusCode) }

        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String else { throw UpdateError.parse }

        let remote = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        guard isNewer(remote, than: AppInfo.version) else { return nil }

        let notes = (obj["body"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let assets = (obj["assets"] as? [[String: Any]]) ?? []
        guard let dmg = assets.first(where: {
                  (($0["name"] as? String) ?? "").lowercased().hasSuffix(".dmg") }),
              let urlStr = dmg["browser_download_url"] as? String,
              let dmgURL = URL(string: urlStr) else { throw UpdateError.noAsset }

        return UpdateInfo(version: remote, notes: notes, dmgURL: dmgURL)
    }

    /// Download the DMG into ~/Downloads and open it (Finder mounts it), so the
    /// user can drag the new app over the old one. Returns the saved file URL.
    static func downloadAndOpen(_ info: UpdateInfo) async throws -> URL {
        let (tmp, resp) = try await URLSession.shared.download(from: info.dmgURL)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdateError.http(http.statusCode)
        }
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dest = dir.appendingPathComponent("RAW-Select-\(info.version).dmg")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        NSWorkspace.shared.open(dest)   // mounts the DMG in Finder
        return dest
    }

    /// Compare dot-separated numeric versions so that "1.10" > "1.9" and "2" > "1.9".
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

/// Drives the update UI: silent check on launch, explicit check from the menu.
@MainActor
final class UpdateController: ObservableObject {
    enum Phase: Equatable {
        case idle, checking, upToDate, downloading
        case available(UpdateInfo)
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var showSheet = false
    /// Whether the current check was user-initiated (then we also report "up to date").
    private(set) var manual = false
    private var didAutoCheck = false

    /// Silent check shortly after launch — only pops the sheet if an update exists.
    func checkOnLaunch() {
        guard !didAutoCheck else { return }
        didAutoCheck = true
        Task { await check(manual: false) }
    }

    /// Menu-triggered check — always reports the outcome, including "up to date".
    func checkManually() { Task { await check(manual: true) } }

    private func check(manual: Bool) async {
        if phase == .checking || phase == .downloading { return }
        self.manual = manual
        phase = .checking
        if manual { showSheet = true }
        do {
            if let info = try await UpdateService.fetchLatest() {
                phase = .available(info)
                showSheet = true
            } else {
                phase = .upToDate
                showSheet = manual          // never nag on the silent launch check
            }
        } catch {
            phase = .failed(error.localizedDescription)
            showSheet = manual              // stay quiet if a background check fails
        }
    }

    func download() {
        guard case .available(let info) = phase else { return }
        phase = .downloading
        Task {
            do {
                _ = try await UpdateService.downloadAndOpen(info)
                showSheet = false
                phase = .idle
                let a = NSAlert()
                a.messageText = "Update \(info.version) geladen"
                a.informativeText = "Ziehe „\(AppInfo.name)“ im geöffneten Fenster in den "
                    + "Programme-Ordner (bestehende Version ersetzen) und starte die App neu."
                a.addButton(withTitle: "OK")
                a.runModal()
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func dismiss() { showSheet = false }
}
