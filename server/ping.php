<?php
// RAW Select – pseudonymer Nutzungs-Ping.
// Speichert NUR: Zufalls-ID (aus der App), Version, grobe OS-Version, Datum.
// Bewusst KEINE IP-Speicherung (pseudonym, nicht anonym: die Zufallskennung bleibt über Tage gleich).
// Ein Eintrag pro Gerät pro Tag: so zählt "aktive Geräte" sauber, ohne Mehrfach-Pings.

// Datenbank AUSSERHALB des Webroots — nginx liefert unter /rawselect/ ohnehin nur die Allowlist
// aus (server/nginx-rawselect.conf), aber eine DB gehört nie neben öffentliche Dateien.
const DB_PFAD = '/var/lib/rawselect/usage.sqlite';

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
// Nur Haupt- und Nebenversion speichern („macOS 15.6“), auch wenn alte Apps (≤ 1.9) Patch und Build senden.
$os      = preg_match('/(\d+)\.(\d+)/', (string)($data['os'] ?? ''), $m) ? "macOS {$m[1]}.{$m[2]}" : '';
$day     = gmdate('Y-m-d');

try {
    $db = new SQLite3(DB_PFAD);
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
