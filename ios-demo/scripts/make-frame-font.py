#!/usr/bin/env python3
"""Tomo's moving picture on the Lock Screen, as a font.

iOS draws a Live Activity once and only keeps its timers ticking. So the card shows a timer that counts
seconds, set in a font whose digits 0–9 are ten frames of Tomo: the last digit changes every second, and
Tomo moves. The frames are rendered from Tomo's own drawing code (TOMO_RENDER_CARD_FRAMES on the Mac app);
this script packs them into an Apple bitmap font (sbix). The colon is empty. Dashes are Tomo at rest (frame
0): after a while on the Lock Screen iOS stops ticking seconds and shows "1:--", and Tomo then holds still
instead of turning into two dashes.

Usage: make-frame-font.py <frames root> <out dir>
  <frames root> is what TOMO_RENDER_CARD_FRAMES wrote: ready-0 … ready-2 and sleep-0 … sleep-2, each with
  frame-0.png … frame-9.png. Writes TomoReady0.ttf … TomoSleep2.ttf (family names match the file names).
Needs fontTools and Pillow (pip install fonttools pillow).
"""
import sys
from pathlib import Path
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import newTable
from fontTools.ttLib.tables import sbixGlyph, sbixStrike
from PIL import Image

UPM = 1000
DIGITS = [f"d{i}" for i in range(10)]
REST = "rest"
# Hyphen, the Unicode hyphens and dashes, and minus: whichever iOS uses for hidden seconds.
DASHES = [0x2D, 0x2010, 0x2011, 0x2012, 0x2013, 0x2014, 0x2015, 0x2212]

def build(frames: Path, family: str, out: Path):
    pngs = [frames / f"frame-{i}.png" for i in range(10)]
    size = Image.open(pngs[0]).size[0]
    order = [".notdef", "space", "colon", REST] + DIGITS
    fb = FontBuilder(UPM, isTTF=True)
    fb.setupGlyphOrder(order)
    cmap = {0x20: "space", 0x3A: "colon"}
    cmap.update({0x30 + i: DIGITS[i] for i in range(10)})
    cmap.update({c: REST for c in DASHES})
    fb.setupCharacterMap(cmap)

    def rect():
        pen = TTGlyphPen(None)
        pen.moveTo((0, 0)); pen.lineTo((0, UPM)); pen.lineTo((UPM, UPM)); pen.lineTo((UPM, 0)); pen.closePath()
        return pen.glyph()
    empty = TTGlyphPen(None).glyph()
    fb.setupGlyf({".notdef": empty, "space": empty, "colon": empty, REST: rect(), **{d: rect() for d in DIGITS}})
    # Digits are one em wide; the colon takes no room, so the last digit always sits at the trailing edge.
    fb.setupHorizontalMetrics({".notdef": (0, 0), "space": (0, 0), "colon": (0, 0), REST: (UPM, 0),
                               **{d: (UPM, 0) for d in DIGITS}})
    fb.setupHorizontalHeader(ascent=UPM, descent=0)
    fb.setupNameTable({"familyName": family, "styleName": "Regular", "uniqueFontIdentifier": family, "fullName": family, "psName": family, "version": "Version 1.0"})
    fb.setupOS2(sTypoAscender=UPM, sTypoDescender=0, usWinAscent=UPM, usWinDescent=0)
    fb.setupPost()

    sbix = newTable("sbix")
    strike = sbixStrike.Strike(ppem=size, resolution=72)
    for name in order:
        g = sbixGlyph.Glyph(glyphName=name)
        if name in DIGITS or name == REST:
            frame = 0 if name == REST else DIGITS.index(name)
            g = sbixGlyph.Glyph(glyphName=name, graphicType="png ", originOffsetX=0, originOffsetY=0,
                                imageData=pngs[frame].read_bytes())
        strike.glyphs[name] = g
    sbix.strikes[size] = strike
    fb.font["sbix"] = sbix
    out.parent.mkdir(parents=True, exist_ok=True)
    fb.save(str(out))
    print("wrote", out, f"({out.stat().st_size // 1024} KB)")

if __name__ == "__main__":
    root, out = Path(sys.argv[1]), Path(sys.argv[2])
    for mood in ("ready", "sleep"):
        for growth in range(3):
            family = f"Tomo{mood.capitalize()}{growth}"
            build(root / f"{mood}-{growth}", family, out / f"{family}.ttf")
