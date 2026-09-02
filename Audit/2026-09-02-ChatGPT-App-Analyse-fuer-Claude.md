# RAW Select 1.8.1 – vollständige App-Analyse für Claude Code

Stand der Analyse: 02.09.2026  
Analysierter Commit: `e5cf5cb` (`main`, `origin/main`)  
Analysierte Version: `1.8.1`

## Zweck dieses Dokuments

Dieses Dokument übergibt eine statische, kritische Analyse des aktuellen RAW-Select-Repositories an Claude Code. Es beschreibt den bestehenden Funktionsumfang, konkrete Bugs, unnötige oder widersprüchliche Features, fehlende Workflow-Funktionen und eine empfohlene Reihenfolge für spätere Änderungen.

Die Analyse selbst wurde strikt read-only durchgeführt. Es wurde weder gebaut noch die App gestartet noch der SelfTest ausgeführt, weil diese Aktionen Build-Artefakte, temporäre Dateien und teilweise Papierkorb-Testdaten erzeugen. Die einzige nachträgliche Änderung ist dieses neue Übergabedokument.

## Kurzurteil

RAW Select besitzt einen guten und bereits erstaunlich ausgereiften Culling-Kern:

- schnelles Grid und Loupe,
- flackerarme RAW-Vorschauen,
- gute Tastatursteuerung,
- Farbmarkierungen und Filter,
- Session-Persistenz,
- sichere Copy-Workflows,
- Schutz externer Datenträger,
- Zoom-Halten über Bildwechsel,
- A/B-Vergleich.

Das Hauptproblem ist nicht fehlender Funktionsumfang, sondern eine unscharfe Produktgrenze. Im Repository stecken aktuell zwei Produkte:

1. ein schneller, fokussierter RAW-Culler;
2. ein umfangreicher Lightroom-/Develop-/Crop-Editor mit Export-Bridge.

Der zweite Teil ist im öffentlichen Release größtenteils deaktiviert, bleibt aber teilweise erreichbar, wird teilweise installiert und prägt weiterhin Settings, Modelle und Architektur. Dadurch entstehen tote UI, irreführende Zustände, unnötige Komplexität und zusätzliche Risiken.

Die wichtigste Empfehlung lautet daher: **Nicht sofort weitere Features bauen. Zuerst Datenkorrektheit, Sicherheit, Produktgrenze, Datenschutz und Dokumentation bereinigen.**

---

## 1. Bestehender Funktionsumfang

### Quellen und Scanning

- Erkennung externer, entfernbarer und auswerfbarer Volumes.
- Ordner-Navigation in einer Sidebar.
- Öffnen über Dialog, Sidebar-Doppelklick oder Drag-and-drop.
- Rekursiver Scan unterstützter Formate.
- Bevorzugung typischer Kameraordner wie `DCIM`.
- Unterstützte Formate: ARW, CR2, CR3, NEF, RAF, DNG, JPG, JPEG, HEIC und PNG.
- RAW/JPG-Gruppierung nach Ordner und Basisname.
- Erkennung von `IMG_0001.xmp` und `IMG_0001.ARW.xmp`.
- Scanfortschritt und Abbrechen.

### Anzeige und Navigation

- Adaptives Thumbnail-Grid.
- Große Loupe mit Filmstrip.
- Fokusmodus ohne Filter, Filmstrip und Statusleiste.
- RAW-/JPEG-Vorschau mit mehreren Qualitätsstufen.
- Prefetching und In-Memory-Cache.
- Full-Resolution-Zoom bzw. größtes eingebettetes JPEG als Fallback.
- Zoom mit Tastatur, Slider, Trackpad und klassischem Mausrad.
- Zoom-Ausschnitt kann beim Wechsel durch eine Serie gehalten werden.
- EXIF-Overlay.
- Vollbildmodus.
- Sortierung nach Dateiname, angeblichem Aufnahmedatum oder Markierung.
- Sortierung umkehrbar.
- Einstellbare Thumbnail-Größe.

### Auswahl, Markierung und Filter

- Einzel-, Command- und Shift-Auswahl.
- `Command-A` für alle sichtbaren Bilder.
- Farbmarkierungen 1–9 und Markierung 0.
- Frei editierbare Markierungsnamen und Farben.
- Auto-Advance nach Markierung.
- Undo der letzten Markierungen.
- Filter für unmarkierte Bilder und Markierungen 1–9.
- Option-Klick für einen Solo-Filter.
- Tab/Shift-Tab zum nächsten/vorherigen unmarkierten Bild.
- Home/End.
- Raster-Navigation mit allen Pfeiltasten.

### Vergleich

- A/B-Ansicht.
- Rechtes Bild mit Links/Rechts wechseln.
- B mit Return zu A machen.
- Zoombefehle auf beide Ansichten anwenden.
- Pan aktuell getrennt pro Ansicht.

### Datei- und Übergabe-Workflows

- Auswahl flach in einen Zielordner kopieren.
- Optional mit oder ohne XMP-Sidecars.
- Konflikte durch `_1`, `_2` usw. vermeiden.
- RAW/JPG-Auswahlmodus intern vorhanden.
- Verschieben von internen Quellen implementiert.
- Verschieben von externen Quellen gesperrt.
- Papierkorb-Workflow für interne Quellen.
- Öffnen der Auswahl in einer frei wählbaren externen App.
- Im Finder anzeigen.

### Persistenz

- Markierungen und nichtdestruktive Edits werden unter Application Support gespeichert.
- Identifikation externer Karten bevorzugt per Volume-UUID.
- Fallback-Fingerprint für FAT/exFAT-Medien ohne UUID.
- Scope-Merge verhindert, dass das Speichern eines Ordners Zustände anderer Ordner desselben Volumes löscht.
- Beschädigte Session-Dateien werden nach Möglichkeit quarantänisiert.
- Writes laufen seriell im Hintergrund.
- Beim Beenden wird synchron geflusht.

