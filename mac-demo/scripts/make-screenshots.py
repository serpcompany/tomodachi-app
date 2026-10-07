#!/usr/bin/env python3
"""Mac App Store screenshots (2880x1800): headless snapshots of Tomo's island and the Tomodachi window, put on a
desktop drawn here (the icon's sky blue, a menu bar and a MacBook notch), under a short headline.

Usage: make-screenshots.py <raw dir> <out dir> (out: mac-demo/metadata/screenshots). Needs Pillow.

The raw files are the app's own snapshots (TOMO_SNAPSHOT_DIR, docs/verification.md), at 2x: the island window
(`snap-NNN.png`, 720x560 pt, centred on the notch) and the Tomodachi window (`window-<screen>-NNN.png`) or the first
run's (`onboarding-NNN.png`). SHOTS says which file each shot uses; mac-demo/app-store.md says how to capture them.
The notch is a 16" MacBook Pro's (185 x 32 pt), the one the island snapshots were taken on.
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 2880, 1800
SCALE = 2                                   # pixels per point
MENU_H = 34 * SCALE                         # the menu bar on a notched MacBook
NOTCH_W, NOTCH_H = 185 * SCALE, 32 * SCALE
TOP, BOTTOM = (0x8F, 0xD3, 0xFF), (0x3E, 0x9B, 0xEA)
HEADLINE = "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf"
SYSTEM = "/System/Library/Fonts/SFNS.ttf"
ICON = Path(__file__).resolve().parents[1] / "NotchBuddy/Assets.xcassets/MenuBarIcon.imageset/menubar@2x.png"

# (out file, headline, subline, island snapshot, window snapshot or None, menus while that app is in front)
FINDER = ["Finder", "File", "Edit", "View", "Go", "Window", "Help"]
APP = ["Tomodachi", "Edit", "View", "Tomo", "Window", "Help"]
SHOTS = [
    ("01-notch", "Tomo lives\nby your notch", "It drops in with a word, then tucks back in",
     "island-round.png", None, FINDER),
    ("02-win", "Get it right,\nwatch Tomo grow", "Words come back over hours and days",
     "island-win.png", None, FINDER),
    ("03-hatch", "Hatch a Tomo\nall your own", "It speaks Japanese, one baby word at a time",
     "island-first-run.png", "first-run.png", APP),
    ("04-tomo", "Watch it\ngrow up", "A new shape at every birthday",
     "island-small.png", "window-tomo.png", APP),
    ("05-words", "Every word\nin one place", "What Tomo knows, and when it comes back",
     "island-small.png", "window-words.png", APP),
]


def font(path, size):
    return ImageFont.truetype(path, size)


def wallpaper():
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y / (H - 1)
        d.line([(0, y), (W, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)))
    # Two soft light blobs, so the desktop isn't flat
    glow = Image.new("L", (W, H), 0)
    g = ImageDraw.Draw(glow)
    g.ellipse([-500, 900, 1300, 2300], fill=70)
    g.ellipse([1900, -300, 3400, 1000], fill=50)
    img.paste((255, 255, 255), (0, 0), glow.filter(ImageFilter.GaussianBlur(220)))
    return img


def menu_bar(img, menus):
    """A translucent menu bar with the front app's menus on the left; Tomo's icon, Wi-Fi, battery and the clock on
    the right; the notch in the middle."""
    bar = Image.new("RGBA", (W, MENU_H), (255, 255, 255, 46))
    img.paste(bar, (0, 0), bar)
    d = ImageDraw.Draw(img)
    cy = MENU_H // 2
    regular, bold = font(SYSTEM, 26), font(SYSTEM, 26)
    try:
        bold.set_variation_by_name("Bold")
    except Exception:
        pass
    x = 40
    d.text((x, cy), "", font=font(SYSTEM, 30), fill="white", anchor="lm")   # the Apple menu
    x += 70
    for i, name in enumerate(menus):
        f = bold if i == 0 else regular
        d.text((x, cy), name, font=f, fill="white", anchor="lm")
        x += d.textlength(name, font=f) + 44
    # Right side, from the right edge in
    x = W - 40
    clock = "Thu Oct 8  9:41 AM"
    d.text((x, cy), clock, font=regular, fill="white", anchor="rm")
    x -= d.textlength(clock, font=regular) + 44
    # Battery
    d.rounded_rectangle([x - 50, cy - 12, x - 4, cy + 12], radius=6, outline="white", width=3)
    d.rounded_rectangle([x - 45, cy - 7, x - 9, cy + 7], radius=3, fill="white")
    d.rounded_rectangle([x, cy - 5, x + 4, cy + 5], radius=2, fill="white")
    x -= 90
    # Wi-Fi: three arcs and a dot
    for r in (24, 16, 8):
        d.arc([x - r, cy + 10 - r, x + r, cy + 10 + r], 225, 315, fill="white", width=4)
    d.ellipse([x - 3, cy + 7, x + 3, cy + 13], fill="white")
    x -= 70
    # Tomodachi's menu bar icon (a template image: draw it white)
    icon = Image.open(ICON).convert("RGBA")
    white = Image.new("RGBA", icon.size, (255, 255, 255, 255))
    white.putalpha(icon.getchannel("A"))
    img.paste(white, (int(x) - icon.width // 2, cy - icon.height // 2), white)
    # The notch, with the small inward curves at its top corners
    n0 = (W - NOTCH_W) // 2
    d.rounded_rectangle([n0, -40, n0 + NOTCH_W, NOTCH_H - 1], radius=22, fill="black")


def wrap(d, text, f, width):
    """`text` in lines no wider than `width`."""
    lines, line = [], ""
    for word in text.split():
        trial = f"{line} {word}".strip()
        if line and d.textlength(trial, font=f) > width:
            lines.append(line)
            line = word
        else:
            line = trial
    return lines + [line]


def headline(img, title, sub, box):
    """The headline and subline, centred in `box` (x0, y0, x1, y1). The headline shrinks to fit; the subline wraps."""
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = box
    width = x1 - x0
    size = 150
    while True:
        big = font(HEADLINE, size)
        if max(d.textlength(line, font=big) for line in title.split("\n")) <= width or size < 40:
            break
        size -= 4
    small = font(HEADLINE, 60)
    lines = [(line, big, int(size * 1.18)) for line in title.split("\n")]
    subs = [(line, small, 76) for line in wrap(d, sub, small, width)]
    total = sum(h for _, _, h in lines) + 40 + sum(h for _, _, h in subs)
    y = y0 + (y1 - y0 - total) // 2
    cx = (x0 + x1) / 2
    shade = Image.new("RGBA", img.size, (0, 0, 0, 0))
    s = ImageDraw.Draw(shade)
    placed = []
    for i, (line, f, h) in enumerate(lines + subs):
        if i == len(lines):
            y += 40
        placed.append((line, f, y))
        y += h
    for line, f, ty in placed:
        s.text((cx, ty + 5), line, font=f, fill=(20, 60, 110, 90), anchor="ma")
    img.paste(shade.filter(ImageFilter.GaussianBlur(8)), (0, 0), shade.filter(ImageFilter.GaussianBlur(8)))
    for line, f, ty in placed:
        d.text((cx, ty), line, font=f, fill="white", anchor="ma")


def window(img, snap, origin, buttons):
    """A window: its content snapshot (full-size content, so the title bar is part of it), with rounded corners, a
    hairline border, the traffic lights (`buttons`: which of close, minimize, zoom are enabled) and a soft shadow."""
    content = Image.open(snap).convert("RGBA")
    base = Image.new("RGBA", content.size, (30, 30, 32, 255))
    content = Image.alpha_composite(base, content)
    w, h = content.size
    radius = 16 * SCALE
    x, y = origin
    shadow = Image.new("L", img.size, 0)
    ImageDraw.Draw(shadow).rounded_rectangle([x, y + 30, x + w, y + h + 30], radius=radius, fill=150)
    img.paste((10, 40, 80), (0, 0), shadow.filter(ImageFilter.GaussianBlur(50)))
    mask = Image.new("L", content.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, h - 1], radius=radius, fill=255)
    d = ImageDraw.Draw(content)
    for i, colour in enumerate([(255, 95, 87), (254, 188, 46), (40, 200, 64)]):
        cx, cy = (20 + 6 + i * 20) * SCALE, 20 * SCALE
        d.ellipse([cx - 12, cy - 12, cx + 12, cy + 12], fill=colour if buttons[i] else (80, 80, 84))
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=radius, outline=(255, 255, 255, 40), width=2)
    img.paste(content, origin, mask)


def compose(raw: Path, title, sub, island, win, menus):
    img = wallpaper()
    menu_bar(img, menus)
    if win:
        snap = Image.open(raw / win)
        w, h = snap.size
        x = W - w - 120
        y = MENU_H + (H - MENU_H - h) // 2 + 20
        # The first run's window can only be closed (TomoOnboardingWindow); the Tomodachi window does all three.
        window(img, raw / win, (x, y), (True, False, False) if win == "first-run.png" else (True, True, True))
        headline(img, title, sub, (80, MENU_H + 200, x - 80, H - 100))
    else:
        headline(img, title, sub, (200, 560, W - 200, H - 120))
    # Tomo's island last: it floats over everything, centred on the notch
    isl = Image.open(raw / island).convert("RGBA")
    img.paste(isl, ((W - isl.width) // 2, 0), isl)
    return img


if __name__ == "__main__":
    raw_dir, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
    out_dir.mkdir(parents=True, exist_ok=True)
    for name, title, sub, island, win, menus in SHOTS:
        compose(raw_dir, title, sub, island, win, menus).save(out_dir / f"{name}.png")
        print("wrote", out_dir / f"{name}.png")
