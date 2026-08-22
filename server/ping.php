<?php
// RAW Select – anonymer Nutzungs-Ping.
// Speichert NUR: anonyme Zufalls-ID (aus der App), Version, grobe OS-Version, Datum.
// Bewusst KEINE IP-Speicherung – dadurch bleibt der Ping anonym (CH-DSG / DSGVO).
// Ein Eintrag pro Gerät pro Tag: so zählt "aktive Geräte" sauber, ohne Mehrfach-Pings.

header('Content-Type: application/json');

$raw  = file_get_contents('php://input');
$data = json_decode($raw, true);
if (!is_array($data) || empty($data['id']) || empty($data['version'])) {
    http_response_code(400);
    echo '{"ok":false}';
    exit;
}

// Whitelist + Längenbegrenzung – keine Freitext-Injektion, keine überlangen Werte.
$id      = substr(preg_replace('/[^A-Za-z0-9\-]/', '', $data['id']), 0, 64);
$version = substr(preg_replace('/[^0-9A-Za-z.\-]/', '', $data['version']), 0, 20);
$os      = substr(preg_replace('/[^0-9A-Za-z. ]/', '', $data['os'] ?? ''), 0, 60);
$day     = gmdate('Y-m-d');

try {
    $db = new SQLite3(__DIR__ . '/rawselect_usage.sqlite');
    $db->busyTimeout(3000);
    $db->exec('CREATE TABLE IF NOT EXISTS pings (
                 id TEXT, version TEXT, os TEXT, day TEXT,
                 PRIMARY KEY (id, day))');
    // INSERT OR REPLACE: pro Gerät+Tag genau eine Zeile (neueste Version des Tages gewinnt).
    $stmt = $db->prepare('INSERT OR REPLACE INTO pings (id, version, os, day) VALUES (?,?,?,?)');
    $stmt->bindValue(1, $id);
    $stmt->bindValue(2, $version);
    $stmt->bindValue(3, $os);
    $stmt->bindValue(4, $day);
    $stmt->execute();
    $db->close();
    echo '{"ok":true}';
} catch (Throwable $e) {
    http_response_code(500);
    echo '{"ok":false}';
}
