#!/usr/bin/env python3
"""Seed saved progress for a test run, so a check starts from a known state (docs/verification.md).

    python3 mac-demo/scripts/seed-progress.py <dir> [--pair en:ja] [--level N] [--age A]
        [--through-level N --stage S --due H] [--edge N] [--days D] [item=stage=dueHours[=peak] ...]

<dir> is the run's TOMO_DATA_DIR; it's wiped first. --through-level seeds every item of levels 1..N from
the target pack at stage S, due in H hours. Items listed after the options override those; a fourth part is
the best stage the word ever reached (a slip: ja:mama=3=40=5). The age defaults to the level's age in the
pack. --days D: Tomo hatched D days ago (default 5), for "Day N together" on the Tomo screen. Example: all
of level 1 just learned, so nothing counts for about an hour (Tomo rests):

    python3 mac-demo/scripts/seed-progress.py /tmp/tomo-test --through-level 1 --stage 1 --due 2

--edge N is one word short of finishing level N: levels 1..N know it (stage 5, not yet halfway to their
review), except level N's last words past the 9 in 10 it needs, at stage 4: the first due now, any other
not yet halfway. One right answer finishes the level, so the level-up (a birthday at an age boundary)
comes on cue:

    python3 mac-demo/scripts/seed-progress.py /tmp/tomo-test --edge 15    # → Lv 16, 2さい
    python3 mac-demo/scripts/seed-progress.py /tmp/tomo-test --edge 60    # → Lv 61, 3さい: talking starts

The owner's Tomo in #89, one word short of level 2 (どうぞ due, いないいないばあ tomorrow):

    python3 mac-demo/scripts/seed-progress.py /tmp/tomo-test --through-level 1 --stage 5 --due 96 \
        ja:douzo=4=-3 ja:inaiinaibaa=4=20

The tables mirror TomoStore.swift; change both together.
"""
import argparse
import json
import shutil
import sqlite3
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

SCHEMA = """
CREATE TABLE tomo (learner TEXT NOT NULL, target TEXT NOT NULL, met_at REAL NOT NULL, level INTEGER NOT NULL,
  age INTEGER NOT NULL, PRIMARY KEY (learner, target));
CREATE TABLE item (learner TEXT NOT NULL, target TEXT NOT NULL, item_id TEXT NOT NULL, stage INTEGER NOT NULL,
  due_at REAL, introduced_at REAL NOT NULL, answered_at REAL NOT NULL, right_count INTEGER NOT NULL,
  wrong_count INTEGER NOT NULL, peak INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (learner, target, item_id));
CREATE TABLE answer (at REAL NOT NULL, learner TEXT NOT NULL, target TEXT NOT NULL, item_id TEXT,
  level INTEGER NOT NULL, mode TEXT NOT NULL, result TEXT NOT NULL, wrong_tries INTEGER NOT NULL,
  hint INTEGER NOT NULL, counted INTEGER NOT NULL, stage_before INTEGER, stage_after INTEGER);
CREATE TABLE growth (at REAL NOT NULL, learner TEXT NOT NULL, target TEXT NOT NULL, kind TEXT NOT NULL,
  value INTEGER NOT NULL);
"""


def pack(target):
    """The target pack, wherever the app keeps its resources."""
    found = [p for p in ROOT.glob(f"**/Resources/languages/{target}.json") if "build" not in p.parts]
    if not found:
        raise SystemExit(f"no pack for {target!r} under {ROOT}")
    return json.loads(found[0].read_text())


def ids(level):
    return [x["id"] for x in level.get("rounds", []) + level.get("starters", []) if x.get("id")]


def level_items(target, through):
    return [i for level in pack(target)["levels"][:through] for i in ids(level)]


# Hours until the next review after reaching a stage; levels 1-2 start faster (TomoSRS in TomoProgress.swift).
HOURS = {1: 4, 2: 8, 3: 23, 4: 47, 5: 167, 6: 335, 7: 719, 8: 2879}
FAST_HOURS = {1: 2, 2: 4, 3: 8, 4: 23}


def wait(stage, level):
    return (FAST_HOURS if level <= 2 else HOURS).get(stage, HOURS.get(stage))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("dir")
    ap.add_argument("--pair", default="en:ja", help="learner:target, as in Settings (default en:ja)")
    ap.add_argument("--level", type=int, help="Tomo's level (default: --through-level, else 1)")
    ap.add_argument("--age", type=int, help="Tomo's age (default: its level's age in the pack)")
    ap.add_argument("--through-level", type=int, default=0)
    ap.add_argument("--edge", type=int, metavar="N", help="one word short of finishing level N (above)")
    ap.add_argument("--stage", type=int, default=1)
    ap.add_argument("--due", type=float, default=2, help="hours until due")
    ap.add_argument("--days", type=float, default=5, help="days since Tomo hatched (default 5)")
    ap.add_argument("items", nargs="*",
                    help="item=stage=dueHours[=peak], e.g. ja:mama=3=-1 (due an hour ago), ja:mama=3=40=5 (slipped)")
    a = ap.parse_args()

    learner, target = a.pair.split(":")
    now = time.time()
    levels = pack(target)["levels"]
    if a.edge:
        a.through_level, a.stage, a.level = a.edge, 5, a.level or a.edge
        a.due = wait(5, a.edge) * 0.9          # 10% of the wait gone: nothing counts early
    items = {i: (a.stage, a.due, a.stage) for i in level_items(target, a.through_level)}
    if a.edge:
        words = ids(levels[a.edge - 1])
        needed = max(1, (len(words) * 9 + 9) // 10)      # TomoProgress.needed(of:)
        short = words[needed - 1:]                         # all but needed - 1 of them know it
        items[short[0]] = (4, -1, 4)
        items.update({i: (4, wait(4, a.edge) * 0.9, 4) for i in short[1:]})
    for spec in a.items:
        item, stage, due, *peak = spec.split("=")
        items[item] = (int(stage), float(due), max(int(stage), int(peak[0]) if peak else 0))

    d = Path(a.dir)
    shutil.rmtree(d, ignore_errors=True)
    d.mkdir(parents=True)
    db = sqlite3.connect(d / "learner.sqlite")
    db.executescript(SCHEMA)
    level = a.level or a.through_level or 1
    age = a.age or levels[min(level, len(levels)) - 1]["age"]
    db.execute("INSERT INTO tomo VALUES (?, ?, ?, ?, ?)", (learner, target, now - a.days * 86400, level, age))
    db.executemany("INSERT INTO item VALUES (?, ?, ?, ?, ?, ?, ?, 3, 0, ?)", [
        (learner, target, item, stage, now + due * 3600, now - min(3, a.days) * 86400, now - 3600, peak)
        for item, (stage, due, peak) in items.items()])
    db.commit()
    print(f"{d}/learner.sqlite: {learner} → {target}, level {level}, age {age}, {len(items)} items")


if __name__ == "__main__":
    main()
