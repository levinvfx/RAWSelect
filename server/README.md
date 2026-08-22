# RAW Select – anonyme Nutzungszählung (Server)

Zwei winzige PHP-Dateien für deinen eigenen Server (z. B. Hoststar). Zeigen dir, **welche
Version auf wie vielen Geräten aktiv** ist – anonym, ohne persönliche Daten.

## Was gezählt wird
Pro Ping nur: eine **zufällige Installations-ID** (kein Hardware-/Personenbezug), die
**App-Version**, die **grobe macOS-Version**, das **Datum**. Ein Eintrag pro Gerät und Tag.
**Keine IP**, keine Dateien, keine Namen, kein Standort. → anonym (CH-DSG / DSGVO unkritisch).

## Einrichten (einmalig, ~5 Min)
1. `ping.php` und `stats.php` in einen Ordner auf deinen Server laden, z. B.
   `https://dein-server.ch/rawselect/`. (Voraussetzung: PHP mit SQLite3 – bei Hoststar Standard.)
2. In **`stats.php`** oben `HIER-EIN-GEHEIMES-WORT-SETZEN` durch ein eigenes Passwort ersetzen.
3. In der App **`Sources/RAWSelect/Utilities/Constants.swift`** `telemetryEndpoint` setzen:
   ```swift
   static let telemetryEndpoint: URL? = URL(string: "https://dein-server.ch/rawselect/ping.php")
   ```
   (Solange das `nil` bleibt, sendet die App nichts.)
4. Neu bauen/releasen. Fertig.

## Ansehen
`https://dein-server.ch/rawselect/stats.php?token=DEIN-WORT` →
Liste „aktive Geräte pro Version (letzte 30 Tage)" + all-time.

## Datenschutz-Hinweis (Best Practice)
- Die App hat einen **Aus-Schalter**: Einstellungen → Erweitert → „Anonyme Nutzungsstatistik senden".
- Nimm einen Satz in deine Download-/Release-Beschreibung auf, z. B.:
  *„RAW Select sendet beim Start anonym eine Zufalls-Kennung und die Version, um die Verbreitung
  zu zählen. Keine persönlichen Daten. Abschaltbar in den Einstellungen."*
- Der Server darf die IP **nicht** loggen. `ping.php` speichert sie nicht; prüfe, dass dein
  Webserver-Log sie nicht dauerhaft aufbewahrt (oder anonymisiert), dann bleibt alles anonym.