### Develop-/Lightroom-Infrastruktur

- Nichtdestruktiver Crop, 90-Grad-Rotation und Straighten.
- Belichtung, Kontrast, Highlights, Schatten, Weiß, Schwarz.
- Weißabgleich und HSL-Mixer.
- Lokale CoreImage-Näherung der Entwicklung.
- Lightroom-Preset- und Bridge-Infrastruktur.
- Lightroom-Export-Wizard im Debug-Build.
- Export im öffentlichen Release bewusst deaktiviert, weil die Bridge fremde Lightroom-Kataloge mit Geister-Importen verschmutzt.
- Lightroom muss langfristig die Engine bleiben, weil Photoshop/ACR vorhandene KI-Masken nicht zuverlässig rendert.

### Netzwerk und Distribution

- Automatischer GitHub-Updatecheck beim Start.
- Manueller Updatecheck.
- Download und Öffnen eines Release-DMGs.
- Standardmäßig aktive Nutzungsstatistik mit persistenter zufälliger Installations-ID, App-Version und macOS-Version.
- Ad-hoc-Signierung des Release-Bundles.

---

## 2. Konkrete Bugs und Risiken

### 2.1 KRITISCH – Persistenzkollision bei deaktivierter RAW/JPG-Gruppierung

Relevante Stellen:

- `Sources/RAWSelect/Services/PhotoScanner.swift:57-59`
- `Sources/RAWSelect/Services/PhotoScanner.swift:70-92`
- `Sources/RAWSelect/App/AppState.swift:249-259`
- `Sources/RAWSelect/Utilities/FolderIdentity.swift:48-50`

Wenn `groupRawJpg == false` ist, enthält die Laufzeit-ID die Extension. RAW und JPG werden dadurch korrekt als zwei Gruppen angezeigt. `PhotoGroup.baseName` wird aber weiterhin ohne Extension erzeugt. Der Persistenzschlüssel basiert ausschließlich auf Ordner und `baseName`.

Damit erhalten beispielsweise `IMG_0001.ARW` und `IMG_0001.JPG` denselben `persistKey`.

Folgen:

- getrennt gesetzte Markierungen überschreiben sich beim Speichern;
- beim nächsten Öffnen können beide Dateien dieselbe Markierung bekommen;
- Edits kollidieren ebenfalls;
- innerhalb eines Snapshots entscheidet die Dictionary-Reihenfolge, welcher Zustand übrig bleibt;
- die UI zeigt getrennte Bilder, die Persistenz behandelt sie aber inkonsistent gemeinsam.

Das ist ein echter Datenkorrektheitsfehler. Entweder muss der Persist-Key im ungruppierten Modus die Extension enthalten, oder getrennte Bilder müssen auch live bewusst denselben Zustand teilen. Der aktuelle Mischzustand ist falsch.

Zusätzlich werden normale Sidecars wie `IMG_0001.xmp` im ungruppierten Modus nicht eindeutig einer RAW- oder JPG-Gruppe zugeordnet.

### 2.2 HOCH – Versteckter Editor erzeugt wirkungslosen Zustand im Release

Relevante Stellen:

- `Sources/RAWSelect/Views/ImageEditorSheet.swift`
- `Sources/RAWSelect/Views/Export/CropEditorView.swift`
- `Sources/RAWSelect/App/AppState.swift:637-656`
- `Sources/RAWSelect/App/AppState.swift:913-916`
- `Sources/RAWSelect/Utilities/Constants.swift:8-19`

Der öffentliche Release blendet den Lightroom-JPEG-Export aus. Der Standalone-Editor bleibt über die Taste `E` aber erreichbar. Dort kann der Benutzer Crop-, Rotations- und Develop-Zustände speichern.

Diese Edits wirken im öffentlichen Release nicht auf:

- Grid oder Loupe;
- Originalkopien;
- `Öffnen mit…`;
- Finder;
- irgendeinen sichtbaren Release-Export.

Der tatsächliche Hauptverbraucher ist der deaktivierte Lightroom-Export. Damit kann ein Benutzer lange Bearbeitungen vornehmen, `Fertig` klicken und später feststellen, dass die kopierten oder extern geöffneten Bilder unverändert sind.

Das ist eine funktionale Falle und erheblicher Feature-Creep. Im öffentlichen Release sollte der Editor entweder vollständig deaktiviert sein oder es muss einen realen, sichtbaren und verlässlichen Output geben. Ein versteckter Shortcut reicht nicht als Produktkonzept.

### 2.3 HOCH – Race-Condition beim schnellen Ordnerwechsel

Relevante Stelle:

- `Sources/RAWSelect/App/AppState.swift:209-284`

Beim Öffnen eines neuen Ordners wird der vorherige Scan abgebrochen und ein neuer gestartet. Der alte Task kann anschließend trotzdem den Abbruchpfad erreichen und `self.isScanning = false` setzen. Zu diesem Zeitpunkt kann bereits der neue Scan laufen.

Auch alte `onProgress`-Callbacks können `scanFound` des neuen Scans überschreiben.

Mögliche Folgen:

- der neue Scan wird in der UI vorzeitig als beendet dargestellt;
- anstelle des Scan-Status erscheint kurz `Keine Bilder gefunden`;
- die Dateizahl springt zwischen zwei Scans;
- Zustände verschiedener Scan-Generationen werden vermischt.

Empfehlung: pro `open()` eine Generation/UUID erzeugen. Fortschritt und Abschluss dürfen nur angewendet werden, wenn die Generation noch aktuell ist.

