# RAW Select V1.1 — Installation & Update

Lokale, offline Culling-App (Photo-Mechanic-Alternative). Markieren/Aussortieren
läuft eigenständig; der **JPEG-Export** nutzt **Lightroom Classic** als Render-Engine.

## Voraussetzungen
- **Mac mit Apple Silicon** (M1/M2/M3/M4). Auf Intel-Macs läuft diese Version nicht.
- **macOS 14 (Sonoma) oder neuer.**
- **Nur für den Export:** Adobe **Lightroom Classic** + das mitgelieferte Plugin.

---

## Neu installieren (erstes Mal)
1. `RAW Select v1.1.dmg` doppelklicken → Fenster öffnet sich.
2. `RAW Select.app` auf das **Programme**-Symbol im selben Fenster ziehen.
3. **Erststart:** Rechtsklick auf die App → **Öffnen** → nochmal **Öffnen**
   (nötig, weil die App nicht über den App-Store signiert ist). Danach normal per Doppelklick.

## Aktualisieren (von einer älteren Version auf 1.1)
Du musst **nichts löschen** — die neue Version überschreibt die alte:
1. **RAW Select beenden**, falls es läuft.
2. `RAW Select v1.1.dmg` öffnen → `RAW Select.app` auf **Programme** ziehen.
3. macOS fragt „**„RAW Select" existiert bereits. Ersetzen?**" → **Ersetzen**.
4. **Erststart der neuen Version:** wieder einmal **Rechtsklick → Öffnen** (Quarantäne).

**Deine Daten bleiben erhalten** (Markierungen, Einstellungen, Lightroom-Plugin) —
die liegen ausserhalb der App und werden beim Ersetzen nicht angefasst.

---

## Lightroom-Plugin (nur für Export, einmalig)
1. Ordner `RAWSelectBridge.lrplugin` aus dem DMG an einen **festen Ort** ziehen
   (empfohlen: `~/Library/Application Support/Adobe/Lightroom/Modules/` → dann lädt
   Lightroom es automatisch). Nicht im DMG lassen.
2. Lightroom Classic → **Datei → Zusatzmodul-Manager → Hinzufügen** → den Ordner wählen.
3. Fertig. (Bei einem App-Update muss das Plugin nur neu installiert werden, wenn es
   sich geändert hat — sonst bleibt es einfach liegen.)

## Kurz-Bedienung
- Datenträger/Ordner links wählen, **Doppelklick** auf einen Ordner lädt die Bilder.
- **1–9** Farbmarkierung · **X**/Ausschuss entfällt · **I** EXIF · **F** Vollbild · **?** alle Kürzel.
- **Return** grosse Ansicht · **Leertaste** Zoom-Modus + Slider · **Z** 100% · in der Loupe zoomen zur Maus.
- Filterleiste: Klick blendet eine Farbe aus, **⌥-Klick** zeigt nur diese.

Fragen/Fehler? Kurze Beschreibung + Screenshot an Levin.
