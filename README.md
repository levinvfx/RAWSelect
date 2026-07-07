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

1. Links einen **Datenträger** wählen oder **„Ordner öffnen…“** (⌘O).
2. Die App scannt rekursiv und zeigt alle Bilder im Raster.
3. Mit **Pfeiltasten** navigieren, mit **1–9** markieren, **0** entfernt die Markierung.
4. Über die **Filter** in der Sidebar nach Markierung sortieren.
5. **„Markierte kopieren…“** → Zielordner wählen → landet automatisch in
   `01_Mark_1 … 09_Mark_9`.

## Tastaturkürzel

| Taste | Aktion |
|-------|--------|
| **← / →** | vorheriges / nächstes Bild |
| **1 – 9** | Markierung setzen |
| **0** | Markierung entfernen |
| **⌘O** | Ordner öffnen |
| **⌘R** | im Finder anzeigen |

## Funktionen

- Erkennt externe Datenträger/SD-Karten unter `/Volumes` (live bei Ein-/Auswerfen).
- Formate: `.ARW .CR2 .CR3 .NEF .RAF .DNG .JPG .JPEG .HEIC .PNG`.
- **RAW + JPG desselben Fotos** werden zu einem Eintrag gruppiert: eine Markierung,
  beide Dateien wandern beim Kopieren/Verschieben zusammen.
- Raster-Ansicht **und** grosse Loupe-Ansicht mit Filmstreifen (Umschalter oben).
- Lazy geladene Thumbnails, Hintergrund-Decoding, Memory-Cache → bleibt bei
  1000–3000 Bildern flüssig, UI friert beim Scannen nicht ein.
- **Kopieren** immer erlaubt; **Verschieben** nur von internen Platten – von
  SD-Karten/externen Datenträgern ist es deaktiviert (Originalschutz) und
  zusätzlich per Bestätigungsdialog abgesichert.
- Dateikonflikte werden nie überschrieben, sondern `_1`, `_2` … angehängt.
- Fortschrittsanzeige mit Abbrechen; klare Statusmeldungen
  („1247 Bilder gefunden“, „32 Bilder kopiert“, „Keine markierten Bilder“).

## Wo werden Markierungen gespeichert?

Zentral pro Ordner unter
`~/Library/Application Support/RAW Select/Sessions/<hash>.json`.
Die **Quelle wird nie beschrieben** – SD-Karte und RAW-Dateien bleiben unangetastet.
Öffnest du denselben Ordner erneut, sind die Markierungen wieder da.

## Sicherheit

- Keinerlei Netzwerk-, Server-, FTP-, Cloud- oder Login-Funktionen.
- Löscht nie etwas von SD-Karten; Verschieben nur mit Warnung und nur von internen Platten.
- Markierungen werden **nicht** in die Originaldateien geschrieben.

## Bekannte Limitationen (MVP)

- Kein App-Icon (Standard-Systemicon).
- Nur ad-hoc signiert → beim ersten Start ggf. Gatekeeper-Hinweis.
- Loupe-Preview nutzt die eingebettete RAW-Preview; deren Auflösung hängt von der
  Kamera ab (keine volle RAW-Entwicklung – bewusst, wegen Tempo).
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
