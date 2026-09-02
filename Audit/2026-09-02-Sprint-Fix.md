# RAW Select — Sprint-Fix (Wellen + Tasks)

Stand 02.09.2026, Basis Commit `e5cf5cb` (V1.8.1). Quellen: Claude-Audit (3 Lese-Agenten + eigene
Verifikation) und ChatGPT-Analyse — jede Behauptung am Code geprüft; widerlegte/korrigierte Punkte unten.

## Produktgrenze (Levins Entscheid, 02.09.)
- **Öffentliche Version = reines Culling.** Lightroom-Export, Bridge-Plugin, Develop-/Crop-Editor,
  Preset-Infrastruktur und toter Code sind im ausgelieferten Produkt **nicht enthalten** — weder im
  Binary noch im Bundle noch als Nebenwirkung (Plugin-Installation, Settings).
- **Lokal (Debug-Build) bleibt alles drin**, hinter `#if DEBUG` (bewährtes Muster: SelfTest/SliderCal).
  Lightroom bleibt die spätere Export-Engine (KI-Masken), Fix dann via Wegwerf-Katalog — nicht Thema hier.
- Weiterhin drin: Auto-Updater (funktioniert nachweislich), Nutzungsstatistik (opt-out), Marks 1–9.

## Korrekturen an den Reviews (nicht umsetzen)
- ChatGPT/Agent „Write-Chain-Race in persistStateNow" → **widerlegt**: `sem.wait()` blockiert den
  Main-Thread, kein Tastendruck kann dazwischen. Kein Fix nötig.
- Agent „Auto-Updater streichen" → **falsch**: Updater lieferte 1.6→1.7→1.8 an die Kollegen; nur der
  Kommentar in `Constants.swift` ist veraltet.
- Agent „Telemetrie streichen" / ChatGPT „Opt-in" → Levins Entscheid ist Opt-out; offen ist nur ein
  First-Run-Hinweis vor dem ersten Ping (Frage an Levin).
- Agent „9 Marks → 3" → nicht umsetzen (Levins 1–9-System), nur Kontrast + deutsche Namen fixen.

---

## Welle 0 — Baseline & Schutz (klein)
- Branch `sprint-fix` ab `main`, Rückfall-Tag `pre-sprint-2026-09-02`.
- `~/Library/Application Support/RAW Select/Sessions` sichern (`Sessions.backup-2026-09-02`).
- Baseline: `swift build`, `--selftest`, `bash build_app.sh` grün dokumentieren. `Releases/` unangetastet.
- Regel für alle Wellen: Build + Selftest grün vor jedem Commit; ein Commit pro Task-Gruppe.

## Welle 1 — Datenverlust & Datenkorrektheit (klein–mittel, ZUERST)
1.1 **⌫ Papierkorb absichern**: Bestätigungsdialog ab >1 Bild (Muster `pendingMoveTarget` existiert),
    Fortschritt/Abbruch über `operation`. (Reject-Workflow mit Review: siehe Welle 5, Frage an Levin.)
1.2 **Tastatur während Copy/Move/Trash sperren**: `operation != nil` in den Guard `AppState.handle` (Z. 868).
1.3 **Karten-Fingerprint**: `?? 0` bei fehlendem `volumeCreationDate` (`FolderIdentity.swift:35`) darf
    nicht zwei Karten zusammenlegen → eindeutiger Fallback (Mount-Pfad) + Statushinweis.
1.4 **Generations-Check für async Completions**: `open()` zählt eine Generation hoch; Scan-Progress/
    -Completion (`isScanning`, `scanFound`, `groups`), Move-/Trash-Completion (`groups.removeAll`,
    `persistState`) und `upgrade()` in LoupeView (`Task.isCancelled`) schreiben nur, wenn die Generation
    noch aktuell ist. Behebt: Spinner des neuen Scans geht aus, falsche Bilder verschwinden nach
    Ordnerwechsel, gesunde Bilder als „nicht lesbar".
1.5 **Kopier-Ziel auf der Quell-Karte** → Warnung/Bestätigung (Volume-Vergleich `targetRoot` vs `rootURL`).
1.6 **persistKey ungruppiert**: bei `groupRawJpg == false` Extension in den Persist-Key aufnehmen
    (`FolderIdentity.persistKey`, `PhotoScanner`), Sidecar-Zuordnung explizit; Selftest-Fall ergänzen.
1.7 **„Aufnahmedatum" ehrlich**: Label → „Dateidatum" (EXIF beim Scan wäre I/O im Hot Path; später
    optional). Sortierung nach Markierung entfällt (Welle 3) → veraltete Mark-Sortierung erledigt sich.