### 2.4 HOCH – „Aufnahmedatum“ ist in Wirklichkeit ein Dateisystemdatum

Relevante Stellen:

- `Sources/RAWSelect/Services/PhotoScanner.swift:76-83`
- `Sources/RAWSelect/Models/AppSettings.swift:5-8`

`PhotoScanner` setzt `fileDate` aus `creationDate` bzw. `contentModificationDate`. Die UI nennt die Sortierung aber `Aufnahmedatum`.

Das ist bei kopierten, synchronisierten oder neu geschriebenen Bildern häufig falsch. EXIF `DateTimeOriginal` wird zwar im MetadataService gelesen, aber nicht für die Sortierung verwendet.

Entweder:

- EXIF-Aufnahmedatum effizient beim Scan lesen und als Capture Date speichern;
- oder die UI ehrlich `Dateidatum` nennen.

### 2.5 HOCH – Sortierung nach Markierung wird nach Änderungen nicht aktualisiert

Relevante Stellen:

- `Sources/RAWSelect/App/AppState.swift:463-518`
- `Sources/RAWSelect/App/AppState.swift:609-624`

Nach `setMark()` bzw. `undoMark()` wird `refreshDerived()` ausgeführt, aber nicht neu sortiert. Wenn `sortField == .mark` aktiv ist, ist die Liste nach der ersten Markierungsänderung nicht mehr korrekt sortiert.

Eine Lösung muss die Auto-Advance- und Ankersemantik berücksichtigen. Blindes Umsortieren vor dem Advance kann den Cursor unerwartet versetzen. Trotzdem darf die UI nicht behaupten, nach Markierung sortiert zu sein, während die Reihenfolge veraltet ist.

### 2.6 HOCH – Race-Condition im Thumbnail-Operation-Registry

Relevante Stellen:

- `Sources/RAWSelect/Services/ThumbnailLoader.swift:41-86`
- `Sources/RAWSelect/Services/ThumbnailLoader.swift:133-164`

Bei `retainPrefetch()` oder Task-Cancellation wird eine Operation abgebrochen und sofort aus `ops` entfernt. Ihre `completionBlock` läuft später trotzdem und entfernt unconditionally:

- `waiters[k]`;
- `ops[k]`;
- `prefetchWanted[k]`.

Wenn zwischen Abbruch und Completion bereits eine neue Operation für denselben Key gestartet wurde, kann die alte Completion den Zustand der neuen Operation zerstören und deren Waiter mit `nil` fortsetzen.

Mögliche Symptome:

- sporadisch leere Thumbnails;
- sichtbare Requests erhalten `nil`, obwohl ein neuer Decode läuft;
- scharfe Preview-Stufe erscheint nicht;
- Registry und echte Queue laufen auseinander.

Empfehlung: jede Operation benötigt eine eindeutige Generation/Identität. Completion darf Registry-Einträge nur entfernen, wenn dort noch genau dieselbe Operation eingetragen ist.

### 2.7 MITTEL – Compare kann dasselbe Bild links und rechts zeigen

Relevante Stelle:

- `Sources/RAWSelect/App/AppState.swift:355-406`

`compareCycleRight()` clamp’t nur den Index. Es überspringt `currentID` nicht. Wenn B neben A steht, führt ein Schritt in Richtung A dazu, dass beide Panes dasselbe Bild zeigen.

Die Vergleichsnavigation sollte:

- A immer überspringen;
- am Rand eine klare Rückmeldung geben oder sinnvoll wrappen;
- bei Filter-/Markierungsänderungen B neu validieren.

### 2.8 MITTEL – Copy/Move meldet fehlende Quelldateien nicht

Relevante Stelle:

- `Sources/RAWSelect/Services/FileOperationService.swift:73-106`

Wenn eine Quelldatei nicht mehr existiert, wird sie still übersprungen. Es wird kein Fehler zu `failures` hinzugefügt und der Fortschritt wird nicht erhöht.

Damit kann die UI einen erfolgreichen Export melden, obwohl Dateien fehlen. Das kann beispielsweise nach Auswurf, externer Löschung, Netzlaufwerksfehlern oder einem teilweise verschobenen Set passieren.

Abbrechen wird ebenfalls nicht als eigener Outcome-Zustand modelliert. Ein abgebrochener Vorgang erscheint wie ein normaler Teilerfolg und kann anschließend trotzdem den Finder öffnen.

Outcome sollte mindestens zwischen `completed`, `cancelled`, `partial` und `failed` unterscheiden.

### 2.9 MITTEL – „Nur RAW“ und „Nur JPG“ halten ihr Versprechen nicht

Relevante Stelle:

- `Sources/RAWSelect/Services/FileOperationService.swift:35-45`

Wenn im Modus `rawOnly` kein RAW existiert, wird auf alle Dateien zurückgefallen. `jpgOnly` macht dasselbe bei fehlendem JPG.

Damit kann `Nur RAW` beispielsweise HEIC oder JPG kopieren und `Nur JPG` ein RAW. Das verhindert leere Ergebnisse, widerspricht aber klar dem Label.

Besser:

- betreffende Gruppe überspringen und sichtbar melden;
- oder UI als `RAW bevorzugen` bzw. `JPG bevorzugen` benennen.

### 2.10 MITTEL – Filteränderungen zerstören Teile der Auswahl

Relevante Stellen:

- `Sources/RAWSelect/App/AppState.swift:20`
- `Sources/RAWSelect/App/AppState.swift:454-460`

Bei jeder Filteränderung wird `selectedIDs` mit den sichtbaren IDs geschnitten. Ausgeblendete Bilder sind danach dauerhaft nicht mehr ausgewählt, selbst wenn der Filter wieder zurückgesetzt wird.

