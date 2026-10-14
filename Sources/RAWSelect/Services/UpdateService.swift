import Foundation
import AppKit
import CryptoKit

/// A newer release available on GitHub Releases.
struct UpdateInfo: Equatable {
    let version: String
    let notes: String
    let dmgURL: URL
    /// `<dmg>.sig` release asset — Ed25519 signature over `UpdateSignature.message`.
    let signatureURL: URL
}

/// Authenticity check for update DMGs. The DMG is downloaded over HTTPS from GitHub, but HTTPS only
/// proves it came FROM GitHub — not that Levin built it. Whoever controls the GitHub account (or the
/// deploy token) could otherwise ship arbitrary code to every user, and a DMG fetched by URLSession
/// carries no quarantine flag, so Gatekeeper would not look at it either.
///
/// The signed message binds the file AND the version: an old, genuinely signed DMG cannot be
/// re-published under a higher tag (downgrade to a known-buggy build). Must stay byte-identical
/// to `message()` in tools/sign_update.swift.
enum UpdateSignature {
    static func message(version: String, fileSHA256 digest: SHA256.Digest) -> Data {
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return Data("RAWSelect-Update|\(version)|\(hex)".utf8)
    }

    static var embeddedKey: Curve25519.Signing.PublicKey? {
        Data(base64Encoded: AppInfo.updatePublicKey)
            .flatMap { try? Curve25519.Signing.PublicKey(rawRepresentation: $0) }
    }

    /// True only for a well-formed signature by `key` over this exact file + version.
    static func isValid(file: URL, version: String, signatureBase64: String,
                        key: Curve25519.Signing.PublicKey? = embeddedKey) -> Bool {
        guard let key,
              let sig = Data(base64Encoded: signatureBase64.trimmingCharacters(in: .whitespacesAndNewlines)),
              let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return false }
        return key.isValidSignature(sig, for: message(version: version, fileSHA256: SHA256.hash(data: data)))
    }
}

/// Talks to the GitHub "latest release" API. No separate appcast file to host:
/// the release's tag becomes the version, its body the notes, and the attached
/// `.dmg` asset the download. Works unauthenticated for a PUBLIC repository.
enum UpdateService {
    enum UpdateError: LocalizedError {
        case http(Int), parse, noAsset, unsigned, badSignature
        var errorDescription: String? {
            switch self {
            case .http(let c): return "Server antwortete mit Status \(c)."
            case .parse:       return "Antwort konnte nicht gelesen werden."
            case .noAsset:     return "Im neuesten Release wurde kein DMG gefunden."
            case .unsigned:    return "Das Update ist nicht signiert und wird aus Sicherheitsgründen nicht geladen."
            case .badSignature: return "Die Signatur des Updates stimmt nicht – die Datei wurde verworfen."
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
              let dmgName = dmg["name"] as? String,
              let urlStr = dmg["browser_download_url"] as? String,
              let dmgURL = URL(string: urlStr) else { throw UpdateError.noAsset }
        // The signature travels as a second asset `<dmg>.sig`. Older apps ignore it (they take the
        // first asset ending in ".dmg", which ".dmg.sig" does not).
        guard let sig = assets.first(where: { ($0["name"] as? String) == dmgName + ".sig" }),
              let sigStr = sig["browser_download_url"] as? String,
              let sigURL = URL(string: sigStr) else { throw UpdateError.unsigned }

        return UpdateInfo(version: remote, notes: notes, dmgURL: dmgURL, signatureURL: sigURL)
    }

    /// Download the DMG into ~/Downloads and open it (Finder mounts it), so the
    /// user can drag the new app over the old one. Returns the saved file URL.
    static func downloadAndOpen(_ info: UpdateInfo) async throws -> URL {
        let (sigData, sigResp) = try await URLSession.shared.data(from: info.signatureURL)
        if let http = sigResp as? HTTPURLResponse, http.statusCode != 200 { throw UpdateError.http(http.statusCode) }
        guard sigData.count < 4096, let signature = String(data: sigData, encoding: .utf8) else {
            throw UpdateError.badSignature
        }

        let (tmp, resp) = try await URLSession.shared.download(from: info.dmgURL)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            try? FileManager.default.removeItem(at: tmp)
            throw UpdateError.http(http.statusCode)
        }
        // Verify BEFORE the file is placed in Downloads or opened — a forged DMG is never shown.
        guard UpdateSignature.isValid(file: tmp, version: info.version, signatureBase64: signature) else {
            try? FileManager.default.removeItem(at: tmp)
            throw UpdateError.badSignature
        }
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        // Never delete anything in the user's Downloads: a name clash gets _1, _2, … instead.
        let dest = FileOperationService.uniqueDestination(for: "RAW-Select-\(info.version).dmg", in: dir)
        try FileManager.default.moveItem(at: tmp, to: dest)
        NSWorkspace.shared.open(dest)   // mounts the DMG in Finder
        return dest
    }

    /// Compare versions numerically ("1.10" > "1.9", "2" > "1.9") with pre-releases ranked below
    /// their release: "2.0-beta1" < "2.0-beta2" < "2.0". Apps up to 1.11 ignore the suffix
    /// ("2.0-beta1" reads as 2.0 there), which still correctly offers the beta as an update.
    static func isNewer(_ a: String, than b: String) -> Bool {
        func parse(_ s: String) -> (nums: [Int], pre: Int?) {
            let parts = s.split(separator: "-", maxSplits: 1).map(String.init)
            let nums = (parts.first ?? "").split(separator: ".").map { Int($0) ?? 0 }
            guard parts.count > 1 else { return (nums, nil) }
            return (nums, Int(parts[1].filter(\.isNumber)) ?? 0)
        }
        let (pa, ra) = parse(a)
        let (pb, rb) = parse(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        switch (ra, rb) {
        case (nil, nil): return false
        case (nil, _?): return true          // final release beats its own beta
        case (_?, nil): return false
        case let (x?, y?): return x > y
        }
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
