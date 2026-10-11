# RAW Select – anonyme Nutzungszählung (Server)

Zeigt, **wie viele Geräte welche Version** nutzen – anonym, ohne persönliche Daten.
Läuft auf Levins vServer unter `https://vfxmedia.ch/rawselect/`.

## Was gezählt wird
Pro Gerät und Tag eine Zeile: **zufällige Installations-ID** (UUID, kein Hardware-/Personenbezug),
**App-Version**, **grobe macOS-Version** („macOS 26.6“), **Datum**. Sonst nichts.
**Keine IP** – weder in der Datenbank noch im Webserver-Log (`access_log off`). Nur deshalb ist die
Zählung anonym und darf in der App fest eingebaut sein. Wer IP-Logging, Pfade oder Namen ergänzt,
macht daraus eine Erhebung von Personendaten – dann wäre die Pflicht-Zählung nicht mehr zulässig.

## Dateien
| Datei | Ort auf dem Server |
|---|---|
| `ping.php`, `stats.php` | `/var/www/rawselect/` |
| `nginx-rawselect.conf` | `/etc/nginx/snippets/rawselect.conf` (eingebunden in die vfxmedia-Site) |
| Datenbank | `/var/lib/rawselect/usage.sqlite` (ausserhalb des Webroots, Ordner 750 www-data) |

nginx liefert unter `/rawselect/` **nur** `ping.php` und `stats.php` aus; alles andere ergibt 404.

## Deploy (Regeln)
1. **Backups nie in den Webroot** – immer nach `/root/backups/rawselect/<datum>/`. Eine `.bak` im
   Webroot wird als Klartext ausgeliefert (so ist am 02.09.2026 das Stats-Token geleakt).
2. `stats.php` enthält im Repo nur den Platzhalter `HIER-EIN-GEHEIMES-WORT-SETZEN`. Das echte Token
   liegt lokal in `~/.config/rawselect/stats-token` und wird beim Deploy per `sed` über stdin
   eingesetzt (nie in der Kommandozeile/im Log).
3. Nach jedem Deploy: `php -l`, `nginx -t`, Aufruf mit/ohne Token, und eine fremde Datei unter
   `/rawselect/` muss 404 liefern.

## Ansehen
`https://vfxmedia.ch/rawselect/stats.php?token=<~/.config/rawselect/stats-token>`