Das ist bei einem sichtbarkeitsorientierten Filter nicht zwingend erwartbar und kann den Umfang eines späteren Copy-Vorgangs unbemerkt reduzieren.

Es braucht eine klare Produktentscheidung:

- Auswahl ist immer nur die sichtbare Menge; dann muss die UI das deutlich kommunizieren.
- Oder Auswahl bleibt filterübergreifend bestehen; dann muss der Status `N ausgewählt, davon M sichtbar` anzeigen.

### 2.11 MITTEL – Sofortiger Papierkorb ohne Review oder Bestätigung

Relevante Stellen:

- `Sources/RAWSelect/App/AppState.swift:731-768`
- `Sources/RAWSelect/App/AppState.swift:882`

Backspace verschiebt die gesamte Auswahl auf internen Laufwerken sofort in den Papierkorb. Der Vorgang ist zwar über den macOS-Papierkorb wiederherstellbar, aber:

- es gibt keine Bestätigung;
- keinen eigenen Reject-Zustand;
- keine Review-Ansicht;
- kein App-internes Undo;
- keine sichtbare Toolbar-Aktion;
- Multi-Selection kann sehr viele Bilder betreffen.

Für einen Culling-Workflow wäre `Reject markieren -> Rejects prüfen -> gesammelt in Papierkorb` sicherer und professioneller.

### 2.12 MITTEL – Verwaiste Session-Zustände nach Move/Trash

Nach erfolgreichem Move oder Trash werden Gruppen zuerst aus `groups` entfernt und danach wird persistiert. `sessionSnapshot()` enthält als Scope nur noch verbleibende Gruppen. Alte Zustände der entfernten Gruppen werden dadurch nicht aus der Session-Datei gelöscht.

Folgen:

- Session-Dateien wachsen mit verwaisten Einträgen;
- später neu auftauchende Dateien mit demselben Pfad/Basisnamen können alte Markierungen erben;
- ein wiederhergestelltes Papierkorb-Bild erhält möglicherweise unerwartet alten Zustand.

Move/Trash benötigen einen expliziten Persistenz-Scope für entfernte Keys.

### 2.13 MITTEL – Teilweise verschobene Gruppen bleiben inkonsistent in der UI

Wenn einige Dateien einer RAW/JPG/XMP-Gruppe erfolgreich verschoben werden und andere scheitern, bleibt die Gruppe in der UI, obwohl Teile ihrer `files` nicht mehr existieren. Preview, weitere Operationen und Größenanzeige arbeiten dann mit veraltetem Zustand.

Nach partiellen Dateioperationen sollte entweder neu gescannt oder das Gruppenmodell anhand der tatsächlich verbleibenden Dateien aktualisiert werden.

### 2.14 MITTEL – Release installiert eine deaktivierte Lightroom-Bridge

Relevante Stellen:

- `Sources/RAWSelect/App/RAWSelectApp.swift:75-84`
- `Sources/RAWSelect/Services/BridgeInstaller.swift`
- `Sources/RAWSelect/Utilities/Constants.swift:8-19`
- `build_app.sh:60-66`

Der öffentliche Release blendet den Lightroom-Export wegen Katalogverschmutzung aus. Trotzdem wird das Plugin gebündelt und beim App-Start nach Application Support kopiert.

Das ist unnötige externe Zustandsänderung und widerspricht der tatsächlichen Feature-Verfügbarkeit. Bridge-Installation, Lightroom-Settings und Plugin-Bundling sollten denselben Release-Guard besitzen wie der Export.

### 2.15 MITTEL – Advanced Settings enthalten tote Lightroom-Infrastruktur

`SettingsView` blendet nur den Export-Tab aus. Der Advanced-Tab bleibt sichtbar und enthält weiterhin:

- Lightroom-Pfad;
- Standard-Preset;
- temporäre Exportdateien;
- Bridge-Erklärung;
- teilweise nur für Debug-Export relevante Optionen.

Im öffentlichen Release sind diese Optionen weitgehend wirkungslos und verwirren.

### 2.16 MITTEL – Privacy-Opt-out erfolgt erst nach dem ersten Ping

Relevante Stellen:

- `Sources/RAWSelect/App/RAWSelectApp.swift:75-84`
- `Sources/RAWSelect/Services/TelemetryService.swift`
- `Sources/RAWSelect/Models/AppSettings.swift:121-124`
- `Sources/RAWSelect/Utilities/Constants.swift:35-39`

`sendUsageStats` ist standardmäßig `true`. Der Ping wird direkt beim Start ausgelöst. Ein neuer Benutzer kann die Einstellung erst nach diesem ersten Ping deaktivieren.

Die gesendete UUID ist zufällig, aber persistent und über Tage wiedererkennbar. Das ist besser als eine Hardware-ID, sollte aber nicht pauschal als vollständig anonym bezeichnet werden. Zudem können IP-Adressen in Webserver-, Proxy- oder Hosting-Logs auftauchen, obwohl `ping.php` sie nicht in SQLite speichert.

Empfehlung:

- First-run-Einwilligung vor dem ersten Ping;
- bevorzugt Opt-in;
- genaue Benennung als pseudonyme Nutzungsstatistik;
- Zweck, Endpoint, Datenumfang, Aufbewahrung und Verantwortlichen offenlegen;
- automatische Requests vollständig abschaltbar machen.

### 2.17 MITTEL – Updateprozess besitzt keine belastbare Authentizitätsprüfung

Relevante Stellen:

- `Sources/RAWSelect/Services/UpdateService.swift:26-70`
- `build_app.sh:91-92`

Der Updater verwendet das erste `.dmg`-Asset des neuesten GitHub-Releases, lädt es herunter und öffnet es. Es gibt keine Prüfung von:

