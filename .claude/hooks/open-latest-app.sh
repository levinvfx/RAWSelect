#!/bin/bash
# Stop hook: startet "RAW Select.app" mit der neuesten Version neu — aber NUR, wenn
# das Bundle gerade (in den letzten 3 Min) neu gebaut wurde. So pop't die App nicht
# bei reinen Fragen/Read-Turns, und der Hook baut selbst nichts (das macht
# build_app.sh im normalen Änderungs-Workflow).
#
# Wichtig: eine LAUFENDE App lädt bei `open` NICHT den neuen Code — sie muss erst
# beendet und dann neu geöffnet werden. Genau das macht dieses Script.
set -uo pipefail

app="${CLAUDE_PROJECT_DIR:-.}/RAW Select.app"
[ -d "$app" ] || exit 0

# Bundle-Verzeichnis in den letzten 3 Minuten verändert = frisch gebaut.
[ -n "$(find "$app" -maxdepth 0 -mmin -3 2>/dev/null)" ] || exit 0

# Laufende Instanz sauber beenden und warten, bis der Prozess weg ist (max ~3s).
osascript -e 'quit app "RAW Select"' >/dev/null 2>&1 || true
for _ in $(seq 1 15); do
  pgrep -x RAWSelect >/dev/null 2>&1 || break
  sleep 0.2
done

open "$app"
exit 0
