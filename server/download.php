<?php
// RAW Select – Download-Weiche.
//   /rawselect/download        → liefert das neueste signierte DMG selbst aus (Kopie von GitHub);
//                                 fehlt die Kopie, 302 auf GitHub wie früher
//   /rawselect/download?info   → JSON {version, size, name, url, releases, published}
//
// GitHub wird höchstens alle 10 Minuten gefragt (Cache ausserhalb des Webroots); fällt GitHub aus,
// gilt der letzte bekannte Stand.
// Zählung seit 02.11.2026 (Levin: Mehrfachklicks und abgebrochene Downloads zählten mit): nur ein
// vollständig übertragener Download zählt, höchstens einmal pro Person und Tag. Dafür entsteht pro
// Download ein Prüfwert aus Tag, geheimem Salz, IP und Browserkennung (SHA-256). Die IP selbst wird nie
// gespeichert, die Prüfwerte nur in einer Datei des laufenden Tages, die am nächsten Tag gelöscht wird.
// Tageszahl in usage.sqlite, Tabelle `downloads_fertig`. Die alte Klickzählung `downloads` bleibt als Altbestand.
//
// Reihenfolge der Repos: das erste Repo mit einem Release gewinnt. RAWSelect-Releases ist das
// öffentliche Download-Repo (nur DMG + Signatur, kein Code). Das alte Repo bleibt als Rückfall, solange
// es öffentlich ist – so läuft die Seite auch, bevor das neue Repo existiert.
const REPOS    = ['levinvfx/RAWSelect-Releases', 'levinvfx/RAWSelect'];
const CACHE    = '/var/lib/rawselect/latest.json';
const DB_PFAD  = '/var/lib/rawselect/usage.sqlite';
const MAX_ALTER = 600;   // Sekunden, bis GitHub erneut gefragt wird
const DMG_ORDNER = '/var/lib/rawselect/dmg';
const TAGES_ORDNER = '/var/lib/rawselect/heute';   // eine Datei pro Tag mit den Prüfwerten, ältere werden gelöscht
const SALZ      = '/var/lib/rawselect/salz';

function github(string $url): ?array {
    $ctx = stream_context_create(['http' => [
        'method'  => 'GET',
        'timeout' => 6,
        'header'  => "User-Agent: RAWSelect-Download\r\nAccept: application/vnd.github+json\r\n",
        'ignore_errors' => true,
    ]]);
    $body = @file_get_contents($url, false, $ctx);
    if ($body === false) { return null; }
    $status = 0;
    foreach ($http_response_header ?? [] as $h) {
        if (preg_match('#^HTTP/\S+\s+(\d{3})#', $h, $m)) { $status = (int)$m[1]; }
    }
    if ($status !== 200) { return null; }
    $j = json_decode($body, true);
    return is_array($j) ? $j : null;
}

/** Neuesten Stand holen: erst Cache, sonst GitHub (Repo für Repo), sonst alter Cache. */
function neuester(): ?array {
    $cache = null;
    if (is_file(CACHE)) {
        $cache = json_decode((string)file_get_contents(CACHE), true);
        if (is_array($cache) && (time() - (int)($cache['geholt'] ?? 0)) < MAX_ALTER) { return $cache; }
    }
    foreach (REPOS as $repo) {
        $rel = github("https://api.github.com/repos/$repo/releases/latest");
        if (!$rel || empty($rel['assets'])) { continue; }
        $dmg = null; $sig = false;
        foreach ($rel['assets'] as $a) {
            $n = strtolower($a['name'] ?? '');
            if ($dmg === null && str_ends_with($n, '.dmg')) { $dmg = $a; }
        }
        if ($dmg === null) { continue; }
        foreach ($rel['assets'] as $a) {
            if (($a['name'] ?? '') === $dmg['name'] . '.sig') { $sig = true; }
        }
        // Ohne Signatur kein Download-Link: die App würde so ein Release auch verwerfen.
        if (!$sig) { continue; }
        $neu = [
            'version'   => ltrim((string)($rel['tag_name'] ?? ''), 'vV '),
            'name'      => (string)$dmg['name'],
            'size'      => (int)($dmg['size'] ?? 0),
            'url'       => (string)$dmg['browser_download_url'],
            'releases'  => "https://github.com/$repo/releases",
            'published' => (string)($rel['published_at'] ?? ''),
            'repo'      => $repo,
            'geholt'    => time(),
        ];
        @file_put_contents(CACHE . '.tmp', json_encode($neu, JSON_UNESCAPED_SLASHES));
        @rename(CACHE . '.tmp', CACHE);   // atomar, nie ein halb geschriebener Cache
        return $neu;
    }
    return is_array($cache) ? $cache : null;   // GitHub nicht erreichbar → letzter bekannter Stand
}