- Developer-ID-Signatur;
- Notarisierung;
- signiertem Appcast;
- publiziertem SHA-256;
- fest erwarteter Download-Domain jenseits der API-Antwort.

Zusätzlich wird eine gleichnamige Datei in Downloads vorher ungefragt entfernt.

Die App installiert nicht automatisch, aber sie fordert den Benutzer anschließend auf, die bestehende App zu ersetzen. Für eine öffentliche Distribution ist die Vertrauenskette zu schwach.

### 2.18 NIEDRIG – Unlesbare Markierungsnummern

Relevante Stellen:

- `Sources/RAWSelect/Views/ThumbnailCell.swift:98-108`
- `Sources/RAWSelect/Views/FilterBar.swift:53-79`

Die Ziffer wird immer weiß dargestellt. Auf der weißen Markierung 9 ist sie fast unsichtbar, auf Gelb ebenfalls kontrastarm. Die Textfarbe muss anhand der Hintergrundluminanz zwischen Schwarz und Weiß wechseln.

### 2.19 NIEDRIG – Aggressiver globaler Tastaturmonitor

Relevante Stelle:

- `Sources/RAWSelect/App/AppState.swift:831-931`

Der lokale Key-Monitor schützt Textfelder und Modals, übernimmt aber sonst Pfeiltasten und Tab global im Hauptfenster. Dadurch kann native Tastaturbedienung von Sidebar, Toolbar und Fokusnavigation beeinträchtigt werden.

### 2.20 NIEDRIG – Einstellungen wirken nicht durchgehend live

`settingsChanged()` reagiert aktuell nur auf Sortiersignatur und maximale Parallelität.

Probleme:

- RAW/JPG-Gruppierung erfordert einen Rescan, ohne dass UI oder App dies klar sagen.
- Preview-Mode lädt das aktuelle Bild nicht zwingend in der neuen Stufe neu.
- Sortieränderung kann die aktuelle Grid-Zelle aus dem sichtbaren Bereich bewegen, weil `currentID` gleich bleibt und damit kein Scroll-Trigger feuert.

### 2.21 NIEDRIG – Tote oder unerreichbare Funktionen

- `requestMoveSelection()` ist von keiner sichtbaren Aktion erreichbar.
- `hasEdit()` wird außerhalb von AppState nicht verwendet; Edits besitzen damit auch keinen sichtbaren Badge.
- Einige feste Settings (`wrapNavigation`, `zeroClearsMark`, `advanceDirection`, `metadataPanel`) wirken wie konfigurierbare Abstraktionen, sind aber nicht konfigurierbar.
- `AppState` ist weiterhin ein God-Object mit Scanning, Auswahl, Navigation, Persistenz, Dateioperationen, Compare und Key-Routing.
- `CropEditorView` ist mit rund 900 Zeilen ein God-View.

---

## 3. Datenschutz- und Dokumentationswidersprüche

### README widerspricht dem aktuellen Produkt

Die Haupt-README ist stark veraltet und muss praktisch neu geschrieben werden.

Sie behauptet unter anderem:

- „komplett offline“;
- „Keine Cloud, kein Server, kein Login, kein Netz“;
- „Keinerlei Netzwerk-, Server-, FTP-, Cloud- oder Login-Funktionen“;
- Photoshop-/Camera-Raw-Export;
- Smart Exposure;
- vorbereitete Photoshop-Einstellungen;
- kein App-Icon;
- einen anderen Settings-Aufbau.

Der aktuelle Stand besitzt dagegen:

- automatischen GitHub-Updatecheck;
- standardmäßig aktive Telemetrie an `vfxmedia.ch`;
- ein App-Icon;
- Lightroom statt Photoshop als Exportengine;
- manuelle Develop-Regler statt des beschriebenen Smart-Exposure-Flows;
- Compare, Reject, Home/End, Tab-Navigation und weitere nicht sauber dokumentierte Funktionen.

Diese Abweichungen sind nicht nur kosmetisch. Besonders das falsche Offline-Versprechen beschädigt Vertrauen.

### Weitere Dokumentationsdrift

- `STAND.md` bezeichnet den Telemetrie-Endpunkt an einer Stelle noch als `nil`, obwohl er aktiv konfiguriert ist.
- Kommentare im Buildscript behaupten teilweise weiterhin, die Bridge werde in Lightrooms Modules-Ordner kopiert; der aktuelle Installer nutzt einen stabilen Application-Support-Pfad.
- `ImageEditorSheet` spricht von einem Toolbar-Button, tatsächlich ist der Editor nur über `E` erreichbar.
- Release Notes 1.8 informieren über Telemetrie, aber erst nach der Installation; das löst das Problem des ersten Opt-out-Pings nicht.

---

## 4. Bewertung der bestehenden Features

### Unbedingt behalten

Diese Funktionen bilden den eigentlichen Produktwert und sollten nicht durch große Refactorings destabilisiert werden:

- schneller Scan und lazy Thumbnails;
- Embedded-JPEG-Strategie für RAWs;
- Loupe und Filmstrip;
- Zoom, 100-Prozent-Ansicht und Zoom-Halten über Serien;
- Tastaturmarkierung und Auto-Advance;
- Mehrfachauswahl;
- Tab zum nächsten unmarkierten Bild;
- RAW/JPG-Gruppierung als Standard;
- XMP-Erkennung und optionale Mitnahme;
- Session-Persistenz außerhalb der Quelle;
- Schutz externer Volumes vor Move/Trash;
- konfliktfreies Kopieren;
- EXIF-Anzeige;
- Compare als Grundkonzept;
- sichtbare Fehler-Toasts bei Session-Speicherfehlern;
- synchroner Flush beim Beenden.

### Entfernen oder im Release vollständig ausblenden

