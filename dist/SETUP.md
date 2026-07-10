# RAW Select V1.2 (Beta) — Installation & Update

⚠️ **Beta / Vorschau:** Diese Version enthält den neuen **Lightroom-artigen Zuschneiden-Editor**
(Bild bleibt fix, Grid wird kleiner; Ecken/Kanten schneiden, innen verschieben, aussen drehen).
Sie ist noch in Arbeit — Feedback erwünscht.

## Voraussetzungen
- **Mac mit Apple Silicon** (M1/M2/M3/M4). Nicht für Intel-Macs.
- **macOS 14 (Sonoma) oder neuer.**
- **Nur für den Export:** Adobe **Lightroom Classic** + das mitgelieferte Plugin.

## Neu installieren
1. `RAW Select v1.2-beta.dmg` doppelklicken → Fenster öffnet sich.
2. `RAW Select.app` auf das **Programme**-Symbol ziehen.
3. **Erststart:** Rechtsklick auf die App → **Öffnen** → nochmal **Öffnen** (weil nicht Apple-signiert).

## Aktualisieren (von 1.0/1.1 auf 1.2)
Nichts löschen — die neue Version überschreibt die alte:
1. **RAW Select beenden**, falls es läuft.
2. DMG öffnen → `RAW Select.app` auf **Programme** ziehen → **„Ersetzen"**.
3. **Erststart:** einmal **Rechtsklick → Öffnen**.
4. Markierungen, Einstellungen und das Plugin **bleiben erhalten**.

## Lightroom-Plugin (nur für Export, einmalig)
`RAWSelectBridge.lrplugin` an einen festen Ort ziehen (empfohlen:
`~/Library/Application Support/Adobe/Lightroom/Modules/`), dann in Lightroom Classic:
**Datei → Zusatzmodul-Manager → Hinzufügen** → den Ordner wählen.

## Neu in 1.2 (bisher)
- **Zuschneiden wie Lightroom:** Bild fix, Grid verkleinert sich; Ecken/Kanten = schneiden,
  innen = verschieben, im Rand aussen = drehen (mit Dreh-Cursor). Standard: Originalformat gesperrt.
- **§-Taste** (links der 1) entfernt eine Markierung, wie die 0.

Fragen/Feedback: kurze Beschreibung + Screenshot an Levin.
