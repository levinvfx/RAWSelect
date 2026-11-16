<?php
// RAW Select – Installations-Zähler (seit App 2.2.2, Levin 16.11.2026: «ich will GENAU wissen, wie viele Leute
// es nutzen, einfach runtergeladen haben, mehr nicht»).
//   POST /rawselect/start   Body {"id":"<UUID>","v":"<Version>"}   → 204
// Die App erzeugt beim ersten Start eine zufällige Nummer (UUID) und meldet sie zusammen mit ihrer Version,
// einmal pro Version (also auch nach einem Update), ohne Abfrage und ohne weitere Angaben. Abschaltbar in den
// Einstellungen der App.
// Gespeichert wird nie die Nummer selbst, nur ein Prüfwert aus geheimem Salz und Nummer (SHA-256), dazu Version
// und Schweizer Tag. Keine IP-Adresse, keine Browserkennung, kein Zugriffsprotokoll (nginx: access_log off).
// Tabellen in usage.sqlite:
//   installationen (id, tag, version)          eine Zeile pro Installation: erster Start, mit welcher Version
//   installation_versionen (id, version, tag)  eine Zeile pro Installation und Version (erster Start dieser Version)
// Alte Apps (bis 2.0 Beta 1) melden sich weiter bei ping.php, das bleibt stillgelegt und speichert nichts.
// Tests: tools/test_start.sh (RAWSELECT_TESTDIR lenkt alles in einen Temp-Ordner, wie bei download.php).
date_default_timezone_set('Europe/Zurich');
$TESTDIR = getenv('RAWSELECT_TESTDIR') ?: '';
$BASIS = $TESTDIR !== '' ? rtrim($TESTDIR, '/') : '/var/lib/rawselect';

header('Cache-Control: no-store');
if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') { http_response_code(405); header('Allow: POST'); exit; }

$roh = (string)file_get_contents('php://input', false, null, 0, 512);
$j = json_decode($roh, true);
$id = is_array($j) ? strtolower((string)($j['id'] ?? '')) : '';
$v  = is_array($j) ? (string)($j['v'] ?? '') : '';
// Nur eine echte UUID und eine Versionsnummer wie 2.2.2 oder 2.3-beta1, sonst nichts speichern
if (!preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/', $id)
    || !preg_match('/^\d{1,3}(\.\d{1,3}){1,3}(-[a-z]+\d{0,3})?$/', $v)) {
    http_response_code(400); exit;
}

try {
    $salzDatei = "$BASIS/salz";
    if (!is_file($salzDatei)) { @file_put_contents($salzDatei, bin2hex(random_bytes(32))); @chmod($salzDatei, 0600); }
    $salz = (string)@file_get_contents($salzDatei);
    if (strlen($salz) < 32) { http_response_code(503); exit; }
    $pruef = hash('sha256', 'installation|' . $salz . '|' . $id);
    $tag = date('Y-m-d');

    $db = new SQLite3("$BASIS/usage.sqlite");
    $db->busyTimeout(3000);
    $db->exec('CREATE TABLE IF NOT EXISTS installationen (id TEXT PRIMARY KEY, tag TEXT NOT NULL, version TEXT NOT NULL)');
    $db->exec('CREATE TABLE IF NOT EXISTS installation_versionen (id TEXT NOT NULL, version TEXT NOT NULL, tag TEXT NOT NULL,
               PRIMARY KEY (id, version))');
    foreach (['INSERT OR IGNORE INTO installationen (id, tag, version) VALUES (:i, :t, :v)',
              'INSERT OR IGNORE INTO installation_versionen (id, version, tag) VALUES (:i, :v, :t)'] as $sql) {
        $st = $db->prepare($sql);
        $st->bindValue(':i', $pruef);
        $st->bindValue(':t', $tag);
        $st->bindValue(':v', $v);
        $st->execute();
    }
    $db->close();
} catch (Throwable $e) {
    http_response_code(503); exit;   // die App versucht es beim nächsten Start nochmals
}
http_response_code(204);