1. **Standalone-Develop-Editor**, solange Edits im Release keinen realen Output besitzen.
2. **Lightroom-Bridge-Installation und Bundling** im öffentlichen Release, solange Export deaktiviert ist.
3. **Lightroom-/Preset-/Temp-Einstellungen** im Advanced-Tab des öffentlichen Releases.
4. **Unerreichbare Move-Funktion**, falls sie nicht bewusst als sichtbarer Workflow unterstützt werden soll.
5. **„Alle Filter ausblenden“**: Eine absichtlich vollständig leere Ansicht besitzt keinen sinnvollen Workflowwert. Der globale Filterbutton sollte eher `Alle anzeigen/Filter zurücksetzen` sein.
6. **Doppelte Einstellpfade** für Sortierung und Thumbnail-Größe. Beide sind bereits kontextuell im Hauptfenster verfügbar.
7. **Eigener Allgemein-Tab nur für Appearance** ist für eine kleine App unnötig. Systemdarstellung als Standard reicht meist; alternativ Appearance in Advanced verschieben.

### Kritisch hinterfragen

#### Neun frei editierbare Farben und Namen

Für einen einzelnen Power-User kann das sinnvoll sein. Für ein klares öffentliches Produkt sind neun frei definierbare Kategorien schwer verständlich. Drei semantische Zustände wären einfacher:

- Ausschuss;
- Auswahl;
- Highlight/Portfolio.

Falls 1–9 bleiben, sollten bessere Standardnamen, adaptive Kontraste und klar sichtbare Zähler verwendet werden. Die aktuellen englischen Defaults `Red`, `Yellow`, `Green` usw. passen nicht zur deutschen UI.

#### Sofortiger Papierkorb

Der aktuelle Shortcut ist schnell, aber für eine Culling-App zu aggressiv. Ein Reject-State mit abschließender Review ist sicherer.

#### Vollständiger In-App-Develop-Stack

Der Develop-Stack besteht aus sehr viel Code und muss gegen Lightroom angenähert werden, obwohl Lightroom später ohnehin final rendert. Für das Kernprodukt ist das ein schlechtes Verhältnis aus Komplexität, Testaufwand und Nutzen.

---

## 5. Sinnvolle neue Features nach Bereinigung

### Priorität 1 – Sicherer Reject-Workflow

Vorschlag:

- `R` markiert/entmarkiert Ausschuss, ohne Dateien sofort anzufassen.
- Direkter Filter `Nur Ausschuss`.
- Abschlussaktion `N Ausschussbilder prüfen`.
- Danach gesammelt in den macOS-Papierkorb.
- Deutliche Bestätigung bei Multi-Selection.
- Optional App-internes Undo bis zum finalen Trash.

Das ist für echte Culling-Sessions wertvoller als weitere Develop-Regler.

### Priorität 2 – Verifizierter Ingest

Nach dem Kopieren sollte RAW Select optional prüfen:

- erwartete gegen tatsächliche Dateianzahl;
- Dateigrößen;
- optional SHA-256 oder eine schnellere robuste Prüfsumme;
- vollständige RAW/JPG/XMP-Gruppen;
- verständlicher Abschlussbericht.

Eine SD-Karten-App sollte nicht nur „copyItem war erfolgreich“ melden, sondern verlässlich beantworten können: **Ist mein Shooting vollständig und sicher am Ziel angekommen?**

### Priorität 3 – Letzte Ordner und Session-Wiederaufnahme

Sessions werden bereits gespeichert, aber der Einstieg ist jedes Mal manuell.

Sinnvoll wären:

- zuletzt verwendete Ordner/Karten;
- `Letzte Session fortsetzen`;
- Anzeige `N Bilder, M markiert, zuletzt geöffnet …`;
- klare Behandlung nicht mehr gemounteter Quellen.

### Priorität 4 – Direkte Filter-Shortcuts

Beispiele:

- nur unmarkierte Bilder;
- nur markierte Bilder;
- nur eine konkrete Markierung;
- alle Filter zurücksetzen;
- ausgewählte Markierung ein-/ausblenden.

Tab hilft beim sequenziellen Springen, ersetzt aber keinen visuellen zweiten Durchgang.

### Priorität 5 – Compare fertigstellen

- B darf nie A sein.
- Optional synchroner Pan zusätzlich zum synchronen Zoom.
- B direkt markieren oder ablehnen.
- `B als Sieger` klarer benennen und visualisieren.
- Optional 2–4 Bilder für Burst-Auswahl.
- Bei Filteränderungen beide Panes validieren.
- Optional Dateiname, Schärfeindikator und EXIF-Differenzen kompakt anzeigen.

### Priorität 6 – Auswahl-/Markierungsmanifest

Ein kleiner TXT-/CSV-/JSON-Export mit Dateinamen und Markierungen wäre für externe Workflows sehr praktisch, ohne Originale zu verändern.

Optional:

- XMP nur im Zielordner erzeugen;
- Lightroom-kompatible Farblabel nur für Kopien schreiben;
- keine Sidecars neben den Originalen verändern.

### Priorität 7 – Disk-Thumbnail-Cache

Der aktuelle Browsercache ist überwiegend RAM-basiert. Wiederholtes Öffnen großer Shootings dekodiert erneut.

Ein optionaler Disk-Cache sollte:

- anhand Pfad, Dateigröße und Modification Date invalidieren;
- ein klares Größenlimit besitzen;
- unter Application Support/Caches liegen;
- über `Cache leeren` vollständig kontrollierbar sein.

### Später sinnvoll

- zeitbasierte Burst-Gruppierung;
- Fokus-Peaking bzw. einfacher Schärfeindikator;
- Histogramm und Clipping-Warnung in der Loupe;
- schnelles Ziel `letzter Exportordner`;
- optional zwei verifizierte Ingest-Ziele für Arbeitskopie und Backup.

