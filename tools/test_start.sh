#!/bin/bash
# Testet den Installations-Zähler server/start.php mit dem eingebauten PHP-Server, in einem leeren Temp-Ordner.
#   bash tools/test_start.sh            lokal, wenn php da ist, sonst auf dem vServer in /tmp
#   bash tools/test_start.sh --hier     immer lokal (php nötig)
set -uo pipefail
cd "$(dirname "$0")/.."
HOST=root@185.16.62.11

if [[ "${1:-}" != "--hier" ]] && ! command -v php >/dev/null; then
    REMOTE=$(ssh "$HOST" 'mktemp -d /tmp/rs-test-XXXXXX')
    scp -q server/start.php tools/test_start.sh "$HOST:$REMOTE/"
    ssh "$HOST" "cd $REMOTE && mkdir -p server tools && mv start.php server/ && mv test_start.sh tools/ && bash tools/test_start.sh --hier; rc=\$?; cd / && rm -rf $REMOTE; exit \$rc"
    exit $?
fi

T=$(mktemp -d)
PORT=$((20000 + RANDOM % 20000))
mkdir -p "$T/daten"
RAWSELECT_TESTDIR="$T/daten" php -S 127.0.0.1:$PORT server/start.php >/dev/null 2>&1 &
PID=$!
for _ in $(seq 50); do curl -s -o /dev/null "http://127.0.0.1:$PORT/" && break; sleep 0.1; done

melde() { curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "$1" "http://127.0.0.1:$PORT/"; }
sql() { php -r '$d=new SQLite3($argv[1]); echo $d->querySingle($argv[2]);' "$T/daten/usage.sqlite" "$1"; }
fail=0
ok() { if [[ "$2" == "$3" ]]; then echo "✓ $1"; else echo "✗ $1 (ist: $2, soll: $3)"; fail=1; fi; }

A=3f2b8c1e-5d4a-4e6f-9a7b-1c2d3e4f5a6b
B=9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d
ok "GET wird abgelehnt"                   "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/")" 405
ok "Erste Meldung: 204"                   "$(melde "{\"id\":\"$A\",\"v\":\"2.2.2\"}")" 204
ok "Eine Installation"                    "$(sql 'SELECT COUNT(*) FROM installationen')" 1
ok "Gleiche Meldung nochmals: 204"        "$(melde "{\"id\":\"$A\",\"v\":\"2.2.2\"}")" 204
ok "Weiterhin eine Installation"          "$(sql 'SELECT COUNT(*) FROM installationen')" 1
ok "Update derselben Installation: 204"   "$(melde "{\"id\":\"$A\",\"v\":\"2.3\"}")" 204
ok "Update zählt keine neue Installation" "$(sql 'SELECT COUNT(*) FROM installationen')" 1
ok "Update: zwei Versionen dieser Installation" "$(sql 'SELECT COUNT(*) FROM installation_versionen')" 2
ok "Erste Version bleibt 2.2.2"           "$(sql 'SELECT version FROM installationen')" 2.2.2
ok "Zweite Installation"                  "$(melde "{\"id\":\"$B\",\"v\":\"2.3\"}")" 204
ok "Zwei Installationen"                  "$(sql 'SELECT COUNT(*) FROM installationen')" 2
ok "2.3 auf zwei Installationen"          "$(sql "SELECT COUNT(*) FROM installation_versionen WHERE version='2.3'")" 2
ok "Gross geschriebene UUID = dieselbe"   "$(melde "{\"id\":\"${B^^}\",\"v\":\"2.3\"}"; sql 'SELECT COUNT(*) FROM installationen')" "2042"
ok "Keine UUID: 400"                      "$(melde '{"id":"hallo","v":"2.3"}')" 400
ok "Falsche Version: 400"                 "$(melde "{\"id\":\"$A\",\"v\":\"<script>\"}")" 400
ok "Kaputtes JSON: 400"                   "$(melde 'x')" 400
ok "Nichts Ungültiges gespeichert"        "$(sql 'SELECT COUNT(*) FROM installationen')" 2
ok "Nummer selbst nie gespeichert"        "$(sql "SELECT COUNT(*) FROM installationen WHERE id LIKE '%$A%' OR id LIKE '%$B%'")" 0
ok "Tag nach Schweizer Zeit"              "$(sql 'SELECT tag FROM installationen LIMIT 1')" "$(TZ=Europe/Zurich date +%Y-%m-%d)"

kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null
rm -rf "$T"
[[ $fail == 0 ]] && echo "✓ start.php: alle Prüfungen grün" || { echo "✗ start.php: Fehler" >&2; exit 1; }
