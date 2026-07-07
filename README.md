# RAW Select

Eine schlichte, native und **komplett offline** macOS-App zum schnellen Sichten (Culling)
von RAW/JPG-Bildern von SD-Karte oder Ordner – als persönliche Alternative zu einem
Photo-Mechanic-artigen Workflow. Keine Cloud, kein Server, kein Login, kein Netz.

Gebaut mit **Swift + SwiftUI**, AppKit für Datei-Dialoge/Finder, **ImageIO** für schnelle
Thumbnails/Previews (RAW wird nicht entwickelt, sondern über eingebettete JPEG-Previews
angezeigt und gecacht).

---

## Starten

Es ist **kein volles Xcode** nötig – die Command Line Tools genügen.

```bash
cd "/Volumes/Levin 2TB/Neue App/RAWSelect"
./build_app.sh          # baut Release + packt "RAW Select.app"
open "RAW Select.app"   # startet die App
```

Danach liegt `RAW Select.app` im Projektordner. Du kannst sie z. B. in den
`Programme`-Ordner ziehen und wie jede App per Doppelklick starten.

> Beim ersten Start evtl. Rechtsklick → „Öffnen“ (die App ist nur ad-hoc signiert).

**Schnell während der Entwicklung** (ohne Bundle, öffnet ein Fenster):
```bash
swift run
```

**Kern-Workflow headless testen** (ohne GUI):
```bash
swift run RAWSelect --selftest
```

---

## Workflow

1. Links einen **Datenträger** wählen – die App **scannt noch nicht**, sondern zeigt die
   **Ordnerstruktur** zum Navigieren. **Doppelklick** auf einen Ordner lädt dessen Bilder
   (Einzelklick klappt nur auf/zu). Alternativ **„Ordner öffnen…“** (⌘O).
2. Die Bilder erscheinen im Raster. Beim Scrollen wird nie ein Ladesymbol gezeigt – zuerst
   eine kleine Vorschau, die dann in scharf nachlädt.
3. Mit **Pfeiltasten** navigieren, mit **1–9** markieren, **0** entfernt die Markierung.
4. **Mehrere Bilder auswählen**: ⌘-Klick fügt einzeln hinzu, Shift-Klick wählt eine
   ganze Reihe, ⌘A wählt alle im aktuellen Filter. **1–9 markiert dann alle
   ausgewählten** Bilder gleichzeitig.
5. Über die **Filterleiste** oben (immer sichtbar) Tags ein-/ausblenden: „Alle" (ohne Markierung)
   und Markierungen 1–9 sind standardmässig alle an; klick auf einen Chip **blendet** diese Gruppe
   **aus** (Chip wird ausgegraut). Die Sidebar zeigt nur die **Ordnerstruktur** – du bleibst im
   selben Ordner und filterst nur.
6. Auswahl treffen → **„Auswahl kopieren…“** → Zielordner wählen (im Dialog kannst
   du auch einen neuen Ordner anlegen). Wahl **„Bilder + XMP“** oder **„nur Bilder“**.
   Die Dateien landen **flach** im Zielordner.

## Tastaturkürzel

| Taste | Aktion |
|-------|--------|
| **← / →** | vorheriges / nächstes Bild |
| **Shift + ← / →** | Auswahl erweitern |
| **1 – 9 / 0** | Farb-Markierung setzen / entfernen (ganze Auswahl) |
| **I** | EXIF-Info-Overlay ein/aus |
| **F** | Vollbild ein/aus |
| **Klick** | einzeln auswählen |
| **⌘-Klick** | zur Auswahl hinzufügen/entfernen |
| **Shift-Klick** | Reihe auswählen |
| **⌘A** | alle im Filter auswählen |
| **⌘O** | Ordner öffnen |
| **⌘R** | im Finder anzeigen |
| **Doppelklick** | grosse Vorschau |

## Funktionen

- Erkennt externe Datenträger/SD-Karten unter `/Volumes` (live bei Ein-/Auswerfen).
- Formate: `.ARW .CR2 .CR3 .NEF .RAF .DNG .JPG .JPEG .HEIC .PNG`.
- **RAW + JPG desselben Fotos** werden zu einem Eintrag gruppiert: eine Markierung,
  beide Dateien (und passende XMP-Sidecars) wandern beim Kopieren zusammen.
