#!/usr/bin/env python3
"""Build the app icon and menu bar icon from renders of the real character.

  1. TOMO_RENDER_ICON=/tmp/tomo-icon build/Build/Products/Debug/Tomodachi.app/Contents/MacOS/Tomodachi
  2. python3 scripts/make-icons.py /tmp/tomo-icon      (from mac-demo/)

Writes NotchBuddy/Assets.xcassets/AppIcon.appiconset/*.png and MenuBarIcon.imageset/*.png.
Needs Pillow (pip install pillow).
"""
import sys
from pathlib import Path
from PIL import Image

src = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/tomo-icon")
assets = Path(__file__).resolve().parent.parent / "NotchBuddy" / "Assets.xcassets"

# App icon: every size the asset catalog lists.
icon = Image.open(src / "icon-1024.png").convert("RGBA")
for pt in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        px = pt * scale
        name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"
        icon.resize((px, px), Image.LANCZOS).save(assets / "AppIcon.appiconset" / name)

# Menu bar: black silhouette with the eyes cut out (a template image macOS tints).
tomo = Image.open(src / "tomo-1024.png").convert("RGBA")
w, h = tomo.size
mask = Image.new("L", (w, h), 0)
tp, mp = tomo.load(), mask.load()
for y in range(h):
    for x in range(w):
        r, g, b, a = tp[x, y]
        dark_eye = a > 200 and r + g + b < 160
        mp[x, y] = 0 if dark_eye else a
bbox = mask.getbbox()
mask = mask.crop(bbox)
for scale, name in ((1, "menubar.png"), (2, "menubar@2x.png"), (3, "menubar@3x.png")):
    cw, ch = 24 * scale, 18 * scale          # 24×18 pt canvas, as AppDelegate expects
    th = ch - 1 * scale                      # 1 pt breathing room
    tw = round(mask.width * th / mask.height)
    m = mask.resize((tw, th), Image.LANCZOS)
    out = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    glyph = Image.new("RGBA", (tw, th), (0, 0, 0, 255))
    glyph.putalpha(m)
    out.paste(glyph, ((cw - tw) // 2, (ch - th) // 2), glyph)
    out.save(assets / "MenuBarIcon.imageset" / name)
print("icons written to", assets)
