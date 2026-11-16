import Foundation

/// Counts installations (since 2.2.2, Levin 16.11.2026: he wants to know exactly how many people
/// use the app). Once per app version the app sends a random number and its version to
/// vfxmedia.ch — nothing else: no macOS version, no model, no language. The server keeps only a
/// salted hash of the number (`server/start.php`).
/// On by default without a prompt, switchable in Settings → Erweitert. Development builds never
/// report, so test runs do not inflate the count.
enum InstallCounter {
    static let endpoint = URL(string: "https://vfxmedia.ch/rawselect/start")!

    /// Whether this start has to report: counting is on and this version has not been confirmed yet.
    static func shouldReport(enabled: Bool, reportedVersion: String, currentVersion: String) -> Bool {
        enabled && reportedVersion != currentVersion
    }

    /// The complete request body. Exactly two fields — the server rejects anything it cannot parse.
    static func body(id: String, version: String) -> Data {
        // Fixed key order and no escaping surprises: both values are plain ASCII by construction.
        Data("{\"id\":\"\(id)\",\"v\":\"\(version)\"}".utf8)
    }

    /// A lowercase UUID v4, the only identifier the app ever creates. It identifies the installation,
    /// not the person or the Mac, and is new after the settings file is deleted.
    static func newID() -> String { UUID().uuidString.lowercased() }

    /// Called once at launch. Silent: no message on success or failure; a failed attempt is simply
    /// repeated at the next launch, because the version is only remembered after the server said 204.
    @MainActor
    static func reportIfNeeded(settings: AppSettings = .shared) {
        #if DEBUG
        return
        #else
        let version = AppInfo.version
        guard shouldReport(enabled: settings.countInstallation, reportedVersion: settings.reportedVersion,
                           currentVersion: version) else { return }
        if settings.installID.isEmpty { settings.installID = newID() }
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 6)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // URLSession would add the system's languages and its own agent string by default.
        request.setValue("RAWSelect", forHTTPHeaderField: "User-Agent")
        request.setValue("*", forHTTPHeaderField: "Accept-Language")
        request.httpBody = body(id: settings.installID, version: version)
        Task {
            guard let (_, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 204 else { return }
            settings.reportedVersion = version
        }
        #endif
    }
}