/** Lokale Kopie des DMG holen (einmal pro Version, Grösse muss stimmen). Null, wenn es nicht klappt. */
function lokalesDmg(array $stand): ?string {
    $name = basename((string)$stand['name']);
    if (!preg_match('/^[\w.\-]+\.dmg$/', $name)) { return null; }
    $ziel = DMG_ORDNER . '/' . $name;
    if (is_file($ziel) && filesize($ziel) === (int)$stand['size']) { return $ziel; }
    if (!is_dir(DMG_ORDNER)) { @mkdir(DMG_ORDNER, 0750, true); }
    $sperre = @fopen(DMG_ORDNER . '/.holen', 'c');
    if (!$sperre || !flock($sperre, LOCK_EX | LOCK_NB)) { return null; }   // holt gerade ein anderer Aufruf
    $ctx = stream_context_create(['http' => ['timeout' => 20, 'header' => "User-Agent: RAWSelect-Download\r\n"]]);
    $daten = @file_get_contents((string)$stand['url'], false, $ctx);
    $ok = $daten !== false && strlen($daten) === (int)$stand['size'];
    if ($ok) {
        @file_put_contents($ziel . '.tmp', $daten);
        @rename($ziel . '.tmp', $ziel);
        foreach (glob(DMG_ORDNER . '/*.dmg') ?: [] as $alt) { if ($alt !== $ziel) { @unlink($alt); } }
    }
    flock($sperre, LOCK_UN);
    fclose($sperre);
    return $ok && is_file($ziel) ? $ziel : null;
}

/** Fertigen Download zählen, höchstens einmal pro Person und Tag. */
function zaehleDownload(): void {
    try {
        $tag = gmdate('Y-m-d');
        if (!is_file(SALZ)) { @file_put_contents(SALZ, bin2hex(random_bytes(32))); @chmod(SALZ, 0600); }
        $salz = (string)@file_get_contents(SALZ);
        $pruef = hash('sha256', $tag . '|' . $salz . '|' . ($_SERVER['REMOTE_ADDR'] ?? '') . '|' . ($_SERVER['HTTP_USER_AGENT'] ?? ''));
        if (!is_dir(TAGES_ORDNER)) { @mkdir(TAGES_ORDNER, 0700, true); }
        // Prüfwerte älterer Tage sofort weg: eine Datei pro Tag, nur die heutige bleibt
        foreach (glob(TAGES_ORDNER . '/*.txt') ?: [] as $f) { if (basename($f) !== "$tag.txt") { @unlink($f); } }
        $datei = TAGES_ORDNER . "/$tag.txt";
        $fh = fopen($datei, 'c+');
        if (!$fh || !flock($fh, LOCK_EX)) { return; }
        $bekannt = in_array($pruef, preg_split('/\R/', (string)stream_get_contents($fh)), true);
        if (!$bekannt) { fseek($fh, 0, SEEK_END); fwrite($fh, $pruef . "\n"); }
        flock($fh, LOCK_UN);
        fclose($fh);
        @chmod($datei, 0600);
        if ($bekannt) { return; }
        $db = new SQLite3(DB_PFAD);
        $db->busyTimeout(3000);
        $db->exec('CREATE TABLE IF NOT EXISTS downloads_fertig (day TEXT PRIMARY KEY, n INTEGER NOT NULL)');
        $stmt = $db->prepare('INSERT INTO downloads_fertig (day, n) VALUES (:d, 1)
                              ON CONFLICT(day) DO UPDATE SET n = n + 1');
        $stmt->bindValue(':d', $tag);
        $stmt->execute();
        $db->close();
    } catch (Throwable $e) {
        // Zählen darf den Download nie verhindern.
    }
}

$stand = neuester();
header('Cache-Control: no-store');

if (isset($_GET['info'])) {
    header('Content-Type: application/json; charset=utf-8');
    if (!$stand) { http_response_code(503); echo '{"ok":false}'; exit; }
    echo json_encode([
        'ok'        => true,
        'version'   => $stand['version'],
        'name'      => $stand['name'],
        'size'      => $stand['size'],
        'url'       => $stand['url'],
        'releases'  => $stand['releases'],
        'published' => $stand['published'],
    ], JSON_UNESCAPED_SLASHES);
    exit;
}

if (!$stand) {
    // Weder GitHub noch Cache: ehrlich sagen statt ins Leere leiten.
    http_response_code(503);
    header('Content-Type: text/plain; charset=utf-8');
    echo "Der Download ist gerade nicht erreichbar. Bitte in ein paar Minuten noch einmal versuchen.\n";
    echo "Alle Versionen: https://github.com/" . REPOS[0] . "/releases\n";
    exit;
}

$datei = lokalesDmg($stand);
if ($datei === null) {
    // Keine lokale Kopie (GitHub gerade nicht ladbar): wie früher zu GitHub, dort zählt es GitHub.
    header('Location: ' . $stand['url'], true, 302);
    exit;
}

// Datei selbst ausliefern. Ohne Puffer in nginx merkt PHP, wenn der Browser abbricht.
$groesse = filesize($datei);
header('Content-Type: application/x-apple-diskimage');
header('Content-Disposition: attachment; filename="' . basename($datei) . '"');
header('Content-Length: ' . $groesse);
header('X-Accel-Buffering: no');
header('X-Content-Type-Options: nosniff');
if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'GET') { exit; }   // HEAD: nur Kopfzeilen, nichts zählen

ignore_user_abort(true);
while (ob_get_level()) { ob_end_flush(); }
$gesendet = 0;
$fh = fopen($datei, 'rb');
while (!feof($fh) && !connection_aborted()) {
    $stueck = (string)fread($fh, 65536);
    echo $stueck;
    flush();
    $gesendet += strlen($stueck);
}
fclose($fh);

// Nur echte, vollständige Downloads zählen: kein Bot/Link-Vorschau, nichts abgebrochen.
$ua = $_SERVER['HTTP_USER_AGENT'] ?? '';
if ($gesendet === $groesse && !connection_aborted()
    && !preg_match('/bot|crawl|spider|preview|slurp|facebookexternalhit|whatsapp|curl|wget|python/i', $ua)) {
    zaehleDownload();
}
