# RAW Select — Stand (13.10.2026, abends)

## Ziel
**V1.11 (Universal-Build + Download-Seite) veröffentlicht** (13.10.2026, Tag `v1.11`, in beiden Repos).
Vorher: V1.10 (Sicherheit & Datenschutz) veröffentlicht 11.10.2026.

## Design-Durchgang Markierungen 1–9 (13.10.2026, unveröffentlicht)
Levins Auftrag: „1–9 einheitlich, Farben, Apple-Finder-Look, ganze App gründlich". Umgesetzt:
- **Eine Komponente** `Views/MarkBadge.swift` (`MarkBadge`, `UnmarkedBadge`) zeichnet jede Markierung: Kreis in
  Markenfarbe, Ziffer SF Rounded semibold, `.filled`/`.outline`, optionaler weisser Ring auf Fotos. Genutzt in
  Raster/Filmstreifen (Grösse 16–24 pt proportional zur Kachel), Filterleiste (Kreise statt Quadrate, Aus = Umriss,
  kein Rahmenkasten mehr), Loupe- und Vergleichs-Pill (Ziffer + Name), Einstellungen (Live-Vorschau) und dem
  DEBUG-Export-Wizard. grep nach lokalen Badge-Zeichnungen findet nichts mehr.
- **Palette = macOS-Systemfarben** (Finder-Tags): 1 Rot FF3B30 · 2 Gelb FFCC00 · 3 Grün 34C759 · 4 Blau 007AFF ·
  5 Violett AF52DE · 6 Türkis 5AC8FA · 7 Braun A2845E · 8 Grau 8E8E93 (statt Schwarz) · 9 Orange FF9500 (statt
  Weiss – war auf hellem Raster unsichtbar). **Migration:** gespeicherte Marken, die exakt eine alte Neon-Default-Farbe
  tragen, folgen der neuen Palette; eigene Farben/Namen bleiben (`MarkDefinition.localized`, Selftest).
- **Ziffernfarbe** per WCAG-Kontrast (`Color.prefersDarkText`), nicht mehr per Luma-Schwelle.
- Kürzel-Fenster: Tasten als Key-Caps (wie Menüleiste), Beschreibungen umbrechen statt abschneiden.
- **Screenshot-Haken (nur DEBUG, `AppState.start()`):** `RS_OPEN_FOLDER`, `RS_APPEARANCE=light|dark`, `RS_DEMO_MARKS=1`,
  `RS_FILTER_OFF=2,5,0`, `RS_VIEW=loupe|compare|settings|shortcuts`, `RS_SETTINGS_TAB=marks`. Vorher/Nachher-Bilder
  im Scratchpad erzeugt (Headless-Fensterfoto via CGWindowList + screencapture).
- Ergebnis: Apple-Style ist jetzt konsistent; die übrige Oberfläche (Raster, Loupe, Status, Sidebar, Dialoge) war
  bereits nativ und blieb unangetastet. Nicht veröffentlicht, kein Versions-Bump – Levin testet zuerst.

## V1.11 / Public-Release-Plan 13.10.2026 (belegt)
Levins Entscheid aus dem „Public Release Master Prompt": nur Punkte 2–4 (Universal Binary, Download-Seite,
Datenschutz/Impressum), **kein** Apple Developer Program (99 $/Jahr) vorerst, **Code-Repo privat machen**.
Windows/Linux, Lizenz-Audit (null Abhängigkeiten), 13-Dokumente-„Release Control Center", CI, Crash-Reporting:
bewusst gestrichen.
- **Universal Binary:** `build_app.sh` baut arm64 + x86_64 getrennt (`--triple`, Xcode-loses `--arch` geht nicht)
  und fügt per `lipo` zusammen; Intel-Slice wird unter Rosetta gestartet (Smoke). DMG 1.11 = 3,2 MB, signiert,
  `--verify-update` GÜLTIG (falsche Version UNGÜLTIG).
- **Download-Seite live:** `https://vfxmedia.ch/rawselect/` (nginx direkt aus `/var/www/rawselect/`, Papier-und-Tinte-
  Design der Hauptseite, Erststart-Hinweis Rechtsklick→Öffnen, Kürzel, Datenschutzerklärung, Impressum
  Levin Anneler / Mühlemattweg 2k / levin@annelers.ch). `server/site/`, `server/download.php`
  (302 auf neuestes signiertes DMG, 10-Min-Cache, Download-Zähler ohne IP → stats.php), nginx-Allowlist erweitert.
  Desktop + Handy per Headless-Chrome geprüft.
- **Repo-Wechsel für Updates:** `AppInfo.githubRepo = levinvfx/RAWSelect-Releases` (Download-Repo, nur DMG + .sig).
  `publish_release.py` veröffentlicht in ALLE Repos (`REPOS`), 404 wird übersprungen. Apps ≤ 1.10 fragen das alte
  Repo – darum 1.11 in beide. Stand stats.php 13.10.: 4 Geräte auf 1.9, 1 auf 1.8, 1 auf 1.10.
- **Über-Tab:** Links „Website" + „Datenschutz"; Hinweis Nutzungszählung verlinkt die Erklärung.
- **Erledigt 13.10.:** Repo `levinvfx/RAWSelect-Releases` (öffentlich, README) angelegt und im Token freigegeben
  (per Playwright in Levins GitHub-Session), 1.11 in beide Repos veröffentlicht, Download aus dem neuen Repo
  mit `--verify-update` GÜLTIG. Token hat nur Contents read/write + Metadata (kein Admin).
