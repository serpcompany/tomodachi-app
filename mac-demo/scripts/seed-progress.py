#!/usr/bin/env python3
"""Seed saved progress for a test run, so a check starts from a known state (docs/verification.md).

    python3 mac-demo/scripts/seed-progress.py <dir> [--pair en:ja] [--level N] [--age A]
        [--through-level N --stage S --due H] [item=stage=dueHours ...]

<dir> is the run's TOMO_DATA_DIR; it's wiped first. --through-level seeds every item of levels 1..N from
the target pack at stage S, due in H hours. Items listed after the options override those. Example: all of
level 1 just learned, so nothing counts for about an hour (the practice offer):

    python3 mac-demo/scripts/seed-progress.py /tmp/tomo-test --through-level 1 --stage 1 --due 2

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


def level_items(target, through):
    levels = pack(target)["levels"][:through]
    return [x["id"] for level in levels for x in level.get("rounds", []) + level.get("starters", [])]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("dir")
    ap.add_argument("--pair", default="en:ja", help="learner:target, as in Settings (default en:ja)")
    ap.add_argument("--level", type=int, help="Tomo's level (default: --through-level, else 1)")
    ap.add_argument("--age", type=int, default=1)
    ap.add_argument("--through-level", type=int, default=0)
    ap.add_argument("--stage", type=int, default=1)
    ap.add_argument("--due", type=float, default=2, help="hours until due")
    ap.add_argument("items", nargs="*", help="item=stage=dueHours, e.g. ja:mama=3=-1 (due an hour ago)")
    a = ap.parse_args()

    learner, target = a.pair.split(":")
    now = time.time()
    items = {i: (a.stage, a.due) for i in level_items(target, a.through_level)}
    for spec in a.items:
        item, stage, due = spec.split("=")
        items[item] = (int(stage), float(due))

    d = Path(a.dir)
    shutil.rmtree(d, ignore_errors=True)
    d.mkdir(parents=True)
    db = sqlite3.connect(d / "learner.sqlite")
    db.executescript(SCHEMA)
    db.execute("INSERT INTO tomo VALUES (?, ?, ?, ?, ?)",
               (learner, target, now - 5 * 86400, a.level or a.through_level or 1, a.age))
    db.executemany("INSERT INTO item VALUES (?, ?, ?, ?, ?, ?, ?, 3, 0, ?)", [
        (learner, target, item, stage, now + due * 3600, now - 3 * 86400, now - 3600, stage)
        for item, (stage, due) in items.items()])
    db.commit()
    print(f"{d}/learner.sqlite: {learner} → {target}, {len(items)} items")


if __name__ == "__main__":
    main()
