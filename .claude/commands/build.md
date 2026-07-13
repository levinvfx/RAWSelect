---
description: RAW Select bauen und Selbsttest laufen lassen
---

Baue und verifiziere RAW Select:

1. `swift build` ausführen.
2. Bei Erfolg `.build/debug/RAWSelect --selftest` ausführen.
3. Ergebnis knapp melden: grün/rot. Bei Fehlern die relevante Compiler- oder
   Selftest-Ausgabe zeigen, sonst nur „Build + Selftest grün".

Nichts committen oder pushen.
