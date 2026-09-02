import SwiftUI

/// Keyboard-shortcut cheat sheet, toggled with `?`. Improves discoverability of
/// the culling shortcuts that were previously invisible.
struct ShortcutsSheet: View {
    @EnvironmentObject var app: AppState

    private let rows: [(String, String)] = [
        ("1 – 9",      "Farbmarkierung setzen"),
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
                HStack(spacing: 14) {
                    Text(row.0)
                        .font(.body.monospaced().weight(.medium))
                        .frame(width: 96, alignment: .leading)
                    Text(row.1).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 7)
                Divider().opacity(0.35)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}
