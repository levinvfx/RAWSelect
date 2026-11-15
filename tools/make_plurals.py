#!/usr/bin/env python3
"""Erzeugt Localization/{de,en}.lproj/Localizable.stringsdict (Texte mit Anzahl: «1 Bild» / «2 Bilder»).

Jeder Eintrag: Schlüssel aus dem Code → pro Sprache ein Format und die Wortformen der Zählwörter.
Im Format steht {name} für ein Zählwort; die Position des Arguments ergibt sich aus dem Schlüssel
(1. Platzhalter = 1, …) und wird hier als Zahl angegeben.  Aufruf: python3 tools/make_plurals.py
"""
import os, plistlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

W = {  # Zählwörter: (eins, sonst)
    "de": {"bilder": ("%lld Bild", "%lld Bilder"), "dateien": ("%lld Datei", "%lld Dateien"),
           "markierungen": ("%lld Markierung ist", "%lld Markierungen sind"),
           "markierte": ("%lld markiertes Bild", "%lld markierte Bilder")},
    "en": {"bilder": ("%lld photo", "%lld photos"), "dateien": ("%lld file", "%lld files"),
           "markierungen": ("%lld mark is", "%lld marks are"),
           "markierte": ("%lld marked photo", "%lld marked photos")},
}

# Schlüssel: ({Sprache: Format}, {Variable: (Zählwort, Argumentposition)})
E = {
    "%lld Bilder (%lld Dateien) in %@ kopiert – %@ lädt sie hoch.": (
        {"de": "{a} ({b}) in %3$@ kopiert – %4$@ lädt sie hoch.", "en": "{a} ({b}) copied to %3$@ – %4$@ is uploading them."},
        {"a": ("bilder", 1), "b": ("dateien", 2)}),
    "%lld Bilder (%lld Dateien) kopiert.": (
        {"de": "{a} ({b}) kopiert.", "en": "{a} ({b}) copied."}, {"a": ("bilder", 1), "b": ("dateien", 2)}),
    "%lld Bilder gefunden (%lld bereits markiert).": (
        {"de": "{a} gefunden (%2$lld bereits markiert).", "en": "{a} found (%2$lld already marked)."}, {"a": ("bilder", 1)}),
    "%lld Bilder gefunden.": ({"de": "{a} gefunden.", "en": "{a} found."}, {"a": ("bilder", 1)}),
    "%lld Bilder in den Papierkorb?": ({"de": "{a} in den Papierkorb?", "en": "Move {a} to the Trash?"}, {"a": ("bilder", 1)}),
    "%lld Datei(en) nicht gelöscht – Rest im Papierkorb.": (
        {"de": "{a} nicht gelöscht – Rest im Papierkorb.", "en": "{a} not deleted – the rest is in the Trash."}, {"a": ("dateien", 1)}),
    "%lld Datei(en) nicht kopiert – Rest ok.": (
        {"de": "{a} nicht kopiert – Rest ok.", "en": "{a} not copied – the rest is fine."}, {"a": ("dateien", 1)}),
    "%lld Dateien kopiert – %lld fehlgeschlagen.": (
        {"de": "{a} kopiert – %2$lld fehlgeschlagen.", "en": "{a} copied – %2$lld failed."}, {"a": ("dateien", 1)}),
    "Abgebrochen – %lld Bilder im Papierkorb.": (
        {"de": "Abgebrochen – {a} im Papierkorb.", "en": "Cancelled – {a} in the Trash."}, {"a": ("bilder", 1)}),
    "Abgebrochen – %lld Dateien kopiert.": (
        {"de": "Abgebrochen – {a} kopiert.", "en": "Cancelled – {a} copied."}, {"a": ("dateien", 1)}),
    "Datenträger wurde entfernt – %lld Markierungen sind gespeichert.": (
        {"de": "Datenträger wurde entfernt – {a} gespeichert.", "en": "The drive was removed – {a} saved."}, {"a": ("markierungen", 1)}),
    "Scan abgebrochen – %lld Bilder geladen.": (
        {"de": "Scan abgebrochen – {a} geladen.", "en": "Scan cancelled – {a} loaded."}, {"a": ("bilder", 1)}),
    "Scanne … %lld Bilder geladen": ({"de": "Scanne … {a} geladen", "en": "Scanning … {a} loaded"}, {"a": ("bilder", 1)}),
    "%lld Dateien gefunden…": ({"de": "{a} gefunden…", "en": "{a} found…"}, {"a": ("dateien", 1)}),
    "%@ · Taste %lld · %lld Bilder · ⌥-Klick: nur diese": (
        {"de": "%1$@ · Taste %2$lld · {a} · ⌥-Klick: nur diese", "en": "%1$@ · key %2$lld · {a} · ⌥-click: only these"}, {"a": ("bilder", 3)}),
    "Ziel für %lld Bilder (inkl. XMP)": (
        {"de": "Ziel für {a} (inkl. XMP)", "en": "Destination for {a} (incl. XMP)"}, {"a": ("bilder", 1)}),
    "Ziel für %lld markierte Bilder (inkl. XMP)": (
        {"de": "Ziel für {a} (inkl. XMP)", "en": "Destination for {a} (incl. XMP)"}, {"a": ("markierte", 1)}),
}

for lang in ("de", "en"):
    out = {}
    for key, (formats, variables) in E.items():
        fmt = formats[lang]
        entry = {}
        for var, (word, pos) in variables.items():
            fmt = fmt.replace("{" + var + "}", "%%%d$#@%s@" % (pos, var))
            one, other = W[lang][word]
            entry[var] = {"NSStringFormatSpecTypeKey": "NSStringPluralRuleType", "NSStringFormatValueTypeKey": "lld",
                          "one": one, "other": other}
        entry["NSStringLocalizedFormatKey"] = fmt
        out[key] = entry
    path = os.path.join(ROOT, "Localization", lang + ".lproj", "Localizable.stringsdict")
    with open(path, "wb") as f:
        plistlib.dump(out, f, sort_keys=True)
    print(path, len(out))
