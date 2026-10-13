<?php
// RAW Select – Download-Weiche.
//   /rawselect/download        → 302 auf das neueste signierte DMG (GitHub Release)
//   /rawselect/download?info   → JSON {version, size, name, url, releases, published}
//
// GitHub wird höchstens alle 10 Minuten gefragt (Cache ausserhalb des Webroots); fällt GitHub aus,
// gilt der letzte bekannte Stand. Downloads werden als reine Tageszahl gezählt – ohne IP, ohne Cookie
// (dieselbe Datenbank wie die Nutzungszählung, Tabelle `downloads`).
//
// Reihenfolge der Repos: das erste Repo mit einem Release gewinnt. RAWSelect-Releases ist das
// öffentliche Download-Repo (nur DMG + Signatur, kein Code). Das alte Repo bleibt als Rückfall, solange
// es öffentlich ist – so läuft die Seite auch, bevor das neue Repo existiert.
const REPOS    = ['levinvfx/RAWSelect-Releases', 'levinvfx/RAWSelect'];
const CACHE    = '/var/lib/rawselect/latest.json';
const DB_PFAD  = '/var/lib/rawselect/usage.sqlite';
const MAX_ALTER = 600;   // Sekunden, bis GitHub erneut gefragt wird

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

function zaehleDownload(): void {
    try {
        $db = new SQLite3(DB_PFAD);
        $db->busyTimeout(3000);
        $db->exec('CREATE TABLE IF NOT EXISTS downloads (day TEXT PRIMARY KEY, n INTEGER NOT NULL)');
        $stmt = $db->prepare('INSERT INTO downloads (day, n) VALUES (:d, 1)
                              ON CONFLICT(day) DO UPDATE SET n = n + 1');
        $stmt->bindValue(':d', gmdate('Y-m-d'));
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

zaehleDownload();
header('Location: ' . $stand['url'], true, 302);
