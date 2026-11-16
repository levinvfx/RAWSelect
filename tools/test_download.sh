#!/bin/bash
# Testet die Zählung von server/download.php mit dem eingebauten PHP-Server, in einem leeren Temp-Ordner.
# Nie mit echten Daten: RAWSELECT_TESTDIR lenkt Cache, Datenbank, Kopie, Salz und Prüfwerte in den Temp-Ordner,
# GitHub wird nicht gefragt (Quelle ist eine lokale Datei über file://).
#   bash tools/test_download.sh            lokal, wenn php da ist, sonst auf dem vServer in /tmp
#   bash tools/test_download.sh --hier     immer lokal (php nötig)
set -uo pipefail
cd "$(dirname "$0")/.."
HOST=root@185.16.62.11

if [[ "${1:-}" != "--hier" ]] && ! command -v php >/dev/null; then
    REMOTE=$(ssh "$HOST" 'mktemp -d /tmp/rs-test-XXXXXX')
    scp -q server/download.php tools/test_download.sh "$HOST:$REMOTE/"
    ssh "$HOST" "cd $REMOTE && mkdir -p server tools && mv download.php server/ && mv test_download.sh tools/ && bash tools/test_download.sh --hier; rc=\$?; cd / && rm -rf $REMOTE; exit \$rc"
    exit $?
fi

T=$(mktemp -d)
PORT=$((20000 + RANDOM % 20000))
cp server/download.php "$T/download.php"
mkdir -p "$T/daten/dmg" "$T/quelle"
head -c 20000000 /dev/urandom > "$T/quelle/RAW-Select-9.9.0.dmg"   # gross genug, dass ein Abbruch nicht im Puffer verschwindet
head -c 400000 /dev/urandom > "$T/quelle/RAW-Select-9.9.1.dmg"

stand() {   # stand <version> <groesse> <url>
    printf '{"version":"%s","name":"RAW-Select-%s.dmg","size":%s,"url":"%s","releases":"x","published":"2026-11-15T09:58:36Z","repo":"x","geholt":%s}' \
        "$1" "$1" "$2" "$3" "$(date +%s)" > "$T/daten/latest.json"
}
zahl() {     # zahl <tag> <version> <art>
    php -r '$d=new SQLite3($argv[1]); $r=@$d->querySingle("SELECT n FROM downloads_tag WHERE day=\x27".$argv[2]."\x27 AND version=\x27".$argv[3]."\x27 AND art=\x27".$argv[4]."\x27"); echo $r?:0;' \
        "$T/daten/usage.sqlite" "$1" "$2" "$3"
}
server() {   # Server mit optionaler Testzeit neu starten
    [[ -n "${PID:-}" ]] && kill "$PID" 2>/dev/null && wait "$PID" 2>/dev/null
    RAWSELECT_TESTDIR="$T/daten" RAWSELECT_TESTZEIT="${1:-}" php -S 127.0.0.1:$PORT "$T/download.php" >/dev/null 2>&1 &
    PID=$!
    for _ in $(seq 50); do curl -s -o /dev/null "http://127.0.0.1:$PORT/?info" && break; sleep 0.1; done
}
holen() { curl -s -o /dev/null -w '%{http_code}' -A "${1:-Mozilla/5.0 (Macintosh)}" "${@:2}" "http://127.0.0.1:$PORT/"; }

fail=0
ok() { if [[ "$2" == "$3" ]]; then echo "✓ $1"; else echo "✗ $1 (ist: $2, soll: $3)"; fail=1; fi; }

HEUTE=$(TZ=Europe/Zurich date +%Y-%m-%d)
stand 9.9.0 20000000 "file://$T/quelle/RAW-Select-9.9.0.dmg"
server

