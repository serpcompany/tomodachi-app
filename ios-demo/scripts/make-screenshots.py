#!/usr/bin/env python3
"""App Store screenshots: each raw simulator capture (6.9", 1320x2868) under a headline on the icon's sky blue.

Usage: make-screenshots.py <raw dir> <out dir>. Raw files and their captions are listed in SHOTS.
Captures come from the tomodachi-max simulator (ios-demo/README.md, "App Store").
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1320, 2868
TOP, BOTTOM = (0x8F, 0xD3, 0xFF), (0x3E, 0x9B, 0xEA)
FONT = "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf"
SHOTS = [
    ("1-ask.png",   "Learn Japanese\nwith a baby chick",   "Tomo talks like a real 1-year-old"),
    ("2-win.png",   "Get it right,\nwatch Tomo grow",       "Every answer counts toward its next birthday"),
    ("3-talk.png",  "From baby words\nto real questions",   "At 3, Tomo starts asking you things"),
    ("4-word.png",  "Tap any word\nto look it up",          "Readings, meanings and the iPhone dictionary"),
    ("5-home.png",  "Tomo waits on your\nHome Screen",      "Widgets show when new words are ready"),
]

def gradient():
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y / (H - 1)
        d.line([(0, y), (W, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)))
    return img

def compose(raw: Path, title: str, sub: str) -> Image.Image:
    img = gradient()
    d = ImageDraw.Draw(img)
    big, small = ImageFont.truetype(FONT, 118), ImageFont.truetype(FONT, 54)
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
    out_dir.mkdir(parents=True, exist_ok=True)
    for i, (name, title, sub) in enumerate(SHOTS, 1):
        compose(raw_dir / name, title, sub).save(out_dir / f"{i:02d}-{Path(name).stem}.png")
        print("wrote", out_dir / f"{i:02d}-{Path(name).stem}.png")
