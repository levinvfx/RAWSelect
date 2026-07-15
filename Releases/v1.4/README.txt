V1.4 – 2026-07-15
Git-Tag: v1.4 (Commit 1f61a11)

Anpassen-Schritt: nur noch Weissabgleich, Licht und Farbmischer.
Präsenz (Klarheit/Dynamik/Sättigung) und Detail (Schärfe) entfernt —
preset-eigene Werte bleiben unangetastet.

Alle Regler gegen echte Lightroom-Renders kalibriert; die Live-Vorschau
folgt jetzt über den ganzen Regelbereich dem, was Adobe beim Export macht.
Der Zoom im Entwickeln-Tab zeigt die Anpassungen live statt das Original.

Behobene Fehler, die still gewirkt haben:
- Weissabgleich war bei RAW komplett wirkungslos (Camera Raw ignoriert
  relative WB-Werte) und schrieb beim Export teils absurde Werte.
- Ungültige Regler-Werte wurden von Camera Raw verworfen statt begrenzt,
  der Regler fiel dabei still auf 0.

NEU: Das Lightroom-Plugin ist in der App enthalten und wird beim Start
automatisch installiert. Nach dem Update einmal Lightroom neu starten —
mehr ist nicht nötig. Ein von Hand installiertes altes Plugin kann nach
diesem Update entfernt werden (Zusatzmodul-Manager → Entfernen).
