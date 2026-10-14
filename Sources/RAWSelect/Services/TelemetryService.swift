import Foundation
import AppKit

/// Datensparsame Nutzungszählung — fester Bestandteil der App (seit V1.10 nicht abschaltbar,
/// Levins Entscheid: er will die echte Zahl der Nutzer sehen).
///
/// Ehrlich benannt ist sie PSEUDONYM, nicht anonym: die Kennung bleibt über Tage gleich, sonst
/// liessen sich Geräte nicht zählen. Darum sieht jede Person ihre Kennung in Einstellungen →
/// Erweitert und kann die Löschung ihrer Einträge verlangen. Höchstens **einmal pro Tag** ein kleiner
/// Ping mit:
///   • einer rein **zufälligen** Installations-ID (UUID, kein Hardware-/Personenbezug),
///   • der App-Version,
///   • der groben macOS-Version (z. B. „macOS 26.6“ — ohne Build-Nummer).
/// KEINE Dateien, Pfade, Namen, kein Standort. Der Server speichert keine IP — auch das
/// Webserver-Log ist für /rawselect/ abgeschaltet (server/nginx-rawselect.conf). Wer diese Garantie
/// aufweicht (IP loggen, Pfade senden …), macht aus der datensparsamen Zählung eine Profilbildung.
/// Schlägt der Ping fehl, passiert nichts: die App-Funktion hängt nie davon ab.
enum TelemetryService {
    private static let idKey = "rs.anonID"
    private static let lastPingKey = "rs.lastUsagePing"
    /// v2: seit die Zählung fest ist. Auch wer früher „Nein“ gewählt hat, sieht den neuen
    /// Hinweis einmal — niemand soll still mitgezählt werden, ohne es je gelesen zu haben.
    private static let noticeKey = "rs.usageNoticeV2"

    /// One-time notice BEFORE the first ping of this build generation. Informational only.
    static func showNoticeIfNeeded() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: noticeKey) else { return }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Nutzungszählung"
        alert.informativeText = "RAW Select ist gratis. Damit sichtbar ist, wie viele Leute die App nutzen, meldet sie beim Start höchstens einmal täglich eine zufällige Kennung, die App-Version und die macOS-Version an vfxmedia.ch.\n\nKeine Dateien, keine Namen, kein Standort, keine IP-Adresse. Deine Kennung siehst du unter Einstellungen → Erweitert, dort kannst du auch die Löschung verlangen."
        alert.addButton(withTitle: "Verstanden")
        alert.runModal()
        d.set(true, forKey: noticeKey)
    }

    /// Die Kennung, wie sie gesendet wird — für die Anzeige in den Einstellungen (Löschanfrage).
    static var installationID: String { anonID }

    /// Pre-filled deletion request: carries the id, so the entries can be found and removed.
    static var deletionRequestURL: URL {
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = AppInfo.email
        c.queryItems = [
            URLQueryItem(name: "subject", value: "RAW Select – Löschung meiner Nutzungsdaten"),
            URLQueryItem(name: "body", value: "Bitte lösche alle Einträge der Nutzungszählung zu dieser Kennung:\n\(installationID)\n"),
        ]
        return c.url ?? AppInfo.emailURL
    }

    /// Stabile, rein zufällige Kennung pro Installation. Einmalig erzeugt und lokal gespeichert;
    /// nicht aus Hardware abgeleitet und mit keinem Namen verknüpft.
    private static var anonID: String {
        let d = UserDefaults.standard
        if let id = d.string(forKey: idKey) { return id }
        let id = UUID().uuidString
        d.set(id, forKey: idKey)
        return id
    }

    /// „macOS 26.6“ — Major.Minor reicht für die Statistik; Patch und Build-Nummer wären nur
    /// zusätzliche Unterscheidungsmerkmale ohne Nutzen.
    static var coarseOSVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion)"
    }

    /// Feuert höchstens 1×/Tag, non-blocking, alle Fehler werden still ignoriert.
    static func ping() {
        guard let endpoint = AppInfo.telemetryEndpoint else { return }   // kein Endpunkt → nichts senden

        let d = UserDefaults.standard
        let now = Date()
        if let last = d.object(forKey: lastPingKey) as? Date, now.timeIntervalSince(last) < 86_400 {
            return   // heute bereits gezählt
        }

        let payload: [String: String] = [
            "id": anonID,
            "version": AppInfo.version,
            "os": coarseOSVersion,
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
