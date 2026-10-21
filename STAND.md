# RAW Select — Stand (21.10.2026)

## Ziel
**V2.0 (final) veröffentlicht** (21.10.2026, beide Repos, `releases/latest` = v2.0, Download-Seite leitet auf 2.0).
Davor: V1.11 (Universal-Build + Download-Seite) veröffentlicht 13.10.2026.

## Nur noch Downloads zählen, Nutzungszählung entfernt (21.10.2026)
Levins Entscheid: «ich will wirklich nichts von den Leuten, nur Downloads». Hintergrund: Mit dem YouTube-Tutorial
erreicht die App viele Leute aus Deutschland; eine feste Zählung mit gespeicherter Kennung bräuchte dort eine
Einwilligung (DSGVO, § 25 TDDDG). Statt Einwilligungsdialog: gar nichts mehr sammeln.
- **App 2.0:** `TelemetryService` gelöscht, kein Ping, kein Hinweis beim Start, Abschnitt «Nutzungszählung» in
  Einstellungen → Erweitert weg. `rs.anonID`, `rs.lastUsagePing`, `rs.usageNoticeV2` stehen in `obsoleteKeys`
  und werden bei jedem Start entfernt. `coarseOSVersion` lebt in `AppInfo` (nur noch für die Feedback-Mail).
  Einzige Netzwerkverbindung: Update-Prüfung bei GitHub.
- **Server (live 21.10.):** `ping.php` antwortet 204 und speichert nichts (Apps bis 2.0 Beta 1 pingen weiter, bis
  sie aktualisieren). Altdaten gelöscht mit Levins OK (Levin hat das Skript selbst ausgeführt, Hook blockt DROP):
  `pings` 4 + `pings_bis_2026_10_15` 51 Zeilen, danach VACUUM. Backup `/root/backups/rawselect/2026-10-21/
  usage-vor-loeschung-pings.sqlite` → nach Kontrolle löschen (Datenschutzerklärung sagt «gelöscht»).
- **Gezählt wird:** `download.php` (Klicks pro Tag, ohne IP/Cookie) + GitHub `download_count` der Release-Assets.
  Auswertung im Portfolio-Admin (Analyse → RAW Select, Portfolio-Commit 65c9f25, live). Stand 21.10.: Website 0
  seit 15.10. (alle 2.0-Beta-DMG-Downloads auf GitHub waren App-Updates: .dmg = .sig = 4), GitHub 46 insgesamt.
- **Texte:** Download-Seite (Beta-Kennzeichnung weg, «Nur Downloads werden gezählt», Satz «kostenlos, ohne Gewähr»),
  Datenschutzerklärung (Abschnitt 4 «Keine Nutzungsstatistik», ältere Versionen + Löschanfrage mit Kennung,
  Download-Zähler und GitHub-Zähler in Abschnitt 5), README, server/README, nginx-Kommentare.
- **Veröffentlicht:** `Releases/v2.0/` (DMG Universal, .sig GÜLTIG). Seite + Datenschutz deployt und live geprüft.
- **Tag-Schönheitsfehler:** `git push` scheiterte zuerst (kein Credential), `publish_release.py` legte den Tag `v2.0`
  im Code-Repo darum auf `bd1ac7d` an (Stand vor den 2.0-Commits). Lokaler Tag zeigt auf `6b51883`. Für Updater und
  Seite egal; korrigieren ginge nur per Tag-Löschen/Force (nicht gemacht).
- **Push-Weg:** immer mit Token-Helper (siehe Memory `rawselect-github-deploy`), normales `git push` hat kein Credential.

## Zählung auf 0 gesetzt (15.10.2026, 09:58) – Regel Nr. 1
Levin: „Daten auf 0, erst ab Beta tracken, ich zähle, wenn ich mein DMG lade. Ab dann: Statistiken nie mehr raten,
verändern oder auf Wunsch anpassen – nur 1:1 Auskunft." Umgesetzt ohne Löschen: `pings` → `pings_bis_2026_10_15`,
`downloads` → `downloads_bis_2026_10_15` (51 bzw. 3 Zeilen), neue leere Tabellen mit gleicher Struktur; Backup
`/root/backups/rawselect/2026-10-15/usage-vor-reset-0958.sqlite`. Dashboard zeigt 0/0. Debug-Builds pingen seit
Commit `264d13d` nie (nur die gepackte Release-App). Hintergrund: die „3 Geräte auf 2.0" waren Levins Mac, ein Kollege
und ein Test-Ping – darum zählt ab jetzt nur noch Echtes, und niemand fasst die Zahlen mehr an.

