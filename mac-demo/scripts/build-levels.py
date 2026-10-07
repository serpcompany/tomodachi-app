#!/usr/bin/env python3
"""Builds Tomo's levels for a language pack (TomoCore/Sources/TomoCore/Resources/languages/<id>.json → "levels") from Wordbank's
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

Japanese goes past 3 with NINJAL's preschool words (幼児語彙: how many of 4 preschoolers used each word) and picture-book
words (絵本語彙: in how many books), CC BY 4.0, with readings and English meanings from JMdict (the snapshot the Zenbu
apps use). Used by all 4 children or in 20+ books → 3さい; 3 children or 10+ books → 4さい; 2 or 5+ → 5さい; 1 or 3+ → 6さい
(common JMdict words only at 6). An assumption to tune: the data has no per-age norms past 3.

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
            "pack": ROOT.parent / f"TomoCore/Sources/TomoCore/Resources/languages/{lang}.json",
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

# ---------- Japanese ages 3–6: NINJAL preschool and picture-book words, with JMdict meanings

def fetch_ninjal():
    import zipfile
    src = json.loads((ROOT / "scripts/sources/ninjal-bev.source.json").read_text())
    cache = ROOT / "build/data-cache/ninjal"
    cache.mkdir(parents=True, exist_ok=True)
    out = {}
    for name, sha in src["files"].items():
        dest = cache / name
        if not dest.exists() or hashlib.sha256(dest.read_bytes()).hexdigest() != sha:
            dest.write_bytes(urllib.request.urlopen(src["base_url"] + name).read())
        if hashlib.sha256(dest.read_bytes()).hexdigest() != sha:
            sys.exit(f"SHA-256 mismatch for {name}")
        with zipfile.ZipFile(dest) as z:
            txt = next(n for n in z.namelist() if n.endswith(name.replace(".zip", ".txt")))
            out[name.replace(".zip", "")] = z.read(txt).decode("utf-8-sig").splitlines()
    return out

def load_jmdict():
    import gzip, os
    src = json.loads((ROOT / "scripts/sources/jmdict.source.json").read_text())
    path = Path(os.environ["ZENBU_MONOREPO"]) / src["path"].split("zenbujapanese-monorepo/", 1)[1] \
        if "ZENBU_MONOREPO" in os.environ else (ROOT.parent / src["path"])
    raw = path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != src["sha256"]:
        sys.exit(f"JMdict at {path} isn't the pinned snapshot")
    cached = ROOT / f"build/data-cache/jmdict-{src['sha256'][:12]}.json"
    if cached.exists():
        return json.loads(cached.read_text())
    xml = gzip.decompress(raw).decode("utf-8")
    ents, idx = [], {}
    for e in re.findall(r"<entry>(.*?)</entry>", xml, re.S):
        keb, reb = re.findall(r"<keb>(.*?)</keb>", e), re.findall(r"<reb>(.*?)</reb>", e)
        pris = re.findall(r"<(?:ke|re)_pri>(.*?)</", e)
        nf = min([int(p[2:]) for p in pris if p.startswith("nf")] or [99])
        glosses, pos, misc = [], [], []
        for sense in re.findall(r"<sense>(.*?)</sense>", e, re.S)[:2]:
            gl = re.findall(r"<gloss>(.*?)</gloss>", sense)
            if gl: glosses.append(gl[0])
            pos += re.findall(r"<pos>&(.*?);</pos>", sense)
            misc += re.findall(r"<misc>&(.*?);</misc>", sense)
        ents.append({"seq": re.search(r"<ent_seq>(\d+)", e).group(1), "keb": keb, "reb": reb, "pri": bool(pris),
                     "score": [0 if {"news1", "ichi1", "spec1"} & set(pris) else 1, nf], "gloss": glosses,
                     "pos": pos, "misc": misc})
        for f in reb + keb: idx.setdefault(f, []).append(len(ents) - 1)
    data = {"ents": ents, "idx": idx}
    cached.write_text(json.dumps(data, ensure_ascii=False))
    return data

NINJAL_POS = {"名": ("n",), "動": ("v",), "形": ("adj-i",), "形動": ("adj-na",), "副": ("adv",), "感": ("int",), "代": ("pn",)}
NINJAL_CATEGORY = {"名": "nouns", "動": "verbs", "形": "adjectives", "形動": "adjectives", "副": "adverbs", "感": "interjections",
                   "代": "pronouns"}
JMDICT_SKIP = {"vulg", "derog", "X", "arch", "obs", "rare", "sens"}

def build_items_ninjal(cdi_items, cur):
    lists, jm = fetch_ninjal(), load_jmdict()
    ents, idx = jm["ents"], jm["idx"]
    cdi = {to_hiragana(it["kana"]) for it in cdi_items}
    fixes, block = cur.get("ninjal", {}), set(cur.get("ninjalExclude", []))

    def split(word):
        w = unicodedata.normalize("NFKC", word)
        k = re.search(r"\(([^)]*)\)", w)
        return to_hiragana(re.split(r"\(", w)[0].strip()), (k.group(1) if k else None), w
    kids, books, kanji = {}, {}, {}
    for row in csv.reader(lists["yojigoi"]):
        if len(row) < 6 or row[1] not in NINJAL_POS: continue
        h, k, _ = split(row[0])
        kids[(h, row[1])] = max(kids.get((h, row[1]), 0), sum(1 for x in row[2:6] if x.strip()))
        if k: kanji[(h, row[1])] = k
    for row in csv.reader(lists["ehongoi"]):
        if len(row) < 5 or row[1] not in NINJAL_POS: continue
        h, k, raw = split(row[0])
        if "人名" in raw or "地名" in raw or not row[4].strip().isdigit(): continue
        books[(h, row[1])] = books.get((h, row[1]), 0) + int(row[4])

    def age(key):
        n, b = kids.get(key, 0), books.get(key, 0)
        return min({4: 3, 3: 4, 2: 5, 1: 6}.get(n, 99), 3 if b >= 20 else 4 if b >= 10 else 5 if b >= 5 else 6 if b >= 3 else 99)

    def match(h, k, pos):
        kat = "".join(chr(ord(c) + 0x60) if "ぁ" <= c <= "ゖ" else c for c in h)
        cands = [ents[i] for i in set(idx.get(h, []) + idx.get(kat, []))]
        cands = [e for e in cands if e["gloss"] and not set(e["misc"]) & JMDICT_SKIP
                 and any(p.startswith(w) for p in e["pos"] for w in NINJAL_POS[pos])]
        if k:
            withk = [e for e in cands if any(k in kb or kb in k for kb in e["keb"])]
            if withk: return min(withk, key=lambda e: e["score"])
        exact = [e for e in cands if h in e["reb"]]           # a native word over a katakana loanword with the same sound
        pool = exact or cands
        return min(pool, key=lambda e: e["score"]) if pool else None

    items, seqs = [], set()
    for key in sorted(set(kids) | set(books), key=lambda k: (age(k), -kids.get(k, 0), -books.get(k, 0), k[0])):
        h, pos = key
        a = age(key)
        if a == 99 or h in cdi or h in block or len(h) < 2 or "," in h or (h.endswith("たち") and len(h) > 3):
            continue
        e = match(h, kanji.get(key), pos)
        if not e or e["seq"] in seqs or (a == 6 and not e["pri"]):
            continue
        seqs.add(e["seq"])
        kana = next((r for r in e["reb"] if to_hiragana(r) == h), e["reb"][0])
        meaning = re.sub(r"\s*\([^)]*\)$", "", e["gloss"][0]).strip()
        fix = fixes.get(kana) or fixes.get(h) or {}
        if fix.get("exclude"): continue
        items.append({"id": "ja:" + slug(kana_to_romaji(kana)), "category": NINJAL_CATEGORY[pos], "head": kana,
                      "kana": kana, "note": None, "meaning": fix.get("meaning", meaning), "uni_lemma": "",
                      "picture": fix.get("picture"), "say_mo": None, "und_mo": None, "band": a,
                      "src": f"ninjal:{kids.get(key, 0)}kids/{books.get(key, 0)}books/jmdict{e['seq']}"})
    return items

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
    if "band" in it: return it["band"]                      # NINJAL words come with their age
    u, s = it["und_mo"], it["say_mo"]
    if (u is not None and u <= 19) or (s is not None and s < 24): return 1
    if s is not None and s < 36: return 2
    return 3

# ---------- levels

def rounds_for(lang, items, pictures_by_band, all_pictures=()):
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
            if len({p["picture"] for p in pool}) < 2:             # an age with few pictures borrows from the others
                pool += [p for p in all_pictures if p["picture"] != it["picture"] and p not in pool]
            other = [p for p in pool if p["category"] != it["category"]]
            h = int(hashlib.sha256(it["id"].encode()).hexdigest(), 16)
            picks = []
            for group in (other, pool):                          # another category first, then anything
                for k in range(len(group)):
                    pic = group[(h + k) % len(group)]["picture"]
                    if pic not in picks: picks.append(pic)
                    if len(picks) == 2: break
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
    if lang == "ja":                                          # past 3: NINJAL words, already in order within each age
        extra = build_items_ninjal(items, cur)
        taken = {it["id"] for it in items}
        for it in extra:
            base, n = it["id"], 2
            while it["id"] in taken: it["id"], n = f"{base}{n}", n + 1
            taken.add(it["id"])
        pictures = {it["meaning"].lower(): it["picture"] for it in items if it.get("picture") and not it.get("need")}
        for it in extra:
            it["picture"] = it.get("picture") or pictures.get(it["meaning"].lower())
        items = items + extra
    pack = json.loads(P["pack"].read_text())
    talking = [l for l in pack["levels"] if l.get("starters")]
    levels = []
    for age in sorted({it["band"] for it in items}):
        group = [it for it in items if it["band"] == age]
        pics = [it for it in group if it.get("picture") and not it.get("need")]
        rounds = rounds_for(lang, group, pics, [it for it in items if it.get("picture") and not it.get("need")])
        if age == 3:
            levels += [dict(l, age=3) for l in talking]
        chunks = [rounds[i:i + LEVEL_SIZE] for i in range(0, len(rounds), LEVEL_SIZE)]
        if len(chunks) > 1 and len(chunks[-1]) < LEVEL_SIZE // 2:   # a short leftover joins the level before it
            leftover = chunks.pop()      # popped first: `chunks[-2] += chunks.pop()` wrote over the level before that
            chunks[-1] += leftover
        levels += [{"age": age, "rounds": c} for c in chunks]
    pack["levels"] = levels
    P["pack"].write_text(json.dumps(pack, ensure_ascii=False, indent=2))
    n = {a: sum(1 for it in items if it["band"] == a) for a in sorted({it["band"] for it in items})}
    pics = sum(1 for it in items if it.get("picture") or it.get("need"))
    print(f"{len(items)} words → {len(levels)} levels (" + ", ".join(f"age {a}: {c}" for a, c in n.items()) + "); "
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
