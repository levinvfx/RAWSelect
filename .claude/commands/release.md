---
description: Release bauen (Version prüfen/bumpen, App packen) — ohne Auto-Commit
argument-hint: "[version, z.B. 1.5]"
---

Baue einen Release von RAW Select. Zielversion: `$ARGUMENTS` (falls leer: bestehende Version verwenden).

1. **Version prüfen/bumpen — zwei Stellen synchron:**
   - `Sources/RAWSelect/Utilities/Constants.swift` → `static let version`
   - `build_app.sh` → `VERSION=`
   Wenn eine Version angegeben ist, beide auf diesen Wert setzen. Sonst prüfen, dass beide gleich sind
   und Abweichungen melden.
2. **`./build_app.sh`** ausführen — baut release, läuft Selbsttest, packt `RAW Select.app`.
3. **DMG bauen und signieren** (Pflicht seit V1.10 – Apps lehnen unsignierte Updates ab):
   `swift tools/sign_update.swift sign ~/.config/rawselect/update-signing.key Releases/v<version>/RAW-Select-<version>.dmg <version>`
   → erzeugt `<dmg>.sig`. Gegenprobe mit dem App-Code: `.build/debug/RAWSelect --verify-update <dmg> <version> <dmg>.sig`.
4. **Danach nur vorschlagen** (nicht selbst ausführen):
   - DMG unter `Releases/` ablegen — bestehende `Releases/` (v1.0–v1.2 …) sind eingefroren, nie überschreiben.
   - git-Tag, z.B. `git tag v<version>` + Commit der Versions-Dateien.
   - Veröffentlichen: `python3 tools/publish_release.py <version>` (prüft die Signatur, lädt .sig + DMG hoch).

WICHTIG: Nicht automatisch committen, pushen oder taggen. Levin bestätigt diese Schritte selbst.