1.8 **Move/Trash-Persistenz**: entfernte Keys explizit aus der Session löschen (Removal-Scope statt
    Waisen); Edits der entfernten Gruppen aufräumen.
1.9 **FileOperationService**: fehlende Quelldatei → `failures` + kein Fortschritts-Schweigen;
    Outcome kennt `cancelled`/`partial`; Finder nur bei vollem Erfolg öffnen.

## Welle 2 — Async-Stabilität & Kern-Tempo (mittel)
2.1 **ThumbnailLoader**: Completion räumt nur auf, wenn `ops[k] === operation` (Waiter-Kappung);
    gecachtes Ergebnis auch bei Cancel zurückgeben; `clearCache()` bricht laufende `ops` ab.
2.2 **markCounts** einmal in `refreshDerived()` cachen (statt 9× O(n) pro Render) — und **sichtbar
    in den Filter-Chips** statt nur Tooltip.
2.3 O(n)-Allokationen pro Tastendruck (`selectRange`, `jumpUnmarked`, `mutateSelection`) auf die
    vorhandene `filteredIndexByID` umstellen.
2.4 **EXIF nur laden, wenn das Overlay an ist** (`LoupeView.swift:126`).
2.5 **Progressiver Scan**: Gruppen in Batches (~200) an den MainActor liefern → erstes Bild < 1 s,
    Sichten während des Scans; „Scan abbrechen" hinterlässt Teilbestand statt „Keine Bilder gefunden".
2.6 **Nachbar-Vordecode im Zoom**: exakt 1 Nachbar in Blickrichtung vorentwickeln, hartes Limit 2–3
    Full-Decodes im RAM (kein Setting).
2.7 **Unmount erkennen**: betrifft `didUnmount` den offenen `rootURL` → laufende Operation abbrechen,
    Meldung, Liste sperren.
2.8 `toggleSelect` setzt `currentID` nicht auf ein abgewähltes Bild; Esc in der Loupe darf den
    Abbrechen-Button des Overlays nicht schlucken.

## Welle 3 — Release-Grenze & toter Code (mittel, Levins Entscheid)
**A) Aus dem Release raus, lokal (DEBUG) behalten — datei-weit `#if DEBUG`:**
`Views/Export/ExportWizard.swift`, `Views/Export/CropEditorView.swift`, `Views/Export/LightroomControls.swift`,
`Views/ImageEditorSheet.swift`, `Services/DevelopEngine.swift`, `Services/XMPPresetBuilder.swift`,
`Services/LightroomExportService.swift`, `Services/LightroomPreviewService.swift`, `Services/BridgeInstaller.swift`.
- `ImageEdit` (in `ExportModels.swift`) bleibt als reines Codable-Modell immer kompiliert → bestehende
  Session-Dateien mit `edit`-Feld bleiben lesbar. Editor-Hooks in `AppState` (`openEditor`, Taste E,
  `saveEditsNow`, `commitEdit`, `hasEdit`), `DetailView`-Editor-Sheet, `ShortcutsSheet`-Zeile „E",
  Lightroom-/Preset-/Temp-Sektionen in `SettingsTabsB` → `#if DEBUG`.
- `RAWSelectApp`: `BridgeInstaller.installIfNeeded()` nur DEBUG. Doppelter ⌘A-Menüeintrag raus.
- `build_app.sh`: kein `.lrplugin` ins Bundle, kein Kopieren nach Application Support,
  `NSAppleEventsUsageDescription` raus. **Verifikation**: Release-Bundle enthält kein `.lrplugin`,
  `strings` des Binaries ohne Lightroom-Pfade, kein Schreibzugriff in Application Support beim Start.
- Settings nur DEBUG: `lightroomPath`, `presetPath`, `deleteTempFiles`, `autoConfirmLightroomDialogs`,
  `jpegQualityPercent`, `colorSpace`, `recentPresets`, `rememberPreset`, `exportSize`, `customLongEdge`,
  `exportConflict`. `lastExportTarget` wird zum Kopier-Ziel-Gedächtnis umgewidmet (Welle 5).
**B) Toter Code — löschen (auch lokal):**
- Unerreichbares Verschieben (`requestMoveSelection`, `confirmMove`, `pendingMoveTarget`, Dialog in
  `ContentView`) — **oder** Button zurück (Frage an Levin).
