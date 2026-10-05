#!/usr/bin/env python3
"""Builds Tomo's levels for a language pack (NotchBuddy/Resources/languages/<id>.json → "levels") from Wordbank's
CDI data: the words toddlers understand and say, and when.

  python3 mac-demo/scripts/build-levels.py ja            # rebuild ja.json's levels
  python3 mac-demo/scripts/build-levels.py en --review   # also write build/data-cache/en-review.tsv to curate

Sources are pinned in scripts/sources/wordbank-<language>.source.json (commit and SHA-256 per file); downloads are
cached in mac-demo/build/data-cache/ (never committed). Hand curation (pictures, meaning fixes, exclusions, needs,
translations) is in scripts/data/<id>-curation.json. The talking level (conversation openers) is kept as it is.

How a word gets its age:
  - understand: the first month when half of children understand it (Words & Gestures)
  - say:        the first month when half of children say it (Words & Sentences)
  1さい = understood by half of children by 19 months, or said before 24 months · 2さい = said at 24–35 months ·
  3さい = later, or never by half of the children. Each age's words, earliest first, become levels of LEVEL_SIZE words.

English is for learners who speak Japanese: each word's Japanese meaning comes from the Japanese CDI word for the same
concept (Wordbank's uni_lemma, after the Japanese curation), or from "ja" in en-curation.json.
"""
import csv, hashlib, json, re, sys, unicodedata, urllib.parse, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent              # mac-demo/
LEVEL_SIZE = 10
LANGS = {
    "ja": {
        "source": "wordbank-japanese", "ws_instrument": "[Japanese_WS].csv", "wg_instrument": "[Japanese_WG].csv",
        "ws": [{"data": "JapaneseWS_Tsuji_data.csv"}, {"data": "JapaneseWS_Hagihara_data.csv"},
               {"data": "JapaneseWS_Minagawa_data.csv"}],
        "wg": [{"data": "JapaneseWG_Tsuji_data.csv"}],
    },
    "en": {
        "source": "wordbank-english", "ws_instrument": "[English_WS].csv", "wg_instrument": "[English_WG].csv",
        "ws": [{"data": "EnglishWS_Marchman_Norming_data.csv", "fields": "EnglishWS_Marchman_Norming_fields.csv",
                "values": "EnglishWS_Marchman_Norming_values.csv"},
               {"data": "EnglishWS_Marchman_Norming2_data.csv", "fields": "EnglishWS_Marchman_Norming2_fields.csv",
                "values": "EnglishWS_Marchman_Norming2_values.csv"}],
        "wg": [{"data": "EnglishWG_Marchman_Norming2_data.csv", "fields": "EnglishWG_Marchman_Norming2_fields.csv",
                "values": "EnglishWG_Marchman_Norming2_values.csv"}],
    },
}

def paths(lang):
    return {"source": ROOT / f"scripts/sources/{LANGS[lang]['source']}.source.json",
            "curation": ROOT / f"scripts/data/{lang}-curation.json",
            "pack": ROOT / f"NotchBuddy/Resources/languages/{lang}.json",
            "cache": ROOT / f"build/data-cache/{LANGS[lang]['source']}"}

# ---------- sources

def fetch(lang):
    src = json.loads(paths(lang)["source"].read_text())
    cache = paths(lang)["cache"]
    cache.mkdir(parents=True, exist_ok=True)
    out = {}
    for path, sha in src["files"].items():
        dest = cache / Path(path).name
        if not dest.exists() or hashlib.sha256(dest.read_bytes()).hexdigest() != sha:
            url = f"https://raw.githubusercontent.com/langcog/wordbank/{src['commit']}/{urllib.parse.quote(path)}"
            dest.write_bytes(urllib.request.urlopen(url).read())
        got = hashlib.sha256(dest.read_bytes()).hexdigest()
        if got != sha:
            sys.exit(f"SHA-256 mismatch for {path}: {got}")
        out[Path(path).name] = dest
    return out

def instrument(path):
    return {r["itemID"]: r for r in csv.DictReader(open(path, encoding="utf-8-sig")) if r["type"] == "word"}