- **XMP-Sidecars** (`IMG_0001.xmp` oder `IMG_0001.ARW.xmp`) werden erkannt und beim
  Kopieren optional mitkopiert.
- **Vorschau in ~720p HD**, effizient über die eingebettete Kamera-Preview – die
  volle RAW-Datei wird dabei nie geladen (nur der Pfad gemerkt, das Original erst
  beim Kopieren von der SD geholt).
- Raster-Ansicht **und** grosse Loupe-Ansicht mit Filmstreifen (Umschalter oben).
- **Mehrfachauswahl** (⌘/Shift/⌘A) – Bewerten und Kopieren gilt für die ganze Auswahl.
- **Farb-Markierungen 1–9** – nur app-intern, nie in die Dateien geschrieben.
- **EXIF-Info-Overlay** (Taste I): Kamera, Objektiv, Brennweite, Blende, Zeit, ISO, Datum.
- **Ordner-Navigator** in der Sidebar: in einen Unterordner klicken zeigt sofort alle Bilder
  dieses Ordners (Filter springt auf „Alle Bilder") – gezielt nur einen Ordner sichten statt
  der ganzen Karte.
- **Sortierung** (Dateiname/Datum, umgekehrt), **Thumbnail-Grösse** per Slider, **Vollbild** (F),
  Prefetching der Nachbar-Previews für Sichten ohne Ladezeit.
- Lazy geladene Thumbnails, Hintergrund-Decoding, Memory-Cache → bleibt bei
  1000–3000 Bildern flüssig, UI friert beim Scannen nicht ein.
- **Kopieren** der Auswahl **flach** in einen frei wählbaren Zielordner, wahlweise
  mit oder ohne XMP. **Verschieben** nur von internen Platten – von SD-Karten/externen
  Datenträgern deaktiviert (Originalschutz) und per Bestätigungsdialog abgesichert.
- Dateikonflikte werden nie überschrieben, sondern `_1`, `_2` … angehängt.
- Fortschrittsanzeige mit Abbrechen; klare Statusmeldungen
  („1247 Bilder gefunden“, „32 Bilder kopiert“, „Keine Bilder ausgewählt“).

## Tags & wie sich die App die SD-Karte merkt

- Markierungen (1–9) sind **rein app-intern** – sie werden **nie** in die Bilder oder
  XMP geschrieben. Kopierte/verschobene Dateien tragen also **keine** App-Tags.
- Gespeichert werden sie zentral unter
  `~/Library/Application Support/RAW Select/Sessions/<hash>.json`.
- Der Schlüssel basiert auf der **Volume-UUID** der Karte, nicht auf dem Mount-Pfad.
  Deshalb erkennt die App eine SD-Karte nach **Auswerfen/Wiedereinstecken** wieder und
  zeigt die Markierungen erneut an – **ohne je etwas auf die Karte zu schreiben**.

## Sicherheit

- Keinerlei Netzwerk-, Server-, FTP-, Cloud- oder Login-Funktionen.
- Löscht nie etwas von SD-Karten; Verschieben nur mit Warnung und nur von internen Platten.
- Markierungen werden **nicht** in die Originaldateien geschrieben.

## Bekannte Limitationen (MVP)

- Kein App-Icon (Standard-Systemicon).
- Nur ad-hoc signiert → beim ersten Start ggf. Gatekeeper-Hinweis.
- Die grosse Loupe-Vorschau wird scharf aus dem vollen Bild gerendert (an die
  Display-Auflösung angepasst, mind. Full HD). Beim ersten Betrachten eines RAWs
  dauert das minimal länger; danach ist es gecacht. Das Raster nutzt weiterhin
  schnelle eingebettete Previews.
- Ein Bild trägt genau **eine** Markierung (1–9), keine Mehrfach-Tags/Sterne.
- Thumbnail-Cache ist In-Memory (kein Disk-Cache über Neustarts hinweg).

## Projektstruktur

```
Sources/RAWSelect/
  App/         RAWSelectApp, AppDelegate, AppState, SelfTest
  Models/      PhotoGroup, VolumeInfo
  Services/    PhotoScanner, VolumeScanner, ThumbnailLoader,
               FileOperationService, SessionStore, FinderService
  Views/       ContentView, SidebarView, DetailView, ThumbnailGridView,
               LoupeView, ThumbnailCell, StatusBar, OperationOverlay
  Utilities/   Constants, CancellationToken
```
