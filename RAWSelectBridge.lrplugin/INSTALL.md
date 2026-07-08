# RAW Select Bridge – Lightroom-Plugin

Damit RAW Select **Lightroom Classic** als lokale Render-Engine benutzen kann
(Preset, Masken, Rauschreduzierung), muss dieses Plugin einmalig in Lightroom
installiert und aktiv sein.

## Installation (einmalig)

1. Lightroom Classic öffnen.
2. **Datei → Zusatzmodul-Manager…** (File → Plug-in Manager…).
3. **Hinzufügen** klicken und den Ordner **`RAWSelectBridge.lrplugin`** auswählen.
4. Fertig – im Manager sollte „RAW Select Bridge“ als **aktiviert** erscheinen.

Das Plugin startet beim Öffnen von Lightroom automatisch einen Hintergrund-Watcher.
Lightroom muss beim Export also **laufen** (RAW Select startet es bei Bedarf selbst).

## Wie es funktioniert

RAW Select legt pro Bild eine Auftragsdatei in
`~/Library/Application Support/RAW Select/LightroomBridge/jobs/` ab.
Das Plugin importiert das (temporäre) RAW – Lightroom liest dabei die daneben
liegende `.xmp` (Preset + Belichtung + Rauschreduzierung) –, exportiert ein JPEG
und meldet das Ergebnis in `…/done/` zurück. RAW Select holt das JPEG ab und legt
es im Zielordner ab. Originale werden nie verändert, es wird kein Netzwerk genutzt.

## Fehlersuche

- Protokoll: `~/Library/Application Support/RAW Select/LightroomBridge/bridge.log`
- Läuft Lightroom Classic und ist das Plugin im Zusatzmodul-Manager **aktiviert**?
- Timeout beim Export → Plugin nicht geladen oder Lightroom nicht gestartet.

## Hinweis zu „Adobe KI-Denoise (Enhance)“

Adobes echtes *Enhance → Denoise* erzeugt eine neue DNG per KI und ist von der
Lightroom-SDK **nicht** ansteuerbar. RAW Select schreibt deshalb bei aktivem
Entrauschen eine kräftige Camera-Raw-Rauschreduzierung in die `.xmp`, die dieses
Plugin beim Rendern anwendet. Das ist die effektive Entrauschung dieses Wegs.
