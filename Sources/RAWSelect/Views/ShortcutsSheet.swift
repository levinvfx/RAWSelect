import SwiftUI

/// Keyboard-shortcut cheat sheet, toggled with `?`. Improves discoverability of
/// the culling shortcuts that were previously invisible.
struct ShortcutsSheet: View {
    @EnvironmentObject var app: AppState

    private let rows: [(String, String)] = [
        ("1 – 9",      "Farbmarkierung setzen · nochmals: entfernen"),
        ("0  /  §",    "Markierung entfernen"),
        ("⌫",          "In den Papierkorb (Ausschuss)"),
        ("⌘Z",         "Markierung rückgängig"),
        ("← / →",      "Vorheriges / nächstes Bild"),
        ("↑ / ↓",      "Eine Rasterzeile hoch / runter"),
        ("⇧ ← / →",    "Auswahl erweitern"),
        ("Home / End", "Erstes / letztes Bild"),
        ("⇥ / ⇧⇥",     "Nächstes / vorheriges unmarkiertes Bild"),
        ("Return",     "Grosse Ansicht · dann Fokusmodus"),
        ("Esc",        "Zoom zurück · Ansicht verlassen"),
        ("Leertaste",  "Zoom-Modus + Slider ein/aus (Loupe)"),
        ("Z",          "100% / Einpassen (in der Loupe)"),
        ("+ / −",      "Rein- / rauszoomen (in der Loupe)"),
        ("C",          "Vergleichen (A|B) · ←/→ rechtes Bild · ↩ B→A"),
        ("⇧1 – 9",     "Im Vergleich: B markieren"),
        ("⌥1 – 9 / ⌥0","Nur diese Markierung zeigen / alle zeigen"),
        ("⌘⇧C",        "Alle markierten Bilder kopieren…"),
        ("I",          "EXIF-Infos ein/aus"),
        ("F",          "Vollbild"),
        ("?",          "Diese Übersicht ein/aus")
    ]
    #if DEBUG
    private let devRows: [(String, String)] = [("E", "Bild bearbeiten (nur Entwicklungs-Build)")]
    #else
    private let devRows: [(String, String)] = []
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Tastaturkürzel").font(.title3.weight(.semibold))
                Spacer()
                Button { app.showShortcuts = false } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.bottom, 16)

            ForEach(rows + devRows, id: \.0) { row in
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    KeyCaps(row.0)
                        .frame(width: 128, alignment: .leading)
                    Text(row.1).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
                Divider().opacity(0.35)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

/// Renders a shortcut like the macOS menu bar does: one key cap per key, " / " and " – " kept as
/// plain separators ("1 – 9" → [1] – [9], "⇧ ← / →" → [⇧ ←] / [→]).
private struct KeyCaps: View {
    let spec: String
    init(_ spec: String) { self.spec = spec }

    private var parts: [(text: String, isKey: Bool)] {
        spec.split(separator: " ", omittingEmptySubsequences: true).map { s in
            let t = String(s)
            return (t, !(t == "/" || t == "–" || t == "-"))
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                if p.isKey {
                    Text(p.text)
                        .font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit()
                        .padding(.horizontal, 6).frame(minWidth: 22, minHeight: 22)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .controlBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
                } else {
                    Text(p.text).font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }
}
