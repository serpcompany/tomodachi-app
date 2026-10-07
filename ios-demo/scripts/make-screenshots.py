#!/usr/bin/env python3
"""App Store screenshots: each raw simulator capture (6.9", 1320x2868) under a headline on the icon's sky blue.

Usage: make-screenshots.py <raw dir> <out dir>. Writes <out dir>/6.9/ (1320x2868) and <out dir>/6.3/ (1206x2622,
the same images scaled; the two sizes differ in shape by under 0.1%). The out dir is ios-demo/metadata/screenshots.

Raw files and their captions are in SHOTS. They're captured headless on an iPhone 17 Pro Max simulator, each from
seeded progress or a first-run step: ios-demo/app-store.md has the steps.
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1320, 2868
SMALL = (1206, 2622)
TOP, BOTTOM = (0x8F, 0xD3, 0xFF), (0x3E, 0x9B, 0xEA)
FONT = "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf"
# (raw file, headline, subline). How each raw file is captured: ios-demo/app-store.md.
SHOTS = [
    ("1-hatch.png",          "Hatch a Tomo\nall your own",    "It speaks Japanese, one baby word at a time"),
    ("2-round.png",          "Show Tomo\nyou understood",     "Tap the picture: nothing to type or say"),
    ("3-win.png",            "Get it right,\nwatch Tomo grow", "Words come back over hours and days"),
    ("4-tomo.png",           "Watch it\ngrow up",             "A new shape at every birthday"),
    ("5-words.png",          "Every word\nin one place",      "What Tomo knows, and when it comes back"),
    ("6-comes-to-you.png",   "Tomo comes\nto you",            "A reminder when words are ready, quiet at night"),
]

def gradient():
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y / (H - 1)
        d.line([(0, y), (W, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)))
    return img

def fitted(d, text, size, width):
    """The font at `size`, smaller until every line of `text` fits `width`."""
    while True:
        font = ImageFont.truetype(FONT, size)
        if max(d.textlength(line, font=font) for line in text.split("\n")) <= width or size <= 20:
            return font
        size -= 2

def compose(raw: Path, title: str, sub: str) -> Image.Image:
    img = gradient()
    d = ImageDraw.Draw(img)
    big, small = fitted(d, title, 118, W - 120), fitted(d, sub, 54, W - 120)
    y = 150
    for line in title.split("\n"):
        w = d.textlength(line, font=big)
        d.text(((W - w) / 2, y), line, font=big, fill="white")
        y += 140
    w = d.textlength(sub, font=small)
    d.text(((W - w) / 2, y + 20), sub, font=small, fill=(255, 255, 255, 230))
    # The phone screen, scaled, with rounded corners and a soft shadow
    shot = Image.open(raw).convert("RGB")
    sw = int(W * 0.78); sh = int(shot.height * sw / shot.width)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, sw, sh], radius=96, fill=255)
    x0, y0 = (W - sw) // 2, y + 140
    shadow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(shadow).rounded_rectangle([x0, y0 + 24, x0 + sw, y0 + sh + 24], radius=96, fill=110)
    shadow = shadow.filter(ImageFilter.GaussianBlur(40))
    img.paste((20, 60, 110), (0, 0), shadow)
    img.paste(shot, (x0, y0), mask)
    return img

if __name__ == "__main__":
    raw_dir, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
    for size in ("6.9", "6.3"):
        (out_dir / size).mkdir(parents=True, exist_ok=True)
    for i, (name, title, sub) in enumerate(SHOTS, 1):
        img = compose(raw_dir / name, title, sub)
        file = f"{i:02d}-{Path(name).stem.split('-', 1)[1]}.png"
        img.save(out_dir / "6.9" / file)
        img.resize(SMALL, Image.LANCZOS).save(out_dir / "6.3" / file)
        print("wrote", out_dir / "6.9" / file, "and", out_dir / "6.3" / file)
