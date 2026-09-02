# RAW Select

Schnelles, natives macOS-Werkzeug zum **Sichten (Culling)** von RAW-/JPG-Bildern – von der
SD-Karte oder aus einem Ordner. Gebaut für Sportfotografie: tausende Bilder nach dem Spiel
durchsteppen, Treffer markieren, auf Schärfe zoomen, Auswahl kopieren, weiter in Lightroom.

Swift + SwiftUI, AppKit für Datei-Dialoge, ImageIO für Vorschauen (RAWs werden über ihre
eingebettete Kamera-Vorschau angezeigt, beim Zoom auf 100 % voll entwickelt).

---

## Installation

1. Neuestes `RAW-Select-x.y.dmg` von den
   [GitHub-Releases](https://github.com/levinvfx/RAWSelect/releases) laden, öffnen, App nach
   `Programme` ziehen.
2. Beim ersten Start **Rechtsklick → Öffnen** (die App ist nur ad-hoc signiert, nicht notarisiert).
3. Ab dann meldet sich die App selbst, wenn es ein Update gibt (siehe *Netzwerk* unten).

Voraussetzung: macOS 14 oder neuer.

---

## Workflow

1. Links einen **Datenträger** wählen oder einen Ordner per **⌘O** / Drag-and-drop öffnen.
   Im Ordnerbaum: **Einfachklick** klappt auf, **Doppelklick** lädt die Bilder des Ordners.
2. Die ersten Bilder erscheinen nach etwa einer Sekunde, der Rest lädt weiter, während du schon
   arbeitest. Es gibt nie ein Ladesymbol im Raster – erst eine kleine Vorschau, dann scharf.
3. **Pfeiltasten** navigieren, **1–9** markieren (Farbmarkierung), **0** entfernt sie.
   Nach einer Markierung springt die App automatisch zum nächsten Bild.
4. **Return** öffnet die grosse Ansicht, **Z** oder das **Mausrad** zoomt auf 100 % – der
   Zoom-Ausschnitt bleibt beim Weiterblättern erhalten, so prüfst du eine Serie am selben
   Auge/AF-Punkt. **Tab** springt zum nächsten noch unmarkierten Bild.
5. Zweiter Durchgang über die **Filterleiste** oben: Klick auf einen Farbchip blendet die
   Gruppe aus, ⌥-Klick zeigt *nur* diese. Unter jedem Chip steht, wie viele Bilder darin sind.
6. **Auswahl kopieren…** (Symbolleiste) legt die Originale samt XMP-Sidecars flach in einen
   Zielordner. Nichts wird je überschrieben (Namenskonflikt → `_1`, `_2`, …).

Markierungen liegen **nicht** in den Dateien, sondern in `~/Library/Application Support/RAW Select`
– pro Datenträger, per Volume-UUID bzw. Karten-Fingerprint. Eine Karte wird beim nächsten
Einstecken wiedererkannt, ohne dass je etwas auf sie geschrieben wird.

---

## Tastaturkürzel

| Taste | Aktion |
|---|---|
| **← / →** | vorheriges / nächstes Bild |
| **↑ / ↓** | Raster: eine Zeile hoch/runter · Einzelansicht: vor/zurück |
| **⇧ + Pfeil** | Auswahl erweitern |
| **Home / End** | erstes / letztes Bild |
| **⇥ / ⇧⇥** | nächstes / vorheriges **unmarkiertes** Bild |
| **1 – 9** | Farbmarkierung setzen (für die ganze Auswahl) |
| **0 / § / °** | Markierung entfernen |
| **⌘Z** | letzte Markierung rückgängig |
| **⌘A** | alle Bilder im aktuellen Filter auswählen |
| **⌫** | Auswahl in den **Papierkorb** (nur von interner Platte; ab 2 Bildern mit Rückfrage) |
| **Return** | grosse Ansicht · dort: Fokusmodus (ohne Filmstreifen/Leisten) an/aus |
| **Esc** | Zoom zurück → Fokusmodus aus → zurück ins Raster |
| **Leertaste** | Zoom-Modus mit Slider (Einzelansicht) |
| **Z** | 100 % / Einpassen |
| **+ / −** | rein- / rauszoomen |
| **C** | Vergleich A\|B · ←/→ blättert B · Return macht B zu A · Esc oder C beendet |
| **I** | EXIF-Infos ein/aus |
| **F** | Vollbild |
| **?** | Kürzel-Übersicht in der App |
| **⌘O** | Ordner öffnen |
| **⌘R** | aktuelles Bild im Finder zeigen |
| **⌘,** | Einstellungen |

**Maus:** Klick wählt · ⌘-Klick fügt hinzu/entfernt · ⇧-Klick wählt eine Reihe · Doppelklick
öffnet die grosse Ansicht · **Mausrad zoomt** auf den Zeiger (Trackpad: zwei Finger schwenken,
Pinch zoomt) · ⌥-Klick auf einen Filterchip = nur diese Gruppe · Ordner aufs Fenster ziehen lädt ihn.

---

## Was die App kann

- Erkennt externe Datenträger/SD-Karten live (Ein-/Auswerfen) – wird die offene Karte gezogen,
  bricht die App laufende Vorgänge ab und sagt es dir.
- Formate: `ARW CR2 CR3 NEF RAF DNG · JPG JPEG HEIC PNG`. RAW + JPG desselben Fotos werden zu
  **einem** Eintrag gruppiert (abschaltbar in *Ansicht*); XMP-Sidecars (`IMG_0001.xmp` und
  `IMG_0001.ARW.xmp`) hängen automatisch dran und werden mitkopiert.
- Grosse Ansicht mit Filmstreifen, flackerfreie Vorschau in drei Stufen, Full-Res-Zoom mit
  vorentwickeltem Nachbarbild für Serien.
- Vergleich A|B mit synchronem Zoom.
- Sortierung nach Dateiname oder Dateidatum (Symbolleiste), Kachelgrösse per Slider (Statusleiste).
- Statusleiste: Auswahl-/Gesamtzähler, Position, Dateigrösse, Pfad.
- Kopieren mit Fortschritt und Abbrechen; Fehler (z. B. eine inzwischen fehlende Datei) werden
  gemeldet, nie verschwiegen. Kopieren **auf** die Quell-Karte fragt nach.
- Papierkorb-Ausschuss: nie ein hartes Löschen, immer der macOS-Papierkorb – und nie von SD-Karten.
- Beschädigte Session-Dateien werden beiseitegelegt statt überschrieben; Speicherfehler (Platte voll)
  werden sichtbar gemeldet; beim Beenden wird die letzte Markierung synchron gesichert.

## Einstellungen (⌘,)

- **Ansicht** – RAW+JPG gruppieren · Vorschau-Modus (Schnell / Ausgewogen / Qualität).
- **Markierungen** – Auto-Weiterspringen · Namen und Farben der Markierungen 1–9.
- **Erweitert** – Erscheinungsbild · Zielordner nach dem Kopieren im Finder zeigen ·
  anonyme Nutzungsstatistik · „Öffnen mit"-App der Symbolleiste · Cache leeren · Zurücksetzen.
- **Über** – Version, Kontakt.

Bewusst wenige Optionen; alles andere sind feste, sinnvolle Defaults.

---

## Netzwerk & Datenschutz – ehrlich

RAW Select arbeitet komplett **lokal** – Bilder, Markierungen, Kopien verlassen den Mac nie.
Zwei Dinge gehen ins Netz:

1. **Update-Check** beim Start (GitHub-API `releases/latest`, nur die Versionsnummer wird gelesen).
   Ein Update wird als DMG in *Downloads* abgelegt und geöffnet, nie automatisch installiert.
2. **Anonyme Nutzungsstatistik** (Standard: an, beim ersten Start wirst du gefragt): höchstens
   einmal täglich eine zufällige Kennung, App-Version und macOS-Version an `vfxmedia.ch`.
   Keine Dateien, Namen, Pfade, kein Standort; der Server speichert keine IP-Adressen.
   Abschaltbar unter *Einstellungen → Erweitert*.

Kein Login, keine Cloud, kein Konto.

---

## Für Entwickler

```bash
swift build                              # Debug-Build
.build/debug/RAWSelect --selftest        # Logik-Selbsttest (Scan, Sidecars, Sessions, Kopieren, Papierkorb …)
.build/debug/RAWSelect --rawcheck a.ARW  # kann macOS dieses RAW nativ entwickeln? welche Vorschau, welcher Zoom?
./build_app.sh                           # Selbsttest + Release-Build + „RAW Select.app"
```

Version bumpen = **zwei Stellen synchron**: `Sources/RAWSelect/Utilities/Constants.swift`
(`static let version`) und `build_app.sh` (`VERSION=`). Releases liegen als DMG unter `Releases/`
(nicht im Git) und auf GitHub.

**Nur im Debug-Build** (`#if DEBUG`) existiert zusätzlich ein Lightroom-Export-Stack
(Export-Wizard, Crop-/Develop-Editor mit Taste **E**, Preset-Sidecars, Bridge-Plugin
`RAWSelectBridge.lrplugin`). Er ist bewusst **nicht Teil der öffentlichen App**: das Plugin
importiert beim Rendern jedes RAW als „Geist" in den aktiven Lightroom-Katalog des Nutzers, und das
Lightroom-SDK kann diese Einträge nicht wieder entfernen. Bis das (via eigenem Wegwerf-Katalog)
gelöst ist, bleibt er Entwicklungswerkzeug. `RS_DEV_BRIDGE=1 ./build_app.sh` synchronisiert das
Plugin lokal nach `~/Library/Application Support/RAW Select/`.

### Projektstruktur (`Sources/RAWSelect/`)

- `App/` – `RAWSelectApp` (Einstieg), `AppState` (zentraler Zustand, Navigation, Tastatur), `SelfTest`
- `Models/` – `PhotoGroup`, `AppSettings`, `VolumeInfo`, `ExportModels`
- `Services/` – `PhotoScanner`, `VolumeScanner`, `ThumbnailLoader`, `SessionStore`,
  `FileOperationService`, `MetadataService`, `UpdateService`, `TelemetryService`
- `Views/` – Raster, Loupe, Vergleich, Filterleiste, Statusleiste, Sidebar, Settings
- `Utilities/` – `Constants`, `FolderIdentity`, `CancellationToken`
- `server/` – die zwei PHP-Dateien der Nutzungsstatistik (Setup in `server/README.md`)

## Bekannte Grenzen

- Nur ad-hoc signiert → beim ersten Start Rechtsklick → Öffnen.
- „Dateidatum" ist das Dateisystem-Datum, nicht das EXIF-Aufnahmedatum.
- Der Zoom auf 100 % braucht für ein RAW einen Moment („RAW lädt…"); das jeweils nächste Bild
  der Serie wird vorentwickelt.