def half_month(datasets, files, items, value):
    """First month (3-month window, ≥15 children) when at least half of children have `value` for each item.
    A dataset with a fields file maps item ids to its own column names and age column; a values file maps its codes
    ("1", "1p", "produces") to "produces" / "understands"."""
    counts = {i: {} for i in items}
    for ds in datasets:
        colmap, agecol, valmap = {i: i for i in items}, None, None
        if "fields" in ds:
            colmap = {}
            for r in csv.DictReader(open(files[ds["fields"]], encoding="utf-8-sig")):
                if r.get("field") == "data_age": agecol = r["column"]
                if r.get("group") == "item" and r.get("type") == "word" and r["field"] in items:
                    colmap[r["field"]] = r["column"]
        if "values" in ds:
            valmap = {r["data_value"]: r["value"] for r in csv.DictReader(open(files[ds["values"]], encoding="utf-8-sig"))
                      if r["type"] == "word"}
        for r in csv.DictReader(open(files[ds["data"]], encoding="utf-8-sig")):
            try:
                m = int(float((r.get(agecol) if agecol else None) or r.get("age_mo") or r.get("age") or 0))
            except ValueError:
                continue
            for i, col in colmap.items():
                v = r.get(col)
                if v is None:
                    continue
                if valmap is not None: v = valmap.get(v, v)
                hit = v == value or (value == "understands" and v == "produces")
                c = counts[i].setdefault(m, [0, 0])
                c[0] += hit
                c[1] += 1
    out = {}
    for i, months in counts.items():
        out[i] = None
        for m in sorted(months):
            win = [months[x] for x in (m - 1, m, m + 1) if x in months]
            n = sum(w[1] for w in win)
            if n >= 15 and sum(w[0] for w in win) / n >= 0.5:
                out[i] = m
                break
    return out

# ---------- kana and romaji

ROMAJI = {
    "kya": "きゃ", "kyu": "きゅ", "kyo": "きょ", "sha": "しゃ", "shu": "しゅ", "sho": "しょ", "sya": "しゃ", "syu": "しゅ",
    "syo": "しょ", "cha": "ちゃ", "chu": "ちゅ", "cho": "ちょ", "tya": "ちゃ", "tyu": "ちゅ", "tyo": "ちょ", "nya": "にゃ",
    "nyu": "にゅ", "nyo": "にょ", "hya": "ひゃ", "hyu": "ひゅ", "hyo": "ひょ", "mya": "みゃ", "myu": "みゅ", "myo": "みょ",
    "rya": "りゃ", "ryu": "りゅ", "ryo": "りょ", "gya": "ぎゃ", "gyu": "ぎゅ", "gyo": "ぎょ", "ja": "じゃ", "ju": "じゅ",
    "jo": "じょ", "zya": "じゃ", "zyu": "じゅ", "zyo": "じょ", "bya": "びゃ", "byu": "びゅ", "byo": "びょ", "pya": "ぴゃ",
    "pyu": "ぴゅ", "pyo": "ぴょ", "cya": "ちゃ", "cyu": "ちゅ", "cyo": "ちょ", "jya": "じゃ", "jyu": "じゅ", "jyo": "じょ",
    "shi": "し", "chi": "ち", "tsu": "つ", "si": "し", "ti": "ち", "tu": "つ", "fu": "ふ",
    "hu": "ふ", "ji": "じ", "zi": "じ", "di": "ぢ", "du": "づ",
    "ka": "か", "ki": "き", "ku": "く", "ke": "け", "ko": "こ", "sa": "さ", "su": "す", "se": "せ", "so": "そ",
    "ta": "た", "te": "て", "to": "と", "na": "な", "ni": "に", "nu": "ぬ", "ne": "ね", "no": "の", "ha": "は", "hi": "ひ",
    "he": "へ", "ho": "ほ", "ma": "ま", "mi": "み", "mu": "む", "me": "め", "mo": "も", "ya": "や", "yu": "ゆ", "yo": "よ",
    "ra": "ら", "ri": "り", "ru": "る", "re": "れ", "ro": "ろ", "wa": "わ", "wo": "を", "ga": "が", "gi": "ぎ", "gu": "ぐ",
    "ge": "げ", "go": "ご", "za": "ざ", "zu": "ず", "ze": "ぜ", "zo": "ぞ", "da": "だ", "de": "で", "do": "ど", "ba": "ば",
    "bi": "び", "bu": "ぶ", "be": "べ", "bo": "ぼ", "pa": "ぱ", "pi": "ぴ", "pu": "ぷ", "pe": "ぺ", "po": "ぽ",
    "a": "あ", "i": "い", "u": "う", "e": "え", "o": "お",
}

