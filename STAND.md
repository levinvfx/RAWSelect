# RAW Select — Stand (02.09.2026)

## Ziel
**Sprint-Fix gemerged auf `main` und gepusht** (02.09., Fast-Forward bis `b423150`, Rückfall-Tag
`pre-sprint-2026-09-02` ebenfalls auf GitHub). Öffentlich ist noch **V1.8.1** — Levin wollte bewusst
„nur mergen"; **V1.9-Release erst nach seinem Live-Test** (Version-Bump an beiden Stellen, DMG, Release).
Plan: `Audit/2026-09-02-Sprint-Fix.md`.

## Stand (belegt)
- W1 Datenverlust `6396038` · W2 Async/Tempo `41a32a6` · W3 Release-Grenze `d7593ed` ·
  W4 Doku/Datenschutz/Repo `f470aea` · W5 Workflow-UX `88d1877`. Build + Selftest + Release-Build grün.
- **Produktgrenze:** Release = reines Culling. Lightroom-Export/Editor/Bridge/Preset-Stack sind datei-weit
  `#if DEBUG`; Release-Bundle enthält kein Plugin, keinen Lightroom-Plist-Key, keine Export-Symbole.
  Lokal (`swift build`) alles da; `RS_DEV_BRIDGE=1 ./build_app.sh` synct das Plugin.
- Von Levin **noch nicht live getestet**: Vergleich A|B (Pan/Zoom-Sync, ⇧1–9 für B), First-Run-Dialog der
  Statistik, progressiver Scan bei grossem Ordner, ⌫-Rückfrage, Zähler unter den Filter-Chips.
- `server/stats.php` wird von einer anderen Session (Dashboard) bearbeitet — nicht Teil dieses Sprints.

## Entscheide (mit Grund — nicht neu ausdiskutieren)
- **Lightroom-Export ist nicht Teil der Release-App** (ganzer Stack datei-weit `#if DEBUG`, seit 02.09.):
  Bridge verschmutzt fremde Lightroom-Kataloge mit Geister-Importen, SDK kann sie nicht entfernen.
- **Engine MUSS Lightroom bleiben**: Photoshop/ACR rendert Levins KI-Masken (Motiv/Objekt) NICHT.
  Späterer Export-Fix = **eigener Wegwerf-Katalog**, NICHT Engine-Wechsel.
- **SelfTest/SliderCal sind `#if DEBUG`** (überforderten den Release-Optimierer); `build_app.sh`
  fährt den Selbsttest über das **Debug**-Binary, baut dann Release.
- **Kein Verkauf** jetzt (gratis/privat). Telemetrie default AN (Opt-out).

## Verworfen (nicht nochmal probieren)
- Photoshop/ACR oder darktable als Export-Engine → KI-Masken gehen verloren.
- Einzelne „langsame Ausdrücke" gegen Release-Build-Fehler jagen → Ursache war **korrupter
  `.build`-Cache**; Fix ist `rm -rf .build`.
- `git push --force` → vom Classifier blockiert; immer normaler Push (Token-Helper).

## Offen (Reihenfolge)
1. ~~Telemetrie scharfschalten~~ **ERLEDIGT 27.08.** (V1.8 released, Server live, Details im Memory).
2. Backlog-Task **„RAW Select Änderungen Lorenzo"** — Inhalt noch unklar, mit Levin klären.
3. Irgendwann: Katalog-Verschmutzung via Wegwerf-Katalog lösen → Export wieder einschalten.

## Dateien
- Version bumpen: `Sources/RAWSelect/Utilities/Constants.swift` **und** `build_app.sh` (beide!).
- Deploy: Token in `~/.config/rawselect/gh-token`; Release-Muster `scratchpad/make_release_17.py`.
- Telemetrie: `Services/TelemetryService.swift`, `Constants.telemetryEndpoint` (nil), Toggle in
  `Views/Settings/SettingsTabsB.swift` (Advanced), `server/` (PHP + README).

## Annahmen (Levin gegenprüfen)
- Telemetrie-Toggle default **AN** (Opt-out-Modell) — als datenschutzkonform gewählt.

_Alle Details stehen zusätzlich im Auto-Memory (`rawselect-*`), das über /clear hinweg geladen wird._
