<?php
// RAW Select – Auswertung der anonymen Nutzung. Zeigt NUR aggregierte Zahlen.
// Schutz per Token: stats.php?token=DEIN-WORT  (unten setzen!). Ohne gültiges Token: kein Zugriff.

$TOKEN = 'HIER-EIN-GEHEIMES-WORT-SETZEN';
if (!hash_equals($TOKEN, $_GET['token'] ?? '')) {
    http_response_code(403);
    exit('Kein Zugriff.');
}

$dbFile = __DIR__ . '/rawselect_usage.sqlite';
if (!file_exists($dbFile)) { exit('Noch keine Daten.'); }

$db = new SQLite3($dbFile);
$since = gmdate('Y-m-d', time() - 30 * 86400);   // "aktiv" = in den letzten 30 Tagen gesehen

header('Content-Type: text/plain; charset=utf-8');
echo "RAW Select – aktive Geräte pro Version (letzte 30 Tage)\n";
echo str_repeat('-', 52) . "\n";

$stmt = $db->prepare("SELECT version, COUNT(DISTINCT id) AS n
                      FROM pings WHERE day >= :since
                      GROUP BY version ORDER BY version DESC");
$stmt->bindValue(':since', $since);
$res = $stmt->execute();

$total = 0;
while ($r = $res->fetchArray(SQLITE3_ASSOC)) {
    printf("%-12s %5d Geräte\n", $r['version'], $r['n']);
    $total += (int)$r['n'];
}
echo str_repeat('-', 52) . "\n";
printf("%-12s %5d aktive Geräte insgesamt\n", 'Summe', $total);

// Gesamt je gesehene Geräte (all-time, distinct) als Zusatzinfo.
$allTime = $db->querySingle("SELECT COUNT(DISTINCT id) FROM pings");
printf("%-12s %5d je gesehene Geräte (all-time)\n", 'Total', (int)$allTime);

$db->close();
