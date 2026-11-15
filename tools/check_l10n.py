#!/usr/bin/env python3
"""Prüft die englische Übersetzung gegen den Code.

Der Swift-Compiler schreibt beim Release-Build jeden Text heraus, den die App zur Laufzeit
nachschlägt (SwiftUI-Literale und L("…")). Dieses Skript vergleicht diese Liste mit
Localization/en.lproj/Localizable.strings:
  - fehlt ein Text in der Tabelle, bliebe er in der englischen App deutsch  → Fehler
  - steht ein Text nur in der Tabelle, ist er veraltet                      → Fehler
  - Platzhalter (%@, %lld) müssen in beiden Sprachen gleich oft vorkommen   → Fehler

  python3 tools/check_l10n.py            prüfen
  python3 tools/check_l10n.py --keys     nur die Texte aus dem Code ausgeben
"""
import glob, json, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, ".build", "l10n")
TABLE = os.path.join(ROOT, "Localization", "en.lproj", "Localizable.strings")
# Texte, die absichtlich nicht übersetzt werden (Eigennamen, reine Platzhalter).
SAME = {"", "Orange", "%lld", "%@", "%lld%%", "%lld / %lld", "ISO", "System", "Name", "Instagram", "VFX MEDIA", "VFX Media", "OK", "Export", "Google Drive", "Lr", "Export JPEG", "%@ %@", "·"}


def code_keys():
    # Immer frisch bauen: ein inkrementeller Build schreibt nur die Listen der neu übersetzten Dateien.
    import shutil
    shutil.rmtree(OUT, ignore_errors=True)
    shutil.rmtree(os.path.join(ROOT, ".build", "l10n-build"), ignore_errors=True)
    os.makedirs(OUT, exist_ok=True)
    cmd = ["swift", "build", "-c", "release", "--scratch-path", os.path.join(ROOT, ".build", "l10n-build"),
           "-Xswiftc", "-emit-localized-strings", "-Xswiftc", "-emit-localized-strings-path", "-Xswiftc", OUT]
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("Build fehlgeschlagen:\n" + r.stdout[-2000:] + r.stderr[-2000:])
    keys = {}
    for f in sorted(glob.glob(os.path.join(OUT, "*.stringsdata"))):
        data = json.load(open(f))
        for entries in data.get("tables", {}).values():
            for e in entries:
                keys.setdefault(e["key"], os.path.basename(data["source"]))
    return keys


def table():
    text = open(TABLE, encoding="utf-8").read()
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    pairs = re.findall(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";\s*$', text, flags=re.M)
    rest = re.sub(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";\s*$', "", text, flags=re.M).strip()
    if rest:
        sys.exit("Unlesbare Zeilen in Localizable.strings:\n" + rest[:500])
    un = lambda s: s.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")
    out = {}
    for k, v in pairs:
        if un(k) in out:
            sys.exit("Doppelter Schlüssel: " + k)
        out[un(k)] = un(v)
    return out


def specs(s):
    return sorted(re.sub(r"\d+\$", "", m) for m in re.findall(r"%(?:\d+\$)?(?:lld|ld|d|@|f|g)", s))


def main():
    keys = code_keys()
    if "--keys" in sys.argv:
        for k, src in sorted(keys.items(), key=lambda kv: (kv[1], kv[0])):
            print(src + "\t" + json.dumps(k, ensure_ascii=False))
        return
    tab = table()
    import plistlib
    plural = {}
    for lang in ("de", "en"):
        with open(os.path.join(ROOT, "Localization", lang + ".lproj", "Localizable.stringsdict"), "rb") as f:
            plural[lang] = plistlib.load(f)
    if set(plural["de"]) != set(plural["en"]):
        sys.exit("Mehrzahl-Tabellen (stringsdict) haben in de und en nicht dieselben Schlüssel.")
    both = [k for k in plural["en"] if k in tab]
    if both:
        sys.exit("Schlüssel steht in .strings UND .stringsdict: " + ", ".join(both))
    stale_plural = [k for k in plural["en"] if k not in keys]
    if stale_plural:
        sys.exit("Veraltet in der Mehrzahl-Tabelle: " + ", ".join(stale_plural))
    keys = {k: v for k, v in keys.items() if k not in plural["en"]}
    missing = [k for k in keys if k not in tab and k not in SAME]
    stale = [k for k in tab if k not in keys]
    bad = [k for k, v in tab.items() if specs(k) != specs(v)]
    empty = [k for k, v in tab.items() if not v.strip()]
    for title, items in (("Fehlt in der englischen Tabelle", missing), ("Veraltet (nicht mehr im Code)", stale),
                         ("Platzhalter stimmen nicht überein", bad), ("Leere Übersetzung", empty)):
        if items:
            print("✗ " + title + ":")
            for k in sorted(items):
                print("    " + json.dumps(k, ensure_ascii=False) + ("   [" + keys[k] + "]" if k in keys else ""))
    if missing or stale or bad or empty:
        sys.exit(1)
    print("✓ Übersetzung vollständig: %d Texte im Code, davon %d mit Einzahl/Mehrzahl." % (len(keys) + len(plural["en"]), len(plural["en"])))


if __name__ == "__main__":
    main()