## Statistik im Portfolio-Admin (15.10.2026)
Levin: „mach das in mein Admin unter Insights, lösche den Link". Öffentliche `stats.php` (Token-URL) ist vom Server
entfernt (Backup /root/backups/rawselect/2026-10-15/), aus nginx und Repo gelöscht. Neu: Portfolio-Admin → Insights →
Abschnitt „RAW Select" (aktive Geräte 30 T., insgesamt, heute, Downloads, Versionen inkl. Beta, macOS, Verlauf).
Technik im Portfolio-Repo: `services/rawselectStats.js` (better-sqlite3 readonly), `GET /api/admin/rawselect` (adminOnly),
`js/admin-rawselect.js`. Server: `/var/lib/rawselect` auf 751, damit User `vfx` lesen kann. `~/.config/rawselect/stats-token`
wird nicht mehr gebraucht.

## 2.0 Beta 1 LIVE (15.10.2026, morgens)
Levin: „veröffentliche die Beta, auf die Webseite, alles final, Alle-Versionen-Button weg, Datenschutz/Impressum auf
eigene Seiten, Animation zum Erklären" (ultracode). Umgesetzt und live:
- Seite: `server/site/index.html` + `datenschutz.html` + `impressum.html` (nginx-Locations), geteiltes `static/site.css`
  (`?v=`-Cache-Version erhöhen bei Änderungen), Erklär-Animation `static/tutorial/` (reines JS, Fotos aus öffentlichen
  Portfolio-Seiten TST + Feusi-Cup, Kinder nur von hinten/weit). Button „Versionsübersicht" entfernt, 100&nbsp;% ohne Umbruch.
