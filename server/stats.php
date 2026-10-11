<?php
// RAW Select – Auswertung der anonymen Nutzung. Zeigt NUR aggregierte Zahlen.
// Schutz per Token: stats.php?token=DEIN-WORT  (unten setzen!). Ohne gültiges Token: kein Zugriff.

$TOKEN = 'HIER-EIN-GEHEIMES-WORT-SETZEN';

// Pfad zur Datenbank — ausserhalb des Webroots, gleich wie in ping.php.
$DB_PFAD = '/var/lib/rawselect/usage.sqlite';

if (!hash_equals($TOKEN, $_GET['token'] ?? '')) {
    http_response_code(403);
    exit('Kein Zugriff.');
}

$dbFile = $DB_PFAD;
if (!file_exists($dbFile)) { exit('Noch keine Daten.'); }

$db = new SQLite3($dbFile);
$db->busyTimeout(3000);

$since   = gmdate('Y-m-d', time() - 30 * 86400);   // "aktiv" = in den letzten 30 Tagen gesehen
$heute   = gmdate('Y-m-d');

/** Kleine Hilfe: eine vorbereitete Abfrage als Array zurückgeben. */
function hole(SQLite3 $db, string $sql, array $werte = []): array {
    $stmt = $db->prepare($sql);
    foreach ($werte as $k => $v) { $stmt->bindValue($k, $v); }
    $res = $stmt->execute();
    $out = [];
    while ($r = $res->fetchArray(SQLITE3_ASSOC)) { $out[] = $r; }
    return $out;
}

// --- Kennzahlen ------------------------------------------------------------
$aktiv30 = (int)$db->querySingle("SELECT COUNT(DISTINCT id) FROM pings WHERE day >= '" . SQLite3::escapeString($since) . "'");
$allTime = (int)$db->querySingle("SELECT COUNT(DISTINCT id) FROM pings");
$aktivHeute = (int)$db->querySingle("SELECT COUNT(DISTINCT id) FROM pings WHERE day = '" . SQLite3::escapeString($heute) . "'");
$ersterTag  = (string)$db->querySingle("SELECT MIN(day) FROM pings");
$letzterTag = (string)$db->querySingle("SELECT MAX(day) FROM pings");

