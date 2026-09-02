import Foundation
import AppKit

/// Anonyme, datensparsame Nutzungszählung — bewusst minimal und opt-out-bar.
///
/// Sendet NUR, wenn (1) der Nutzer es nicht abgeschaltet hat und (2) in `AppInfo.telemetryEndpoint`
/// eine URL steht, höchstens **einmal pro Tag** einen kleinen Ping mit:
///   • einer rein **zufälligen** Installations-ID (UUID, kein Hardware-/Personenbezug),
///   • der App-Version,
///   • der groben macOS-Version.
/// KEINE Dateien, Pfade, Namen, kein Standort, keine IP wird von der App gesendet. Der Server darf
/// die (technisch sichtbare) IP nicht speichern — dann bleibt das Ganze anonym (CH-DSG/DSGVO ok).
/// Schlägt der Ping fehl, passiert nichts: die App-Funktion hängt nie davon ab.
enum TelemetryService {
    private static let idKey = "rs.anonID"
    private static let lastPingKey = "rs.lastUsagePing"
    private static let noticeKey = "rs.usageNoticeShown"

    /// One-time notice BEFORE the first ping. The stats are opt-out, but nobody should learn
    /// about them only after data has already left the machine. "Ja" is the default button.
    static func askOnFirstRunIfNeeded() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: noticeKey) else { return }
        d.set(true, forKey: noticeKey)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Anonyme Nutzungsstatistik"
        alert.informativeText = "RAW Select sendet beim Start höchstens einmal täglich eine zufällige Kennung, die App-Version und die macOS-Version an vfxmedia.ch – damit sichtbar ist, welche Versionen im Einsatz sind. Keine Dateien, keine Namen, kein Standort.\n\nJederzeit änderbar unter Einstellungen → Erweitert."
        alert.addButton(withTitle: "Ja, anonym mitzählen")
        alert.addButton(withTitle: "Nein, nicht senden")
        AppSettings.shared.sendUsageStats = (alert.runModal() == .alertFirstButtonReturn)
    }

    /// Stabile, rein zufällige Kennung pro Installation. Einmalig erzeugt und lokal gespeichert;
    /// kein Bezug zu Gerät oder Person, jederzeit durch Löschen der Preferences zurücksetzbar.
    private static var anonID: String {
        let d = UserDefaults.standard
        if let id = d.string(forKey: idKey) { return id }
        let id = UUID().uuidString
        d.set(id, forKey: idKey)
        return id
    }

    /// Feuert höchstens 1×/Tag, non-blocking, alle Fehler werden still ignoriert.
    static func pingIfEnabled() {
        guard AppSettings.shared.sendUsageStats else { return }
        guard let endpoint = AppInfo.telemetryEndpoint else { return }   // kein Endpunkt → nichts senden

        let d = UserDefaults.standard
        let now = Date()
        if let last = d.object(forKey: lastPingKey) as? Date, now.timeIntervalSince(last) < 86_400 {
            return   // heute bereits gezählt
        }

        let payload: [String: String] = [
            "id": anonID,
            "version": AppInfo.version,
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 10

        URLSession.shared.dataTask(with: req) { _, resp, err in
            guard err == nil, let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
            UserDefaults.standard.set(now, forKey: lastPingKey)   // erst bei Erfolg merken
        }.resume()
    }
}
