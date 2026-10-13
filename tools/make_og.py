#!/usr/bin/env python3
"""Erzeugt das Social-Preview-Bild (1200x630) der Download-Seite: App-Icon auf Papier, Titel in Tinte.
Schrift: Inter aus dem Portfolio-Projekt (OFL), Rückfall Helvetica. Aufruf: python3 tools/make_og.py"""
import pathlib
from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "server/site/static/og.png"
ICON = ROOT / "icon/icon_1024.png"
FONTS = [pathlib.Path.home() / "Developer/Business/Portfolio/assets/fonts/InterVariable.woff2",
         pathlib.Path("/System/Library/Fonts/Helvetica.ttc")]

def font(size, weight="Medium"):
    for f in FONTS:
        if f.exists():
            try:
                ft = ImageFont.truetype(str(f), size)
                try: ft.set_variation_by_name(weight)
                except Exception: pass
                return ft
            except Exception:
                continue
    return ImageFont.load_default()

W, H = 1200, 630
img = Image.new("RGB", (W, H), "#F7F7F5")
d = ImageDraw.Draw(img)

icon = Image.open(ICON).convert("RGBA")
icon.thumbnail((360, 360), Image.LANCZOS)
shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
sd = ImageDraw.Draw(shadow)
ix, iy = W - 360 - 72, (H - 360) // 2
sd.rounded_rectangle((ix + 8, iy + 28, ix + 352, iy + 372), 80, fill=(0, 0, 0, 46))
from PIL import ImageFilter
shadow = shadow.filter(ImageFilter.GaussianBlur(28))
img.paste(shadow, (0, 0), shadow)
img.paste(icon, (ix, iy), icon)

d.line((110, 204, 134, 204), fill="#0A0A0A", width=2)
d.text((146, 190), "KOSTENLOS · MACOS", font=font(22, "SemiBold"), fill="#6B6B68")
d.text((106, 240), "RAW Select", font=font(104, "Medium"), fill="#0A0A0A")
lead = font(32, "Regular")
for i, line in enumerate(["Bilder sichten auf dem Mac.", "Schnell, offline, nichts wird", "an den Originalen verändert."]):
    d.text((110, 378 + i * 44), line, font=lead, fill="#3D3D3B")
d.text((110, 560), "vfxmedia.ch/rawselect", font=font(24, "Medium"), fill="#0A0A0A")

OUT.parent.mkdir(parents=True, exist_ok=True)
img.save(OUT, optimize=True)
print("→", OUT, img.size)
