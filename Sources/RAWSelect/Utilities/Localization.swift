import Foundation

/// Localized text for `String` contexts (status line, toasts, alerts, AppKit panels).
/// German is the source language and doubles as the key; `en.lproj/Localizable.strings` holds the
/// English text. SwiftUI literals (`Text("…")`, `Button("…")`) are looked up the same way without it.
/// Every key the compiler sees is checked against the English table by `tools/check_l10n.py`.
func L(_ key: String.LocalizationValue) -> String { String(localized: key) }

enum AppLanguage {
    /// True when the app runs in German (the system picked `de.lproj`), false for English.
    static var isGerman: Bool { Bundle.main.preferredLocalizations.first?.hasPrefix("de") ?? true }
}