def romaji_to_kana(s):
    s = s.lower().replace("-", "").replace("'", "")
    out, i = "", 0
    while i < len(s):
        if i + 1 < len(s) and s[i] == s[i + 1] and s[i] not in "aeioun":
            out += "っ"; i += 1; continue
        if s[i] == "n" and (i + 1 == len(s) or s[i + 1] not in "aeiouy"):
            out += "ん"; i += 1; continue
        for n in (3, 2, 1):
            if s[i:i + n] in ROMAJI:
                out += ROMAJI[s[i:i + n]]; i += n; break
        else:
            return None                                     # not convertible: curate by hand
    return out

KANA_ROMAJI = {v: k for k, v in ROMAJI.items() if not re.match(r"^(s[yi]|t[iuy]|z[iy]|hu|d[iu])", k) or k in ("su",)}
KANA_ROMAJI.update({"し": "shi", "ち": "chi", "つ": "tsu", "ふ": "fu", "じ": "ji", "しゃ": "sha", "しゅ": "shu",
                    "しょ": "sho", "ちゃ": "cha", "ちゅ": "chu", "ちょ": "cho", "じゃ": "ja", "じゅ": "ju", "じょ": "jo",
                    "を": "o", "ゃ": "ya", "ゅ": "yu", "ょ": "yo", "ぁ": "a", "ぃ": "i", "ぅ": "u", "ぇ": "e", "ぉ": "o",
                    "ゔ": "vu", "ぢ": "ji", "づ": "zu"})
MACRON = {"a": "ā", "i": "ī", "u": "ū", "e": "ē", "o": "ō"}

def to_hiragana(s):
    return "".join(chr(ord(c) - 0x60) if "ァ" <= c <= "ヶ" else c for c in s)

def kana_to_romaji(s):
    h, out, i = to_hiragana(s), "", 0
    while i < len(h):
        c = h[i]
        if c == "っ" and i + 1 < len(h):
            nxt = kana_to_romaji(h[i + 1:i + 3])[:1]
            out += "t" if nxt == "c" else nxt; i += 1; continue
        if c == "ー":
            if out and out[-1] in MACRON: out = out[:-1] + MACRON[out[-1]]
            i += 1; continue
        if c == "ん":
            out += "n"; i += 1; continue
        if h[i:i + 2] in KANA_ROMAJI:
            out += KANA_ROMAJI[h[i:i + 2]]; i += 2; continue
        out += KANA_ROMAJI.get(c, c); i += 1
    return out

KANJI = re.compile(r"[一-鿿々]")

# ---------- items

def clean_meaning(r):
    m = (r["uni_lemma"] or r["gloss"] or "").strip().replace("_", " ")
    m = re.sub(r"\s*\((object|action|question|place|food|beverage|animal|description)\)", "", m)
    return m[:1].lower() + m[1:] if m and not m[:2].isupper() else m

def head_and_note(definition):
    d = unicodedata.normalize("NFKC", definition.strip())       # full-width parens, half-width katakana
    if d.startswith("("):                                   # （イナイイナイ）バー → イナイイナイバー
        d = d.replace("(", "").replace(")", "")
    head = re.split(r"\s*\(", d)[0].split("・")[0].strip()
    note = re.search(r"\(([^)]*)\)", d)
    return head, note.group(1).strip() if note else None

def slug(s):
    return re.sub(r"[^a-z0-9]+", "", s.lower())

