#!/bin/bash
# Lädt die Download-Seite (server/site/) auf den vServer und prüft sie. Nur index.html + static/ –
# ping.php/stats.php/download.php bleiben unberührt (stats.php braucht das Token, siehe server/README.md).
#   bash tools/deploy_site.sh
set -euo pipefail
cd "$(dirname "$0")/.."
HOST=root@185.16.62.11
scp -q server/site/index.html "$HOST:/var/www/rawselect/index.html"
scp -q server/site/static/* "$HOST:/var/www/rawselect/static/"
ssh "$HOST" 'cd /var/www/rawselect && chown -R www-data:www-data index.html static && chmod 755 static && chmod 644 index.html static/*'
code=$(curl -s -o /dev/null -w '%{http_code}' https://vfxmedia.ch/rawselect/)
main=$(curl -s -o /dev/null -w '%{http_code}' https://vfxmedia.ch/)
echo "Download-Seite: $code · Hauptseite: $main"
[[ "$code" == 200 && "$main" == 200 ]] || { echo "✗ Prüfung fehlgeschlagen" >&2; exit 1; }
curl -s "https://vfxmedia.ch/rawselect/download?info"; echo