ok "Erster Download: 200"                       "$(holen)" 200
ok "Eigener Abruf der Kopie gezählt (server)"   "$(zahl "$HEUTE" 9.9.0 server)" 1
ok "Fertiger Download zählt bei 9.9.0"          "$(zahl "$HEUTE" 9.9.0 website)" 1
holen >/dev/null
ok "Gleiche Person nochmals: zählt nicht"       "$(zahl "$HEUTE" 9.9.0 website)" 1
ok "Kopie vorhanden: kein zweiter Abruf"        "$(zahl "$HEUTE" 9.9.0 server)" 1
holen "Mozilla/5.0 (Andere)" >/dev/null
ok "Andere Person: zählt"                       "$(zahl "$HEUTE" 9.9.0 website)" 2
ok "HEAD: 200"                                  "$(holen "Mozilla/5.0 (Head)" -I)" 200
ok "HEAD zählt nicht"                           "$(zahl "$HEUTE" 9.9.0 website)" 2
holen "Googlebot/2.1" >/dev/null
ok "Bot zählt nicht"                            "$(zahl "$HEUTE" 9.9.0 website)" 2
curl -s -o /dev/null -A "Mozilla/5.0 (Abbruch)" --limit-rate 20k --max-time 1 "http://127.0.0.1:$PORT/"
sleep 1
ok "Abgebrochener Download zählt nicht"         "$(zahl "$HEUTE" 9.9.0 website)" 2

# Neue Version erscheint: die ausgelieferte Datei bestimmt die Version
stand 9.9.1 400000 "file://$T/quelle/RAW-Select-9.9.1.dmg"
holen >/dev/null
ok "Nach Umstellung: Download zählt bei 9.9.1"  "$(zahl "$HEUTE" 9.9.1 website)" 1
ok "Nach Umstellung: 9.9.0 bleibt bei 2"        "$(zahl "$HEUTE" 9.9.0 website)" 2
ok "Abruf der neuen Kopie gezählt"              "$(zahl "$HEUTE" 9.9.1 server)" 1

# Rückfall auf GitHub: Kopie fehlt und lässt sich nicht holen → 302, wird gezählt
stand 9.9.2 123 "file://$T/quelle/fehlt.dmg"
ok "Rückfall: 302"                              "$(holen)" 302
holen >/dev/null
ok "Rückfall: Person einmal (umweg)"            "$(zahl "$HEUTE" 9.9.2 umweg)" 1
ok "Rückfall: jeder 302 (umweg_github)"         "$(zahl "$HEUTE" 9.9.2 umweg_github)" 2
ok "Rückfall: fehlgeschlagene Abrufe gezählt"   "$(zahl "$HEUTE" 9.9.2 server_fehler)" 2
ok "Rückfall: kein Website-Download"            "$(zahl "$HEUTE" 9.9.2 website)" 0
holen "Googlebot/2.1" >/dev/null
ok "Rückfall Bot: nicht als Person"             "$(zahl "$HEUTE" 9.9.2 umweg)" 1

# Tageswechsel nach Schweizer Zeit: 23:30 UTC am 15.11. ist schon der 16.11. in Thun
stand 9.9.1 400000 "file://$T/quelle/RAW-Select-9.9.1.dmg"
VORHER=$(zahl 2026-11-15 9.9.1 website)
server "$(date -d '2026-11-15T23:30:00Z' +%s 2>/dev/null || date -j -f '%Y-%m-%dT%H:%M:%SZ' '2026-11-15T23:30:00Z' +%s)"
holen "Mozilla/5.0 (Nacht)" >/dev/null
ok "23:30 UTC zählt am 16.11. (Schweizer Tag)"  "$(zahl 2026-11-16 9.9.1 website)" 1
ok "23:30 UTC nicht am 15.11."                  "$(zahl 2026-11-15 9.9.1 website)" "$VORHER"
ok "Prüfwerte älterer Tage gelöscht"            "$(ls "$T/daten/heute" | tr '\n' ' ')" "2026-11-16.txt "
ok "Keine IP in der Tagesdatei"                 "$(grep -c '127.0.0.1' "$T/daten/heute/2026-11-16.txt")" 0

kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null
rm -rf "$T"
[[ $fail == 0 ]] && echo "✓ download.php: alle Prüfungen grün" || { echo "✗ download.php: Fehler" >&2; exit 1; }
