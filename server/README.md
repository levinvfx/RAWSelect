# RAW Select – Server (Download-Seite + Nutzungszählung)

Läuft auf Levins vServer unter `https://vfxmedia.ch/rawselect/` (nginx liefert den Ordner direkt aus,
der Node-Server des Portfolios ist nicht beteiligt).

## Was hier liegt
| Datei | Ort auf dem Server | Zweck |
|---|---|---|
| `site/index.html` | `/var/www/rawselect/index.html` | Download-Seite: Erststart-Hinweis, Erklär-Animation, Funktionen, Tastatur, Datenverarbeitung |
| `site/datenschutz.html`, `site/impressum.html` | `/var/www/rawselect/` | eigene Seiten, nginx liefert sie unter `/rawselect/datenschutz` und `/rawselect/impressum` |
| `site/static/*` | `/var/www/rawselect/static/` | `site.css` (geteilt), Schriften, Wortmarke, App-Icon, `og.png` (`tools/make_og.py`), `tutorial/` (Animation + Fotos aus öffentlichen Portfolio-Seiten) |
| `download.php` | `/var/www/rawselect/download.php` | `/rawselect/download` → 302 auf das neueste **signierte** DMG; `?info` → JSON für die Seite |
| `ping.php`, `stats.php` | `/var/www/rawselect/` | Nutzungszählung und Auswertung |
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
Jeder Klick zählt eine Zahl pro Tag (Tabelle `downloads`), ohne IP, ohne Cookie – sichtbar in `stats.php`.

## Was gezählt wird (App)
Pro Gerät und Tag eine Zeile: **zufällige Installations-ID** (UUID, kein Hardware-/Personenbezug),
**App-Version**, **grobe macOS-Version** („macOS 26.6"), **Datum**. Sonst nichts.
**Keine IP** – weder in der Datenbank noch im Webserver-Log (`access_log off` für den ganzen Bereich).
Rechtlich ehrlich: Die stabile Kennung ist **pseudonym**, nicht anonym (DSGVO nennt Online-Kennungen
ausdrücklich). Die Zählung ist trotzdem fest eingebaut (Levins Entscheid), gestützt auf berechtigtes Interesse
und abgesichert durch: sichtbare Kennung in der App, Löschanfrage per Mail mit Kennung, Datenschutzerklärung
mit Speicherdauer. **Löschanfrage umsetzen:** Zeilen mit dieser `id` aus `pings` entfernen (Levin bestätigt).
Wer IP-Logging, Pfade oder Namen ergänzt, macht daraus Profilbildung – dann wäre die Pflicht-Zählung nicht
mehr vertretbar und die Datenschutzerklärung falsch.

## Deploy
`bash tools/deploy_site.sh` lädt Seiten und `static/` hoch und prüft alle Pfade live; mit `--nginx` spielt es
vorher das Snippet ein (Backup, `nginx -t`, reload). Nach Änderungen an `site.css`/`tutorial.*` den `?v=`-Parameter
in den HTML-Dateien erhöhen (static/ wird 7 Tage gecacht).

### Regeln
1. **Backups nie in den Webroot** – immer nach `/root/backups/rawselect/<datum>/`. Eine `.bak` im
   Webroot wird als Klartext ausgeliefert (so ist am 02.09.2026 das Stats-Token geleakt). nginx liefert
   heute nur die Allowlist aus, die Regel gilt trotzdem.
2. `stats.php` enthält im Repo nur den Platzhalter `HIER-EIN-GEHEIMES-WORT-SETZEN`. Das echte Token
   liegt lokal in `~/.config/rawselect/stats-token` und wird beim Deploy per Skript eingesetzt
   (nie in der Kommandozeile/im Log); die lokale Kopie danach löschen.
3. Statische Dateien und PHP: `scp` nach `/var/www/rawselect/`, dann `chown www-data:www-data`,
   Ordner 755, Dateien 644, `php -l`.
4. nginx-Snippet: Backup, `scp` nach `/etc/nginx/snippets/rawselect.conf`, `nginx -t`, erst dann
   `systemctl reload nginx`.
5. Nach jedem Deploy prüfen: `/rawselect/` 200, `/rawselect/download?info` JSON, `/rawselect/download`
   302 auf ein `.dmg`, eine fremde Datei unter `/rawselect/` 404, Hauptseite `https://vfxmedia.ch/` 200.

## Ansehen
`https://vfxmedia.ch/rawselect/stats.php?token=<~/.config/rawselect/stats-token>`