def build_items_ja(files, cur, ages=True):
    L = LANGS["ja"]
    ws = instrument(files[L["ws_instrument"]])
    wg = instrument(files[L["wg_instrument"]])
    say = half_month(L["ws"], files, ws, "produces") if ages else {}
    und = half_month(L["wg"], files, wg, "understands") if ages else {}
    wg_by_romaji = {slug(r["definition_ja2"]): k for k, r in wg.items()}
    items, by_head = [], {}
    rows = [(k, r, "ws") for k, r in ws.items()]
    ws_romaji = {slug(r["definition_ja2"]) for r in ws.values()}
    rows += [(k, r, "wg") for k, r in wg.items() if slug(r["definition_ja2"]) not in ws_romaji]
    for key, r, form in rows:
        head, note = head_and_note(r["definition"])
        romaji_src = r["definition_ja2"].split("_")[0]
        kana = head if not KANJI.search(head) else romaji_to_kana(romaji_src)
        iid = "ja:" + slug(romaji_src)
        u = und.get(wg_by_romaji.get(slug(r["definition_ja2"]))) if form == "ws" else und.get(key)
        s = say.get(key) if form == "ws" else None
        it = {"id": iid, "category": r["category"], "head": head, "kana": kana, "note": note,
              "meaning": clean_meaning(r), "uni_lemma": (r["uni_lemma"] or "").strip().lower(),
              "say_mo": s, "und_mo": u, "src": f"{form}:{key}"}
        items.append(it)
        by_head.setdefault(to_hiragana(head), it)
    # unique ids
    seen = {}
    for it in items:
        n = seen.get(it["id"], 0)
        seen[it["id"]] = n + 1
        if n: it["id"] += str(n + 1)
    # curation
    exclude = set(cur.get("exclude", []))
    items = [it for it in items if it["id"] not in exclude and it["head"] not in exclude]
    missing = []
    for it in items:
        o = cur.get("items", {}).get(it["id"], {})
        for k in ("kana", "meaning", "picture", "need", "grownUp", "category"):
            if k in o: it[k] = o[k]
        if it["kana"] is None:
            missing.append(f"{it['id']} ({it['head']})")
        # baby words: the note is the grown-up word (ワンワン (犬) → いぬ（犬）)
        if "grownUp" not in it and it["category"] == "sounds" and it["note"]:
            adult = by_head.get(to_hiragana(it["note"]))
            it["grownUp"] = f"{adult['kana']}（{it['note']}）" if adult and adult["kana"] != it["note"] else it["note"]
    if missing:
        sys.exit("No kana (add \"kana\" in ja-curation.json): " + ", ".join(missing))
    return items

def build_items_en(files, cur):
    L = LANGS["en"]
    ws = instrument(files[L["ws_instrument"]])
    wg = instrument(files[L["wg_instrument"]])
    say = half_month(L["ws"], files, ws, "produces")
    und = half_month(L["wg"], files, wg, "understands")
    # Japanese meanings: the Japanese CDI word for the same concept, matched on the curated English meaning first
    ja_files = fetch("ja")
    ja_items = build_items_ja(ja_files, json.loads(paths("ja")["curation"].read_text()), ages=False)
    ja_by_meaning, ja_by_lemma = {}, {}
    for it in ja_items:
        ja_by_meaning.setdefault(it["meaning"].lower(), it)
        if it["uni_lemma"]: ja_by_lemma.setdefault(it["uni_lemma"], it)
    exclude, excats = set(cur.get("exclude", [])), set(cur.get("excludeCategories", []))
    wg_by_def = {r["definition"].strip(): k for k, r in wg.items()}
    items, missing = [], []
    rows = [(k, r, "ws") for k, r in ws.items()]
    rows += [(k, r, "wg") for k, r in wg.items() if r["definition"].strip() not in {x["definition"].strip() for x in ws.values()}]
    for key, r, form in rows:
        d = r["definition"].strip()
        if d in exclude or r["category"] in excats:
            continue
        head = re.sub(r"\s*\(.*?\)", "", d).replace("*", "").split("/")[0].strip()
        iid = "en:" + slug(head)
        lemma = (r["uni_lemma"] or "").strip().lower()
        ja = ja_by_meaning.get(lemma) or ja_by_lemma.get(lemma)
        it = {"id": iid, "category": r["category"], "head": head, "definition": d, "uni_lemma": lemma,
              "ja": ja["head"] if ja else None, "picture": ja.get("picture") if ja else None,
              "say_mo": say.get(key) if form == "ws" else None,
              "und_mo": und.get(wg_by_def.get(d)) if form == "ws" else und.get(key)}
        items.append(it)
    seen = {}
    for it in items:
        n = seen.get(it["id"], 0)
        seen[it["id"]] = n + 1
        if n: it["id"] += str(n + 1)
    items = [it for it in items if it["id"] not in exclude]
    for it in items:
        o = cur.get("items", {}).get(it["id"], {})
        for k in ("ja", "picture", "need", "grownUp", "category", "say"):
            if k in o: it[k] = o[k]
        if not it["ja"]:
            missing.append(f"{it['id']} ({it['definition']})")
    if missing:
        sys.exit(f"No Japanese meaning for {len(missing)} words (add \"ja\" in en-curation.json): " + ", ".join(missing))
    return items

