V1.9 – 2026-09-02
Git-Tag: v1.9

BUGFIX (wichtig)
- Schwarze Grossansicht nach Mausrad-Zoom am Bildrand (seit 1.8.1) behoben. Ursache: der
  Zoom-Anker wurde am oberen statt unteren Rand gemessen, und der Ausschnitt wurde nie ans
  Bild geklammert. Betraf auch den Z-Zoom am Mauszeiger.

NEU / GEÄNDERT
- Löschen (⌫) fragt ab 2 Bildern nach; während Kopieren/Löschen ist die Tastatur gesperrt.
- Grosse Ordner erscheinen sofort und füllen sich beim Einlesen (kein Warten mehr).
- Vergleich A|B (C): Auswahl wird A, ⇧1–9 markiert B, Schwenken/Zoom laufen synchron.
- Filter-Chips zeigen die Anzahl je Markierung; ⌥1–9 filtert eine Markierung, ⌥0 alles.
- ⌘⇧C kopiert alle markierten Bilder; Zielordner wird gemerkt; „Zuletzt geöffnet" in der Seitenleiste.
- Kopieren zurück auf dieselbe Karte wird bestätigt; Finder öffnet nur bei vollem Erfolg.
- Nachbarbilder werden im Zoom vorgeladen (schneller Schärfewechsel).
- Kontrast der Markierungsziffern, deutsche Standard-Namen für Markierungen.

ENTFERNT
- Verschieben-Funktion, „Nach Markierung sortieren", RAW+JPG-Exportoption, diverse
  wirkungslose Einstellungen.
- Lightroom-Export/Editor/Plugin sind nicht mehr Teil der öffentlichen App (reines Culling).

SONSTIGES
- Erster Start fragt einmalig, ob anonym mitgezählt werden darf (jederzeit abschaltbar).
- Updater überschreibt keine vorhandenen Downloads mehr.