- Workflow-Prüfung (4 Prüfer, 27 Funde) umgesetzt: u. a. Kennung bleibt in ~/Library/Preferences (nicht „beim Löschen
  weg"), GitHub = USA, E-Mail-Abschnitt, http-Umleitung wird protokolliert, ping.php speichert nur „macOS X.Y" (alte
  Zeilen normalisiert, DB-Backup /root/backups/rawselect/2026-10-15/), überall „pseudonym".
- Deploy: `bash tools/deploy_site.sh [--nginx]` (lädt, prüft alle Pfade live). Test-Ping „selftest-0000" liegt in der DB
  (Löschen nur mit Levins OK, Hook blockt DELETE).

## 2.0 Beta 1 – Vorbereitung (15.10.2026)
Levins Auftrag nach einem externen Review: „ohne Apple-Signierung, Beta 2.0, noch nicht veröffentlichen, erst zeigen,
alles post-ready". Enthält den Design-Durchgang unten plus:
- **Version `2.0-beta1`** (Constants + build_app.sh; Bundle-Keys numerisch `2.0`). `UpdateService.isNewer` kennt jetzt
  Vorabversionen: 2.0-beta1 < 2.0-beta2 < 2.0; Apps ≤ 1.11 lesen 2.0-beta1 als 2.0 und bieten das Update korrekt an.
  Anzeige „2.0 Beta 1" (`AppInfo.displayVersion`) in Über und Update-Fenster.
- **Feedback:** Hilfe → Feedback senden und Chip in Über (mailto mit Version + macOS).
- **Nutzungszählung bleibt fest (Levins Entscheid), aber ehrlicher:** heisst nicht mehr „anonym", sondern pseudonym;
  Kennung sichtbar in Einstellungen → Erweitert (Kopieren, „Löschung meiner Daten verlangen" per Mail mit Kennung);
  Datenschutzerklärung mit Speicherdauer, Rechtsgrundlage (berechtigtes Interesse), Widerspruch/Löschung, EDÖB.
- **Download-Seite:** Beta-Kennzeichnung, Erststart-Anleitung für macOS 15+ („Dennoch öffnen" in Datenschutz &
  Sicherheit – Rechtsklick→Öffnen gibt es dort nicht mehr), Feedback-Hinweis. Nur lokal geprüft, NICHT hochgeladen.
- **Bereit zum Veröffentlichen:** `Releases/v2.0-beta1/` (DMG 3,2 MB Universal, .sig GÜLTIG, README.txt = Release-Text,
  ANKUENDIGUNG.txt = Instagram/WhatsApp-Text). Ablauf bei „veröffentliche": push + Tag `v2.0-beta1` →
  `python3 tools/publish_release.py 2.0-beta1` → `bash tools/deploy_site.sh`. Release NICHT als prerelease markieren,
  sonst sehen Updater und Seite es nicht (`releases/latest`).
- Bewusst nicht: Notarisierung (Levin: ohne Apple), Opt-out der Zählung (Levins früherer Entscheid; vom Review empfohlen),
  Swift-6-Sendable-Umbau, AppState aufteilen.

## Download-Seite neu getextet (15.10.2026, lokal, nicht hochgeladen)
Levins Textvorlage (sachlich, kein Werbeton) umgesetzt, gegen den Code geprüft. Abweichungen von der Vorlage, weil sie
technisch nicht stimmte: Erststart für macOS 15+ („Dennoch öffnen", Rechtsklick nur macOS 14) · nicht „App ist digital
signiert" (nur ad-hoc), sondern „Update-Dateien sind signiert" · Tasten 1–7 statt 1–9 · Schriften/Logo nach `static/`
verlegt, damit „kein IP-Protokoll" für die ganze Seite stimmt · Rechte-Abschnitt mit Kennung + Löschanfrage aus der App.
**Offen (Levins Entscheid):** Speicherdauer der Statistik – steht jetzt ehrlich „keine automatische Löschfrist, auf
Anfrage innert 30 Tagen". Alternative wäre eine echte Frist (z. B. Kennungen nach 24 Monaten Inaktivität löschen).

## Sieben Finder-Farben ohne Zahl (15.10.2026, Teil von 2.0 Beta 1)
Levin: „nur 7, gar nicht nummerieren, mehr Erkennung, Apple-Style" (Vorbild: Finder-Tag-Leiste).
- `MarkDefinition.count = 7`, Defaults in Finder-Reihenfolge Rot, Orange, Gelb, Grün, Blau, Violett, Grau; unberührte
  Defaults zeichnen mit den dynamischen `NSColor.system*` (hell/dunkel wie Finder), eigene Farben wie gespeichert.
- `MarkBadge` = Punkt ohne Ziffer, feine dunklere Kante; auf Fotos weisser Ring + Schatten. Tasten 1–7 (⇧/⌥ ebenso),
  8/9 tun nichts; `setMark`/`markPhoto` lehnen >7 ab. Statusmeldungen nennen den Namen statt der Zahl.
- **Migration:** gespeicherte Definitionen, deren Farbe UND Name ein früherer Default sind → neue Defaults; Angepasstes
  bleibt. Geladene Markierungen 8/9 → 7 (Grau) beim Öffnen (nicht unsichtbar). Folge: bestehende Markierungen behalten
  ihre Nummer, zeigen aber teils eine andere Farbe (2 war Gelb, jetzt Orange) – steht im Release-Text.
- Achtung Screenshots: Die Test-App stiehlt beim Start den Fokus – tippt Levin gleichzeitig, landen seine Tasten dort
  (so entstanden am 15.10. „Grün"-Markierungen im Demo-Ordner). Keine Fenster-Screenshots, während er aktiv ist.

## Design-Durchgang Markierungen (13.10.2026, Teil von 2.0 Beta 1)
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
  Repo – darum 1.11 in beide. Stand Statistik 13.10.: 4 Geräte auf 1.9, 1 auf 1.8, 1 auf 1.10.
- **Über-Tab:** Links „Website" + „Datenschutz"; Hinweis Nutzungszählung verlinkt die Erklärung.
- **Erledigt 13.10.:** Repo `levinvfx/RAWSelect-Releases` (öffentlich, README) angelegt und im Token freigegeben
  (per Playwright in Levins GitHub-Session), 1.11 in beide Repos veröffentlicht, Download aus dem neuen Repo
  mit `--verify-update` GÜLTIG. Token hat nur Contents read/write + Metadata (kein Admin).
- **OFFEN:** Altes Repo `levinvfx/RAWSelect` privat schalten, sobald die Statistik (Admin → Insights) keine Geräte < 1.11 mehr zeigt
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