def band(it):
    u, s = it["und_mo"], it["say_mo"]
    if (u is not None and u <= 19) or (s is not None and s < 24): return 1
    if s is not None and s < 36: return 2
    return 3

# ---------- levels

def rounds_for(lang, items, pictures_by_band):
    out = []
    for it in items:
        if lang == "ja":
            say = it["kana"] + ("？" if it["category"] == "question_words" else "！")
            r = {"id": it["id"], "say": say, "romanization": kana_to_romaji(it["kana"]), "meaning": {"en": it["meaning"]}}
        else:
            word = it.get("say") or it["head"]
            say = word[:1].upper() + word[1:] + ("?" if it["category"] == "question_words" else "!")
            r = {"id": it["id"], "say": say, "meaning": {"en": it["head"], "ja": it["ja"]}}
        r.update({"grownUp": it.get("grownUp"), "category": it["category"]})
        if it.get("need"):
            r["need"] = it["need"]
        elif it.get("picture"):
            pool = [p for p in pictures_by_band if p["picture"] != it["picture"] and p["id"] != it["id"]]
            other = [p for p in pool if p["category"] != it["category"]] or pool
            h = int(hashlib.sha256(it["id"].encode()).hexdigest(), 16)
            picks = []
            for k in range(len(other)):
                p = other[(h + k * 7919) % len(other)]
                if p["picture"] not in picks: picks.append(p["picture"])
                if len(picks) == 2: break
            choices = picks + [it["picture"]]
            pos = h % 3
            choices[pos], choices[2] = choices[2], choices[pos]
            r["answer"], r["choices"] = it["picture"], choices
        r["praise"] = say
        out.append({k: v for k, v in r.items() if v is not None})
    return out

def main():
    lang = next((a for a in sys.argv[1:] if a in LANGS), None) or sys.exit("usage: build-levels.py ja|en [--review]")
    P = paths(lang)
    cur = json.loads(P["curation"].read_text())
    items = build_items_ja(fetch(lang), cur) if lang == "ja" else build_items_en(fetch(lang), cur)
    for it in items: it["band"] = band(it)
    order = lambda it: (it["band"], it["und_mo"] if it["und_mo"] is not None else 99,
                        it["say_mo"] if it["say_mo"] is not None else 99, it["id"])
    items.sort(key=order)
    pack = json.loads(P["pack"].read_text())
    talking = [l for l in pack["levels"] if l.get("starters")]
    levels = []
    for age in (1, 2, 3):
        group = [it for it in items if it["band"] == age]
        pics = [it for it in group if it.get("picture") and not it.get("need")]
        rounds = rounds_for(lang, group, pics)
        if age == 3:
            levels += [dict(l, age=3) for l in talking]
        chunks = [rounds[i:i + LEVEL_SIZE] for i in range(0, len(rounds), LEVEL_SIZE)]
        if len(chunks) > 1 and len(chunks[-1]) < LEVEL_SIZE // 2:   # a short leftover joins the level before it
            chunks[-2] += chunks.pop()
        levels += [{"age": age, "rounds": c} for c in chunks]
    pack["levels"] = levels
    P["pack"].write_text(json.dumps(pack, ensure_ascii=False, indent=2))
    n = {a: sum(1 for it in items if it["band"] == a) for a in (1, 2, 3)}
    pics = sum(1 for it in items if it.get("picture") or it.get("need"))
    print(f"{len(items)} words → {len(levels)} levels (1さい {n[1]}, 2さい {n[2]}, 3さい {n[3]}); "
          f"{pics} with a picture or action, {len(items) - pics} asked by meaning")
    if "--review" in sys.argv:
        path = P["cache"].parent / f"{lang}-review.tsv"
        with open(path, "w") as f:
            f.write("id\tband\tsay_mo\tund_mo\tcategory\thead\treading\tmeaning\tpicture\tgrownUp\n")
            for it in items:
                reading = kana_to_romaji(it["kana"]) if lang == "ja" else ""
                meaning = it["meaning"] if lang == "ja" else it["ja"]
                f.write("\t".join(str(x) for x in (it["id"], it["band"], it["say_mo"], it["und_mo"], it["category"],
                        it["head"], reading, meaning, it.get("picture") or it.get("need") or "",
                        it.get("grownUp") or "")) + "\n")
        print(f"review: {path}")

if __name__ == "__main__":
    main()