### Bewusst nicht hinzufügen

- Cloud-Sync;
- Login/Account;
- DAM/Katalogverwaltung;
- automatische AI-Bewertung;
- Sterne zusätzlich zu den bestehenden Farben;
- weitere Export-Engines;
- mehr Settings;
- Lightroom-Parität in der lokalen Preview;
- Social-/Sharing-Funktionen.

---

## 6. Architektur- und Testfeedback

### AppState ist weiterhin zu groß

`AppState` verantwortet:

- Lifecycle;
- Volume-Watching;
- Scan-Orchestrierung;
- Auswahl;
- Navigation;
- Filter;
- Compare;
- Prefetch;
- Markierungen und Undo;
- Session-Persistenz;
- Editorzustand;
- externe Apps;
- Copy/Move/Trash;
- globales Key-Routing.

Das erschwert gezielte Tests und macht Zustandsraces wahrscheinlicher.

Sinnvolle spätere Extraktionen:

- `ScanCoordinator` mit Generationen;
- `SelectionController`;
- `KeyCommandRouter`;
- `FileOperationCoordinator`;
- `CompareController`;
- Session-Persistenzqueue mit expliziten Snapshots/Generationen.

Nicht alles auf einmal refactoren. Erst konkrete Bugs absichern, dann Verantwortlichkeiten extrahieren.

### CropEditorView ist ein God-View

Die View kombiniert:

- Crop-Geometrie;
- Gesten und Hit-Testing;
- Rotation und Straighten;
- Develop-Controls;
- HSL;
- Lightroom-Preset-Preview;
- Exact-Render-Tasks;
- CoreImage-Render-Pump;
- Zoom.

Falls der Editor langfristig bleibt, sollten mindestens getrennt werden:

- `CropGeometryModel`;
- `DevelopControlsView`;
- `PreviewRenderCoordinator`;
- Lightroom-Preset-Adapter.

Falls der öffentliche Editor entfällt, keinen riskanten Großrefactor nur aus ästhetischen Gründen durchführen.

### Testabdeckung

Der vorhandene SelfTest deckt erfreulich viel Service-Logik ab:

- Scanning und RAW/JPG-Pairing;
- XMP;
- Session Scope Merge;
- Copy und Konflikte;
- XMP-Building;
- DevelopEngine-Richtung;
- Update-Versionsvergleich;
- Session-Quarantäne;
- JPEG-Parser;
- Trash;
- einfachen Thumbnail-Cache-Hit.

Wichtige Lücken:

- kein XCTest-Target;
- AppState-Navigation nicht getestet;
- Scan-Generation/Ordnerwechsel nicht getestet;
- Mark-Sortierung nicht getestet;
- RAW/JPG-Persist-Key im ungruppierten Modus nicht getestet;
- Compare-Navigation nicht getestet;
- Thumbnail-Cancel/Restart-Race nicht getestet;
- Filter-/Selection-Semantik nicht getestet;
- Copy mit währenddessen verschwundener Datei nicht getestet;
- Cancelled/Partial Outcomes nicht getestet;
- App-Lifecycle und Termination-Flush nur indirekt;
- keine UI-/Accessibility-Tests;
- keine echten Performance-Baselines für 1.000–3.000 RAWs.

Empfehlung: kleines XCTest-Target einführen und zuerst deterministische Modell-/Service-Tests hinzufügen. GUI-Tests sind später.

---

## 7. Empfohlene Umsetzungsreihenfolge

### Welle 0 – Baseline und Schutz

Vor Änderungen:

- sauberen Git-Status prüfen;
- neuen Branch verwenden;
- Release-DMGs unter `Releases/` niemals verändern;
- existierende Session-Dateien sichern;
- Debug-Build, SelfTest und Release-Build als Baseline dokumentieren;
- keine Änderungen am handkalibrierten DevelopEngine ohne eigene visuelle Regressionstests.

### Welle 1 – Datenkorrektheit

1. RAW/JPG-Persist-Key im ungruppierten Modus korrigieren.
2. Regressionstest für getrennte Markierungen/Edits ergänzen.
3. Scan-Generation gegen alte Progress-/Completion-Callbacks einführen.
4. Mark-Sortierung nach Änderungen korrekt halten.
5. EXIF-Aufnahmedatum oder ehrliche Umbenennung zu Dateidatum.
6. Move/Trash-Persistenzscope für entfernte Gruppen korrigieren.

### Welle 2 – Async- und Dateioperationen

1. Thumbnail-Operationen mit eindeutiger Identität absichern.
2. Cancel/Restart-Race testen.
3. Fehlende Quelldateien als Fehler melden.
4. Outcome um Cancelled/Partial ergänzen.
5. Nach partiellen Moves Gruppen neu aufbauen oder rescanen.
6. `rawOnly`/`jpgOnly`-Semantik korrigieren.

### Welle 3 – Release entschlacken

1. Standalone-Editor im Release vollständig ausblenden oder entfernen.
2. Lightroom-Bridge im Release nicht installieren/bündeln.
3. Lightroom-/Preset-Settings im Release vollständig ausblenden.
4. Tote Move-Funktion entweder sichtbar fertigstellen oder entfernen.
5. Doppelte Settings reduzieren.

Wichtig: Die Debug-/Entwicklungsinfrastruktur kann isoliert erhalten bleiben, weil Lightroom für den späteren korrekten Maskenexport weiterhin die vorgesehene Engine ist. Nicht erneut auf Photoshop/ACR oder darktable wechseln.

### Welle 4 – Datenschutz, Update und Dokumentation

