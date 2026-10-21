# RAW Select – Server (Download-Seite + Download-Zähler)

Läuft auf Levins vServer unter `https://vfxmedia.ch/rawselect/` (nginx liefert den Ordner direkt aus,
der Node-Server des Portfolios ist nicht beteiligt).

## Was hier liegt
| Datei | Ort auf dem Server | Zweck |
|---|---|---|
| `site/index.html` | `/var/www/rawselect/index.html` | Download-Seite: Erststart-Hinweis, Erklär-Animation, Funktionen, Tastatur, Datenverarbeitung |
| `site/datenschutz.html`, `site/impressum.html` | `/var/www/rawselect/` | eigene Seiten, nginx liefert sie unter `/rawselect/datenschutz` und `/rawselect/impressum` |
| `site/static/*` | `/var/www/rawselect/static/` | `site.css` (geteilt), Schriften, Wortmarke, App-Icon, `og.png` (`tools/make_og.py`), `tutorial/` (Animation + Fotos aus öffentlichen Portfolio-Seiten) |
| `download.php` | `/var/www/rawselect/download.php` | `/rawselect/download` → 302 auf das neueste **signierte** DMG; `?info` → JSON für die Seite |
| `ping.php` | `/var/www/rawselect/` | Stillgelegt seit 21.10.2026: antwortet 204, liest und speichert nichts (Apps bis 2.0 Beta 1 pingen weiter, bis sie aktualisieren) |
| `nginx-rawselect.conf` | `/etc/nginx/snippets/rawselect.conf` | Allowlist (eingebunden in die vfxmedia-Site) |
| Datenbank + Cache | `/var/lib/rawselect/usage.sqlite`, `latest.json` | ausserhalb des Webroots, Ordner 750 www-data |

Schriften (Inter, OFL) und die Wortmarke liegen **in `site/static/`**, nicht auf der Hauptseite: das
Zugriffsprotokoll der Hauptseite speichert IP-Adressen, das von `/rawselect/` nicht – sonst stimmte die
Datenschutzerklärung nicht. Design-Tokens „Papier und Tinte" stehen inline (Portfolio `DESIGN.md`).

## Download-Weiche
`download.php` fragt GitHub höchstens alle 10 Minuten (`latest.json`), Reihenfolge der Repos:
`levinvfx/RAWSelect-Releases` (öffentliches Download-Repo, nur DMG + .sig), dann `levinvfx/RAWSelect`
(Rückfall, solange öffentlich). Ein Release **ohne** `.sig` wird übergangen – die App würde es auch verwerfen.
Fällt GitHub aus, gilt der letzte bekannte Stand; ohne jeden Stand antwortet die Weiche 503 mit Klartext.
Jeder echte Download (GET, kein Bot) zählt eine Zahl pro Tag (Tabelle `downloads`), ohne IP, ohne Cookie.

## Was gezählt wird
**Nur Downloads** (Levins Entscheid 21.10.2026: «ich will wirklich nichts von den Leuten, nur Downloads»):
- `download.php`: jeder echte Klick auf «Herunterladen» (GET, kein Bot) erhöht die Tageszahl in `downloads`.
- GitHub zählt die Downloads jedes Release-Assets selbst (öffentlich über die API, `download_count`). Darin
  stecken auch die Downloads über die Seite und die Updates, die die App direkt bei GitHub lädt.

Die App (ab 2.0) sendet nichts mehr. `ping.php` nimmt Meldungen alter Versionen an und verwirft sie.
**Altbestand gelöscht (21.10.2026, Levins OK):** Die Tabellen `pings` und `pings_bis_2026_10_15` (Kennung, Version,
macOS, Tag) wurden entfernt (DROP + VACUUM). Backup davor: `/root/backups/rawselect/2026-10-21/usage-vor-loeschung-pings.sqlite`
(nach Kontrolle löschen, sonst stimmt «gelöscht» in der Datenschutzerklärung nur halb). In `usage.sqlite` bleiben
`downloads` (seit 15.10.2026) und `downloads_bis_2026_10_15` (reine Tageszahlen).

## Deploy
`bash tools/deploy_site.sh` lädt Seiten und `static/` hoch und prüft alle Pfade live; mit `--nginx` spielt es
vorher das Snippet ein (Backup, `nginx -t`, reload). Nach Änderungen an `site.css`/`tutorial.*` den `?v=`-Parameter
in den HTML-Dateien erhöhen (static/ wird 7 Tage gecacht).

### Regeln
1. **Backups nie in den Webroot** – immer nach `/root/backups/rawselect/<datum>/`. Eine `.bak` im
   Webroot wird als Klartext ausgeliefert (so ist am 02.09.2026 das Stats-Token geleakt). nginx liefert
   heute nur die Allowlist aus, die Regel gilt trotzdem.
2. Keine öffentliche Auswertung mehr: `stats.php` ist seit 15.10.2026 entfernt (lag unter
   `/root/backups/rawselect/2026-10-15/`). Nichts mit Token in den Webroot legen.
3. Statische Dateien und PHP: `scp` nach `/var/www/rawselect/`, dann `chown www-data:www-data`,
   Ordner 755, Dateien 644, `php -l`.
4. nginx-Snippet: Backup, `scp` nach `/etc/nginx/snippets/rawselect.conf`, `nginx -t`, erst dann
   `systemctl reload nginx`.
5. Nach jedem Deploy prüfen: `/rawselect/` 200, `/rawselect/download?info` JSON, `/rawselect/download`
   302 auf ein `.dmg`, eine fremde Datei unter `/rawselect/` 404, Hauptseite `https://vfxmedia.ch/` 200.

## Ansehen
Im Portfolio-Admin (vfxmedia.ch/admin, Login + 2FA) unter **Analyse → RAW Select** (Inhalt pflegt das
Portfolio-Projekt; seit 21.10.2026 nur noch Downloads). Umgesetzt im Portfolio-Projekt:
`services/rawselectStats.js` liest `/var/lib/rawselect/usage.sqlite` **nur lesend** (Ordner 751, damit der
Portfolio-User `vfx` die 644-Datei lesen kann), Route `GET /api/admin/rawselect` (adminOnly), Anzeige
`js/admin-rawselect.js`. Zeigt Website-Downloads und GitHub-Zahlen.
