#!/bin/bash
# Lädt die Download-Seite auf den vServer und prüft sie live.
#   bash tools/deploy_site.sh            Seiten + static/ (index, datenschutz, impressum, Schriften, Animation)
#   bash tools/deploy_site.sh --nginx    zusätzlich das nginx-Snippet (Backup, nginx -t, reload)
# ping.php/stats.php/download.php bleiben unberührt (stats.php braucht das Token, siehe server/README.md).
set -euo pipefail
cd "$(dirname "$0")/.."
HOST=root@185.16.62.11
DAY=$(date +%Y-%m-%d)

if [[ "${1:-}" == "--nginx" ]]; then
    ssh "$HOST" "mkdir -p /root/backups/rawselect/$DAY && cp -p /etc/nginx/snippets/rawselect.conf /root/backups/rawselect/$DAY/rawselect.conf.\$(date +%H%M%S)"
    scp -q server/nginx-rawselect.conf "$HOST:/etc/nginx/snippets/rawselect.conf"
    ssh "$HOST" 'nginx -t && systemctl reload nginx' || { echo "✗ nginx -t fehlgeschlagen – Backup liegt in /root/backups/rawselect/$DAY/" >&2; exit 1; }
    echo "nginx-Snippet aktiv."
fi

scp -q server/site/index.html server/site/datenschutz.html server/site/impressum.html "$HOST:/var/www/rawselect/"
scp -q -r server/site/static/. "$HOST:/var/www/rawselect/static/"
ssh "$HOST" 'cd /var/www/rawselect && chown -R www-data:www-data index.html datenschutz.html impressum.html static && find static -type d -exec chmod 755 {} + && find static -type f -exec chmod 644 {} + && chmod 644 index.html datenschutz.html impressum.html'

fail=0
for path in "" datenschutz impressum static/site.css static/tutorial/tutorial.js static/tutorial/tutorial.css static/inter-400.woff2 static/vfxmedia-wortmarke.svg static/og.png; do
    code=$(curl -s -o /dev/null -w '%{http_code}' "https://vfxmedia.ch/rawselect/$path")
    printf '%-40s %s\n' "/rawselect/$path" "$code"
    [[ "$code" == 200 ]] || fail=1
done
for path in "rawselect/nicht-da.html" "rawselect/index.html.bak"; do
    code=$(curl -s -o /dev/null -w '%{http_code}' "https://vfxmedia.ch/$path")
    printf '%-40s %s (soll 404)\n' "/$path" "$code"
    [[ "$code" == 404 ]] || fail=1
done
main=$(curl -s -o /dev/null -w '%{http_code}' https://vfxmedia.ch/)
echo "Hauptseite: $main"; [[ "$main" == 200 ]] || fail=1
curl -s "https://vfxmedia.ch/rawselect/download?info"; echo
[[ $fail == 0 ]] || { echo "✗ Prüfung fehlgeschlagen" >&2; exit 1; }
echo "✓ Download-Seite live und geprüft."
