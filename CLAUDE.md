# RAW Select — Projekt-Kontext

Native macOS-App zum schnellen Aussortieren (Culling) von RAW-Bildern, offline. Teil von Levins Kamera→NAS→Bearbeitung-Workflow. Übergabe an Lightroom/Photoshop via Bridge-Plugin.

## Stack
- **Swift / SwiftUI**, SwiftPM (`Package.swift`), Sources in `Sources/RAWSelect/`.
- Lightroom-Bridge: `RAWSelectBridge.lrplugin` — Übergabe an Lightroom, separat vom Swift-Code.

## Architektur (Sources/RAWSelect/)
- `App/` — Einstieg (`RAWSelectApp`), zentraler `AppState`, `SelfTest`.
- `Models/` — `PhotoGroup`, `AppSettings`, `ExportModels`, `VolumeInfo`.
- `Services/` — Logik-Layer: Scanner (`PhotoScanner`/`VolumeScanner`), `ThumbnailLoader`,
  `DevelopEngine`, `MetadataService`, `SessionStore`, `LightroomExportService`, `UpdateService`, …
- `Views/` — SwiftUI; darunter `Views/Export/` (Wizard, Crop) und `Views/Settings/`.
- `Utilities/` — `Constants` (u.a. `version`), `CancellationToken`, `FolderIdentity`.

## Bauen / Starten
- Build: `swift build`
- App bauen: `./build_app.sh` → erzeugt `RAW Select.app`
- Selbsttest: `.build/debug/RAWSelect --selftest`
- RAW-Zoom-Diagnose: `.build/debug/RAWSelect --rawcheck <datei.raw> …` → meldet pro RAW,
  ob macOS es nativ entwickeln kann, welches eingebettete JPEG als Fallback dient und
  welche Auflösung der Zoom nutzt (um neue Kameras/Formate ohne die Kamera zu prüfen).
- Releases als DMG unter `Releases/` (eingefroren, nicht überschreiben).

## Vor jedem Commit
- Pflicht: `swift build` **und** `.build/debug/RAWSelect --selftest` müssen grün sein.
- **Versions-Bump = zwei Stellen synchron:** `Utilities/Constants.swift` (`static let version`)
  **und** `build_app.sh` (`VERSION=`). Leicht zu vergessen.

## Wichtig
- **Geschwindigkeit** & stabile RAW/Full-HD-Vorschau ohne Ladeflackern; Tastatursteuerung; Zoom + Navigation im Zoom.
- **Wenige Einstellungen, gute Defaults** — Levin will Settings streichen, nicht vermehren.
- Kein Feature Creep; klare, konsistente Auswahlzustände.
