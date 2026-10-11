#!/usr/bin/env python3
"""RAW Select – GitHub-Release veröffentlichen (DMG + Signatur).

    python3 tools/publish_release.py <version>          z. B. 1.10

Voraussetzungen: Tag v<version> ist gepusht; Releases/v<version>/ enthält
RAW-Select-<version>.dmg, RAW-Select-<version>.dmg.sig und README.txt (= Release-Text).
Bricht ab, wenn die Signatur fehlt oder nicht zum eingebauten Schlüssel passt – ab V1.10
lehnen die Apps unsignierte Updates ab, ein unsigniertes Release wäre für alle unbrauchbar.
Token: ~/.config/rawselect/gh-token (wird nie ausgegeben).
"""
import json, os, pathlib, re, subprocess, sys, urllib.error, urllib.request

REPO = "levinvfx/RAWSelect"
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


tag = f"v{version}"
st, rel = api(f"https://api.github.com/repos/{REPO}/releases/tags/{tag}")
if st != 200:
    st, rel = api(f"https://api.github.com/repos/{REPO}/releases", method="POST", data=json.dumps({
        "tag_name": tag, "target_commitish": "main", "name": f"RAW Select {version}",
        "body": notes.read_text(), "draft": False, "prerelease": False}).encode())
    if st not in (200, 201):
        die(f"Release anlegen: {st} {rel}")
    print("Release angelegt:", rel["html_url"])
else:
    print("Release existiert bereits:", rel["html_url"])

# Signatur ZUERST hochladen: ein Release mit DMG aber ohne .sig würden neue Apps ablehnen.
for f, ctype in ((sig, "text/plain"), (dmg, "application/octet-stream")):
    for a in rel.get("assets", []):
        if a["name"] == f.name:
            api(f"https://api.github.com/repos/{REPO}/releases/assets/{a['id']}", method="DELETE")
    up = f"https://uploads.github.com/repos/{REPO}/releases/{rel['id']}/assets?name={f.name}"
    st, asset = api(up, method="POST", data=f.read_bytes(), ctype=ctype)
    if st not in (200, 201):
        die(f"Upload {f.name}: {st} {asset}")
    print("hochgeladen:", asset.get("browser_download_url"))
