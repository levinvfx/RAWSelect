# RAW Select — Stand (25.08.2026)

## Ziel
RAW Select ist auf **V1.7 öffentlich**. Aktuell keine laufende Code-Arbeit — Working Tree sauber,
alles committet. Nächster echter Punkt: Telemetrie-Server scharfschalten (unten).

## Stand (belegt)
- **V1.7 public**: Commit `c52d789`, GitHub-Release live, DMG hochgeladen, `releases/latest` = v1.7
  (Auto-Updater greift). Build + Selbsttest grün (`bash build_app.sh`).
- Drin seit 1.6: ⌘A wählt alle aus · ↑/↓ auch in Einzelansicht · permanenter Auswahl-/Gesamtzähler ·
  Raster scrollt beim Wechsel zum aktuellen Bild · kritischer Deadlock beim Beenden behoben ·
  anonyme Opt-out-Telemetrie eingebaut (sendet noch nichts, s.u.).

## Entscheide (mit Grund — nicht neu ausdiskutieren)
- **Lightroom-Export bleibt in Release ausgeblendet** (`AppInfo.lightroomExportEnabled` = `#if DEBUG`):
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
1. **Telemetrie scharfschalten**: Levin lädt `server/ping.php` + `stats.php` auf seinen Hoststar,
   dann URL in `AppInfo.telemetryEndpoint` eintragen → neues Release. Bis dahin sendet die App NICHTS.
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