1. Telemetrie vor dem ersten Ping zustimmungspflichtig machen oder auf Opt-in umstellen.
2. Automatischen Updatecheck separat abschaltbar machen oder nur manuell ausführen.
3. README vollständig auf den aktuellen Funktionsumfang umschreiben.
4. Offline-Versprechen entfernen oder Netzwerkzugriffe entfernen.
5. Datenschutzhinweis präzisieren.
6. Update-DMG per Signatur/Notarisierung/Hash absichern.
7. Downloads nicht ungefragt überschreiben.
8. Kommentare in Buildscript, STAND und Editor korrigieren.

### Welle 5 – Workflow-UX

1. Compare darf A nicht als B zeigen.
2. Filter-/Selection-Semantik bewusst entscheiden und sichtbar machen.
3. Reject-Queue mit Review statt Sofort-Trash.
4. Direkte Filter-Shortcuts.
5. Markierungs-Kontrast und deutsche Defaults.
6. Recents bzw. Session-Wiederaufnahme.

### Welle 6 – Neue produktive Features

1. Verifizierter Ingest.
2. Auswahlmanifest.
3. Disk-Thumbnail-Cache.
4. Verbesserter Compare mit synchronem Pan.
5. Erst danach Burst-Gruppierung, Fokus-Peaking oder Histogramm.

---

## 8. Acceptance Criteria für spätere Änderungen

### Allgemein

- `swift build` erfolgreich.
- Debug-SelfTest erfolgreich.
- `swift build -c release` erfolgreich.
- Keine unbeabsichtigten Änderungen in `Releases/`.
- Versionsnummern nur bei echtem Release und dann synchron in `Constants.swift` und `build_app.sh`.
- Keine Originaldatei auf externen Volumes wird verändert.

### RAW/JPG ungruppiert

- RAW und JPG besitzen unterschiedliche Laufzeit- und Persistenzkeys.
- Beide lassen sich unabhängig markieren und bearbeiten.
- Neustart lädt beide Zustände korrekt.
- XMP-Zuordnung ist explizit und getestet.

### Scanning

- Schnelles Öffnen A -> B kann nie Status/Fortschritt von A in B schreiben.
- Abbruch von A beendet nicht den Spinner von B.
- Nur der aktuelle Scan darf `groups`, `isScanning`, `scanFound` und `statusMessage` finalisieren.

### ThumbnailLoader

- Eine Completion darf nur ihre eigene Operation aus der Registry entfernen.
- Ein alter Cancel darf keinen neuen Waiter fortsetzen oder löschen.
- Wiederholtes schnelles Scrubben erzeugt keine dauerhaft leeren Zellen.
- Sichtbare Requests werden nie von Prefetch-Cancellation abgebrochen.

### Dateioperationen

- Jede erwartete, aber fehlende Quelldatei erscheint im Fehlerbericht.
- Abbruch wird als Abbruch angezeigt.
- Partielle Erfolge werden nicht als vollständiger Erfolg bezeichnet.
- Finder öffnet sich bei Abbruch/Fehler nicht automatisch ohne klare Entscheidung.
- RAW-only kopiert ausschließlich RAW oder meldet Gruppen ohne RAW.
- JPG-only kopiert ausschließlich JPG/JPEG oder meldet Gruppen ohne JPG.

### Release-Grenze

- Kein sichtbarer oder versteckter Editor, wenn Edits keinen Release-Output besitzen.
- Keine Lightroom-Bridge-Installation, wenn Export deaktiviert ist.
- Keine wirkungslosen Lightroom-Settings im Release.
- Debug-Export bleibt für Entwicklung isoliert verfügbar.

### Datenschutz

- Vor einer Einwilligung wird keine Telemetrie gesendet.
- Ausschalten verhindert jeden weiteren Ping.
- Dokumentation nennt alle automatischen Netzwerkzugriffe ehrlich.
- Persistent UUID wird nicht als vollständig anonym überverkauft.

---

## 9. Besonders gute Teile, die nicht unnötig angefasst werden sollten

- Embedded-JPEG- und RAW-Fallback-Strategie.
- `ZoomableImageView` und Zoom-Halten über Bildwechsel.
- Session-Scope-Merge.
- Quarantäne beschädigter Sessions.
- serieller Write-Chain plus Termination-Flush.
- Konfliktumbenennung für Copy.
- Schutz externer Volumes.
- Fehler-Toasts bei Session-Speicherfehlern.
- vorhandene XMP-WB-/Clamp-Logik.
- handkalibrierte DevelopEngine-Konstanten, solange keine visuelle Testbasis existiert.
- UUID pro Lightroom-Bridge-Job.

---

## 10. Schlussfolgerung für Claude Code

RAW Select braucht momentan keine breite Feature-Offensive. Die App sollte als schneller, sicherer, lokaler Culler geschärft werden.

Die richtige Priorität ist:

1. Datenkorrektheit;
2. Async-Stabilität;
3. ehrliche Release-Grenze;
4. Datenschutz und Update-Vertrauen;
5. sicherer Reject-/Compare-Workflow;
6. erst danach neue produktive Features.

Besonders wichtig: Den deaktivierten Lightroom-Export nicht durch Photoshop oder eine andere Engine ersetzen. Wenn der Export später zurückkehrt, muss Lightroom wegen der KI-Masken die Engine bleiben und die Katalogverschmutzung über einen isolierten Wegwerf-Katalog gelöst werden.

Vor einer Implementierung sollte Claude Code die genannten Stellen im aktuellen Commit erneut prüfen, Befunde gegen inzwischen erfolgte Änderungen abgleichen und anschließend in kleinen, testbaren Wellen vorgehen. Keine große Komplettumschreibung von AppState oder CropEditorView ohne vorherige Regressionstests.