- **OFFEN:** Altes Repo `levinvfx/RAWSelect` privat schalten, sobald stats.php keine Geräte < 1.11 mehr zeigt
  (Token kann das nicht – Levin macht das auf GitHub: Settings → Danger Zone → Change visibility, oder ich per
  Playwright in seiner Session). Screenshot der App für die Seite fehlt (Hero zeigt nur das Icon).

## V1.10 / Audit 11.10.2026 (belegt)
- **Leck behoben (Server):** `stats.php.bak` lag seit 02.09. im Webroot und wurde samt Stats-Token als
  Klartext ausgeliefert → verschoben nach `/root/backups/rawselect/2026-10-11/`, Token erneuert.
- **nginx-Snippet** (`server/nginx-rawselect.conf`): nur `ping.php`/`stats.php` erreichbar, Rest 404;
  `access_log off` → es wird **keine IP** mehr gespeichert (vorher 14 Tage IP+App-Version im Log).
- **Nutzungszählung fest** (Levins Entscheid: will echte Nutzerzahl): kein Schalter mehr, einmaliger
  Hinweis „Verstanden" (Key `rs.usageNoticeV2`, auch für frühere „Nein"-Wähler), grobe macOS-Version.
  Zulässig nur, weil wirklich anonym (keine IP) — Bedingung steht in TelemetryService + server/README.
- **Signierte Updates:** Ed25519; öffentlicher Schlüssel in `AppInfo.updatePublicKey`, privater in
  `~/.config/rawselect/update-signing.key` (NUR dort — Verlust = keine Auto-Updates mehr ab 1.10).
  Signiert wird `RAWSelect-Update|<version>|<sha256>` (kein Downgrade/Replay). `tools/sign_update.swift`,
  `tools/publish_release.py` (bricht ohne gültige Signatur ab), Prüf-CLI `--verify-update` (DEBUG).
- **Toter Code raus:** Session-Import/-Export (hatte Path-Traversal), Verschieben/Überschreiben im
  Kopierpfad, 113 tote Preference-Keys werden beim Start entfernt.
- Bewusst NICHT: Löschfrist für Statistik-Rohdaten (würde Levins All-time-Zahlen schrumpfen; Daten
  sind anonym) · Swift-6-Sendable-Umbau (19 Warnungen, kein Bug heute) · Apple-Notarisierung (99 $/Jahr).

## Stand (belegt)
- W1 Datenverlust `6396038` · W2 Async/Tempo `41a32a6` · W3 Release-Grenze `d7593ed` ·
  W4 Doku/Datenschutz/Repo `f470aea` · W5 Workflow-UX `88d1877`. Build + Selftest + Release-Build grün.
- **Produktgrenze:** Release = reines Culling. Lightroom-Export/Editor/Bridge/Preset-Stack sind datei-weit
  `#if DEBUG`; Release-Bundle enthält kein Plugin, keinen Lightroom-Plist-Key, keine Export-Symbole.
  Lokal (`swift build`) alles da; `RS_DEV_BRIDGE=1 ./build_app.sh` synct das Plugin.
- **Zoom-Hotfix `89363e5`** (Kollegen-Meldung „schwarze Grossansicht" seit 1.8.1): NSScrollView ist flipped,
  der Anker-Anteil fy war verkehrt herum; zudem klemmt `NSClipView.scroll(to:)` nie ans Dokument → neuer
  `scrollClamped(to:)`. Headless-Test `App/SelfTestZoom.swift` (14 Checks) reproduziert und sichert es ab.
- Levin hat 1.9 lokal getestet und freigegeben („veröffentliche").
- Projekt liegt seit Okt. 2026 unter `~/Developer/Business/RAWSelect` (nicht mehr OneDrive) — `.build` ist
  wieder ein normaler Ordner. DMGs/Signaturen in `Releases/` sind gitignored.
- `server/stats.php` wird von einer anderen Session (Dashboard) bearbeitet — nicht Teil dieses Sprints.

## Entscheide (mit Grund — nicht neu ausdiskutieren)
- **Lightroom-Export ist nicht Teil der Release-App** (ganzer Stack datei-weit `#if DEBUG`, seit 02.09.):
  Bridge verschmutzt fremde Lightroom-Kataloge mit Geister-Importen, SDK kann sie nicht entfernen.
- **Engine MUSS Lightroom bleiben**: Photoshop/ACR rendert Levins KI-Masken (Motiv/Objekt) NICHT.
  Späterer Export-Fix = **eigener Wegwerf-Katalog**, NICHT Engine-Wechsel.
- **SelfTest/SliderCal sind `#if DEBUG`** (überforderten den Release-Optimierer); `build_app.sh`
  fährt den Selbsttest über das **Debug**-Binary, baut dann Release.
- **Kein Verkauf** jetzt (gratis/privat). Nutzungszählung seit V1.10 fest (anonym, ohne IP).

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
- Deploy: Token in `~/.config/rawselect/gh-token`; Ablauf in `.claude/commands/release.md`:
  bauen → DMG signieren → Tag pushen → `python3 tools/publish_release.py <version>`.
- Zählung: `Services/TelemetryService.swift`, `Constants.telemetryEndpoint`, `server/` (PHP, nginx, README).

## Annahmen (Levin gegenprüfen)

_Alle Details stehen zusätzlich im Auto-Memory (`rawselect-*`), das über /clear hinweg geladen wird._
