#!/usr/bin/env python3
"""RAW Select – GitHub-Release veröffentlichen (DMG + Signatur).

    python3 tools/publish_release.py <version>          z. B. 1.11

Voraussetzungen: Tag v<version> ist gepusht; Releases/v<version>/ enthält
RAW-Select-<version>.dmg, RAW-Select-<version>.dmg.sig und README.txt (= Release-Text).
Bricht ab, wenn die Signatur fehlt oder nicht zum eingebauten Schlüssel passt – ab V1.10
lehnen die Apps unsignierte Updates ab, ein unsigniertes Release wäre für alle unbrauchbar.

Veröffentlicht wird in ALLE Repos in REPOS:
  - levinvfx/RAWSelect-Releases: öffentliches Download-Repo (nur DMG + .sig, kein Code). Hier
    fragen Apps ab V1.11 und die Download-Seite (vfxmedia.ch/rawselect/) nach.
  - levinvfx/RAWSelect: das Code-Repo. Apps ≤ 1.10 fragen noch hier nach; bleibt in der Liste,
    bis kein altes Gerät mehr aktiv ist (Admin → Insights → RAW Select) und das Repo privat geschaltet wurde.
Ein Repo, das 404 liefert (noch nicht angelegt / Token ohne Zugriff / privat), wird mit Warnung
übersprungen; mindestens eines muss gelingen.
Token: ~/.config/rawselect/gh-token (wird nie ausgegeben).
"""
import json, pathlib, re, subprocess, sys, urllib.error, urllib.request

REPOS = ["levinvfx/RAWSelect-Releases", "levinvfx/RAWSelect"]
ROOT = pathlib.Path(__file__).resolve().parent.parent


def die(msg):
    print("FEHLER:", msg)
    sys.exit(1)


if len(sys.argv) != 2:
    die("Aufruf: publish_release.py <version>")
version = sys.argv[1]
rel_dir = ROOT / "Releases" / f"v{version}"
dmg = rel_dir / f"RAW-Select-{version}.dmg"
sig = rel_dir / f"RAW-Select-{version}.dmg.sig"
notes = rel_dir / "README.txt"
for f in (dmg, sig, notes):
    if not f.exists():
        die(f"fehlt: {f}")

# Signatur gegen den in der App eingebauten öffentlichen Schlüssel prüfen.
const = (ROOT / "Sources/RAWSelect/Utilities/Constants.swift").read_text()
m = re.search(r'updatePublicKey = "([^"]+)"', const)
if not m:
    die("updatePublicKey nicht in Constants.swift gefunden")
check = subprocess.run(["swift", str(ROOT / "tools/sign_update.swift"), "verify", m.group(1),
                        str(dmg), version, str(sig)], capture_output=True, text=True)
if check.returncode != 0:
    die("Signatur ungültig – nichts veröffentlicht. " + check.stdout + check.stderr)
print("Signatur gültig.")

token = (pathlib.Path.home() / ".config/rawselect/gh-token").read_text().strip()


def api(url, method="GET", data=None, ctype="application/json"):
    req = urllib.request.Request(url, method=method)
    req.add_header("Authorization", "Bearer " + token)
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    req.add_header("Accept", "application/vnd.github+json")
    if data is not None:
        req.add_header("Content-Type", ctype)
        req.data = data
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        try:
            return e.code, json.loads(body)
        except Exception:
            return e.code, {"raw": body}


def publish(repo):
    """Release in einem Repo anlegen/ergänzen. True = fertig, False = Repo nicht erreichbar."""
    tag = f"v{version}"
    st, info = api(f"https://api.github.com/repos/{repo}")
    if st == 404:
        print(f"WARNUNG: {repo} nicht erreichbar (404) – übersprungen. Repo anlegen und dem Token freigeben.")
        return False
    if st != 200:
        die(f"{repo}: {st} {info}")
    branch = info.get("default_branch") or "main"

    st, rel = api(f"https://api.github.com/repos/{repo}/releases/tags/{tag}")
    if st != 200:
        # GitHub legt den Tag auf dem Default-Branch an, falls er im Repo noch nicht existiert
        # (im Download-Repo gibt es keinen Code-Tag – dort zeigt er auf die README).
        st, rel = api(f"https://api.github.com/repos/{repo}/releases", method="POST", data=json.dumps({
            "tag_name": tag, "target_commitish": branch, "name": f"RAW Select {version}",
            "body": notes.read_text(), "draft": False, "prerelease": False}).encode())
        if st not in (200, 201):
            die(f"{repo}: Release anlegen: {st} {rel}")
        print(f"[{repo}] Release angelegt:", rel["html_url"])
    else:
        print(f"[{repo}] Release existiert bereits:", rel["html_url"])

    # Signatur ZUERST hochladen: ein Release mit DMG aber ohne .sig würden neue Apps ablehnen.
    for f, ctype in ((sig, "text/plain"), (dmg, "application/octet-stream")):
        for a in rel.get("assets", []):
            if a["name"] == f.name:
                api(f"https://api.github.com/repos/{repo}/releases/assets/{a['id']}", method="DELETE")
        up = f"https://uploads.github.com/repos/{repo}/releases/{rel['id']}/assets?name={f.name}"
        st, asset = api(up, method="POST", data=f.read_bytes(), ctype=ctype)
        if st not in (200, 201):
            die(f"{repo}: Upload {f.name}: {st} {asset}")
        print(f"[{repo}] hochgeladen:", asset.get("browser_download_url"))
    return True


done = [r for r in REPOS if publish(r)]
if not done:
    die("in keinem Repo veröffentlicht")
print("Fertig:", ", ".join(done))