// --- Versionen: aktiv (30 Tage) und all-time -------------------------------
$aktiv = hole($db, "SELECT version, COUNT(DISTINCT id) AS n FROM pings
                    WHERE day >= :since GROUP BY version", [':since' => $since]);
$aktivProVersion = [];
foreach ($aktiv as $r) { $aktivProVersion[$r['version']] = (int)$r['n']; }

$alle = hole($db, "SELECT version,
                          COUNT(DISTINCT id) AS n,
                          MIN(day) AS erst,
                          MAX(day) AS letzt
                   FROM pings GROUP BY version");

// Nach Versionsnummer sortieren, nicht alphabetisch – sonst stünde 1.9 über 1.10.
usort($alle, function ($a, $b) { return version_compare($b['version'], $a['version']); });

$maxAlle  = 0; foreach ($alle as $r) { $maxAlle  = max($maxAlle,  (int)$r['n']); }
$maxAktiv = 0; foreach ($aktivProVersion as $n) { $maxAktiv = max($maxAktiv, $n); }

// --- macOS-Verteilung (aktive Geräte) --------------------------------------
$osListe = hole($db, "SELECT CASE WHEN os = '' THEN 'unbekannt' ELSE os END AS os,
                             COUNT(DISTINCT id) AS n
                      FROM pings WHERE day >= :since
                      GROUP BY os ORDER BY n DESC", [':since' => $since]);
$maxOs = 0; foreach ($osListe as $r) { $maxOs = max($maxOs, (int)$r['n']); }

// --- Verlauf der letzten 30 Tage -------------------------------------------
$verlaufRoh = hole($db, "SELECT day, COUNT(DISTINCT id) AS n FROM pings
                         WHERE day >= :since GROUP BY day", [':since' => $since]);
$proTag = [];
foreach ($verlaufRoh as $r) { $proTag[$r['day']] = (int)$r['n']; }
$verlauf = [];
for ($i = 29; $i >= 0; $i--) {
    $t = gmdate('Y-m-d', time() - $i * 86400);
    $verlauf[] = ['tag' => $t, 'n' => $proTag[$t] ?? 0];
}
$maxTag = 1; foreach ($verlauf as $v) { $maxTag = max($maxTag, $v['n']); }

$db->close();

/** Datum als 02.09.2026 statt 2026-09-02. */
function datum(string $iso): string {
    if ($iso === '') { return '–'; }
    $t = DateTime::createFromFormat('Y-m-d', $iso);
    return $t ? $t->format('d.m.Y') : $iso;
}
function e(?string $s): string { return htmlspecialchars((string)$s, ENT_QUOTES, 'UTF-8'); }
function prozent(int $wert, int $max): float { return $max > 0 ? round($wert / $max * 100, 1) : 0.0; }

header('Content-Type: text/html; charset=utf-8');
?>
<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>RAW Select – Nutzung</title>
<style>
  :root, :root[data-theme="light"] {
    --bg: #f4f6fa;
    --surface: #ffffff;
    --surface-2: #eef1f6;
    --fill: rgba(14,27,51,.05);
    --border: rgba(14,27,51,.10);
    --text: #0e1b33;
    --muted: #55617a;
    --accent: #14315e;
    --accent-soft: rgba(20,49,94,.14);
    --radius: 16px;
    --radius-s: 10px;
    --shadow: 0 1px 2px rgba(14,27,51,.04), 0 10px 30px -16px rgba(14,27,51,.16);
    --font: "Inter", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    --ease: cubic-bezier(.22,1,.36,1);
  }
  @media (prefers-color-scheme: dark) {
    :root:not([data-theme="light"]) {
      --bg: #0a1224;
      --surface: #0f1c33;
      --surface-2: #16294a;
      --fill: rgba(255,255,255,.06);
      --border: rgba(255,255,255,.12);
      --text: #eaf0fb;
      --muted: #9aa8c4;
      --accent: #6f9bdc;
      --accent-soft: rgba(111,155,220,.18);
      --shadow: 0 1px 2px rgba(0,0,0,.30), 0 10px 30px -16px rgba(0,0,0,.55);
    }
  }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    padding: clamp(20px, 5vw, 48px) clamp(14px, 4vw, 28px) 64px;
    background: var(--bg);
    color: var(--text);
    font-family: var(--font);
    font-size: 15px;
    line-height: 1.55;
    -webkit-font-smoothing: antialiased;
  }
  .huelle { max-width: 940px; margin: 0 auto; }

  header { margin-bottom: 28px; }
  h1 { margin: 0 0 4px; font-size: clamp(24px, 4vw, 32px); letter-spacing: -0.02em; font-weight: 650; }
  .unterzeile { margin: 0; color: var(--muted); font-size: 14px; }

  .karten { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 14px; margin-bottom: 28px; }
  .kachel {
    background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius);
    padding: 18px 20px; box-shadow: var(--shadow);
  }
  .kachel .zahl { font-size: 32px; font-weight: 650; letter-spacing: -0.03em; line-height: 1.1; }
  .kachel .titel { color: var(--muted); font-size: 13px; margin-top: 2px; }

  section {
    background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius);
    padding: 22px clamp(16px, 3vw, 26px); box-shadow: var(--shadow); margin-bottom: 20px;
  }
  h2 { margin: 0 0 2px; font-size: 17px; font-weight: 620; letter-spacing: -0.01em; }
  .hinweis { margin: 0 0 18px; color: var(--muted); font-size: 13px; }

  table { width: 100%; border-collapse: collapse; }
  th, td { text-align: left; padding: 11px 10px; border-bottom: 1px solid var(--border); }
  th { font-size: 12px; font-weight: 600; color: var(--muted); text-transform: uppercase; letter-spacing: .04em; }
  tr:last-child td { border-bottom: 0; }
  td.zahl, th.zahl { text-align: right; font-variant-numeric: tabular-nums; white-space: nowrap; }
  .version { font-weight: 600; font-variant-numeric: tabular-nums; }
  .datum { color: var(--muted); font-size: 13px; font-variant-numeric: tabular-nums; white-space: nowrap; }

  .balken { background: var(--fill); border-radius: var(--radius-s); height: 8px; overflow: hidden; min-width: 90px; }
  .balken > i { display: block; height: 100%; background: var(--accent); border-radius: var(--radius-s); }
  td.balkenzelle { width: 42%; }

  .marke {
    display: inline-block; padding: 2px 9px; border-radius: 999px;
    background: var(--accent-soft); color: var(--accent);
    font-size: 12px; font-weight: 600; white-space: nowrap;
  }
  .still { color: var(--muted); }

  .verlauf { display: flex; align-items: flex-end; gap: 3px; height: 96px; margin-top: 6px; }
  .verlauf .tag { flex: 1; background: var(--fill); border-radius: 3px 3px 0 0; position: relative; min-height: 3px; }
  .verlauf .tag > i { position: absolute; inset: auto 0 0 0; background: var(--accent); border-radius: 3px 3px 0 0; }
  .achse { display: flex; justify-content: space-between; color: var(--muted); font-size: 12px; margin-top: 8px; }

  footer { color: var(--muted); font-size: 13px; text-align: center; margin-top: 32px; }

  @media (max-width: 560px) {
    td.balkenzelle, th.balkenzelle { display: none; }
    th, td { padding: 10px 6px; }
  }
</style>
</head>
<body>
<div class="huelle">

  <header>
    <h1>RAW Select – Nutzung</h1>
    <p class="unterzeile">Anonyme Zählung. Ein Eintrag pro Gerät und Tag, keine persönlichen Daten.</p>
  </header>

  <div class="karten">
    <div class="kachel">
      <div class="zahl"><?= $aktiv30 ?></div>
      <div class="titel">aktive Geräte (30 Tage)</div>
    </div>
    <div class="kachel">
      <div class="zahl"><?= $allTime ?></div>
      <div class="titel">Geräte insgesamt</div>
    </div>
    <div class="kachel">
      <div class="zahl"><?= $aktivHeute ?></div>
      <div class="titel">heute gesehen</div>
    </div>
    <div class="kachel">
      <div class="zahl"><?= count($alle) ?></div>
      <div class="titel">Versionen im Umlauf</div>
    </div>
  </div>

  <section>
    <h2>Alle Versionen</h2>
    <p class="hinweis">Jede Version, die je einen Ping gesendet hat – auch längst abgelöste.</p>
    <table>
      <thead>
        <tr>
          <th>Version</th>
          <th class="zahl">Geräte</th>
          <th class="balkenzelle"></th>
          <th class="zahl">aktiv (30 T.)</th>
          <th>zuerst</th>
          <th>zuletzt</th>
        </tr>
      </thead>
      <tbody>
      <?php foreach ($alle as $r):
              $n = (int)$r['n'];
              $a = $aktivProVersion[$r['version']] ?? 0; ?>
        <tr>
          <td class="version"><?= e($r['version']) ?></td>
          <td class="zahl"><?= $n ?></td>
          <td class="balkenzelle">
            <div class="balken"><i style="width: <?= prozent($n, $maxAlle) ?>%"></i></div>
          </td>
          <td class="zahl"><?= $a > 0 ? '<span class="marke">' . $a . '</span>' : '<span class="still">–</span>' ?></td>
          <td class="datum"><?= datum($r['erst']) ?></td>
          <td class="datum"><?= datum($r['letzt']) ?></td>
        </tr>
      <?php endforeach; ?>
      </tbody>
    </table>
  </section>

  <?php if ($osListe): ?>
  <section>
    <h2>macOS-Versionen</h2>
    <p class="hinweis">Nur aktive Geräte der letzten 30 Tage.</p>
    <table>
      <thead><tr><th>System</th><th class="zahl">Geräte</th><th class="balkenzelle"></th></tr></thead>
      <tbody>
      <?php foreach ($osListe as $r): $n = (int)$r['n']; ?>
        <tr>
          <td><?= e($r['os']) ?></td>
          <td class="zahl"><?= $n ?></td>
          <td class="balkenzelle"><div class="balken"><i style="width: <?= prozent($n, $maxOs) ?>%"></i></div></td>
        </tr>
      <?php endforeach; ?>
      </tbody>
    </table>
  </section>
  <?php endif; ?>

  <section>
    <h2>Letzte 30 Tage</h2>
    <p class="hinweis">Aktive Geräte pro Tag. Höchstwert: <?= $maxTag ?>.</p>
    <div class="verlauf">
      <?php foreach ($verlauf as $v): ?>
        <div class="tag" title="<?= datum($v['tag']) ?>: <?= $v['n'] ?>">
          <i style="height: <?= prozent($v['n'], $maxTag) ?>%"></i>
        </div>
      <?php endforeach; ?>
    </div>
    <div class="achse">
      <span><?= datum($verlauf[0]['tag']) ?></span>
      <span><?= datum($verlauf[count($verlauf) - 1]['tag']) ?></span>
    </div>
  </section>

  <footer>
    Daten von <?= datum($ersterTag) ?> bis <?= datum($letzterTag) ?>
  </footer>

</div>
</body>
</html>