- Fest verdrahtete/tote Settings + ihre `if`-Hüllen: `wrapNavigation`, `showDateUnderThumb`,
  `preloadPerfect`, `zeroClearsMark`, `advanceDirection`, `showMarkToolbar`, `metadataPanel`,
  `showFilename/TypeBadge/MarkBadge`, `conflictMode`, `recursiveScan/ignoreHidden/cameraFoldersOnly`
  (→ Konstanten). `AppSettings` halbiert sich.
- Sortierung nach Markierung (`.mark`) raus. „Allgemein"-Tab raus, Erscheinungsbild nach „Erweitert".
- Doppelte Settings-Einträge für Thumbnail-Grösse + Sortierung raus (Toolbar/Statusbar bleiben).
- Kopieren: **ein** Button „Auswahl kopieren…" (immer inkl. XMP); `rawJpgExport`/`RawJpgExport`
  und der `rawJpg`-Parameter in `FileOperationService` raus (löst auch die „Nur RAW"-Lüge).
- keyCode-10-Zweig (§ auf ANSI = Backtick) raus, nur Unicode §/°. Tautologischer Guard in
  `CompareView:104` raus. Toasts nur noch für Fehler (Statuszeile für Erfolg).
- Behalten: Zoom-Slider/Kapsel (harmlos), „Öffnen mit App"-Menü (Übergabe an Lightroom = Culling-Ende).

## Welle 4 — Datenschutz, Update, Doku, Repo (klein–mittel)
4.1 **README komplett neu** auf die Culling-App: ehrlich zu Update-Check + Nutzungsstatistik, vollständige
    Shortcut-Tabelle (inkl. ⌫, Tab, C, Z, Space, Esc, ⌘Z, ⌥-Klick), Photoshop/Smart-Exposure/Quellen raus.
4.2 **First-Run-Hinweis** vor dem ersten Ping (ein Satz, Ja vorausgewählt) — Frage an Levin.
4.3 `resetAll()` darf `rs.anonID`/`rs.lastUsagePing` nicht löschen. Kommentare fixen (`githubRepo`,
    `telemetryEndpoint`, `build_app.sh` Modules-Hinweis, `ImageEditorSheet` Toolbar-Button).
4.4 Updater: Download-Datei nicht ungefragt löschen (eindeutiger Name); Hinweis auf Signatur/
    Notarisierung bleibt bekannt/später.
4.5 Repo: `dist/` löschen, `Releases/*.dmg` aus dem Tracking (`git rm --cached` + `.gitignore`), keine
    History-Umschreibung (force-push blockiert, unnötig). STAND.md + Memory aktualisieren.

## Welle 5 — Workflow-UX (mittel)
5.1 **Compare A|B reparieren**: `enterCompare` reduziert Auswahl auf A; ⇧1–9 markiert B; Pan synchron;
    Prefetch statt Spinner; kein altes Bild unter neuem Namen (`image = nil` bei Wechsel); B ≠ A;
    `open()`/`reconcileSelection` validieren `compareRightID`; `exitCompare` zurück in den
    vorherigen Modus; Ansichts-Picker kennt `.compare`.
5.2 Mark-Ziffer schwarz/weiss nach Luminanz; deutsche Mark-Namen.
5.3 `?` auffindbar: Hilfe-Menüeintrag + Zeile im Empty State.
5.4 Letzten Kopier-Zielordner merken (`lastExportTarget` → `chooseDestination.directoryURL`).
5.5 „Markierte kopieren…" im Kopieren-Menü; Filter-Shortcuts (⌥1–9 Solo, ⌥0 alle).
5.6 „Zuletzt geöffnet" (3–5) in der Sidebar.
5.7 Optional (Frage): **Reject-Workflow** — `R` markiert Ausschuss, Filter „nur Ausschuss", am Ende
    gesammelt mit Review in den Papierkorb (ersetzt Sofort-⌫).

## Welle 6 — Später, bewusst nicht jetzt
Verifizierter Ingest (Zähl-/Grössen-/Hash-Prüfung nach dem Kopieren) · Auswahl-Manifest (CSV/JSON) ·
Disk-Thumbnail-Cache · Burst-Gruppierung · XCTest-Target · `AppState`-Aufteilung · Developer-ID +
Notarisierung · Sortierung nach EXIF-Datum · Export-Rückkehr via Wegwerf-Katalog.

## Abschluss
Nach Welle 5: Release-Bundle-Check (siehe Welle 3), Selftest, Sichttest in der App, dann **V1.9**
(Version in `Constants.swift` + `build_app.sh`), Release nur nach Levins Go.
