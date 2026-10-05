# Learner data schema: what Tomo remembers about you

Researched 2026-10-03. Answers the question in [#4](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/4) (closed; built as the learner store).

## The answer

Keep an **append-only log** on the Mac in SQLite: visits, turns, and one **evidence** row each time a word, phrase or grammar point is heard (exposure), understood (comprehension), said on request (production), or used freely in a reply Tomo understood (conversation). Everything else is a cache rebuilt from that log: what you "know", what's due for review, and how close Tomo is to its next birthday. Words are keyed by Zenbu's Language Reference ID. Phrases and grammar points get prefixed IDs (`phrase:…`, `grammar:…`), the same trick the iOS app uses for `kanji:`. Spaced repetition uses FSRS, with one card for *understanding* an item and one for *saying* it. Tomo's age is the one learning result that is stored, not recomputed, so Tomo never gets younger when we retune the rules. Syncing later is just uploading log rows that have UUIDv7 IDs: the server ignores duplicates and other devices replay the rows. There are no conflicts, because nothing edits a log row. No audio is ever written. Text the learner typed or said stays on the Mac if they allow it, and is left out of uploads unless they opt in.

## What exists today

- **The demo saves nothing.** Progress is `known: Set<String>` of surface words (`"ワンワン"`, `"いた"`) plus a `goodReplies` counter, and `TomoGame.start()` clears both at every launch.
- **Zenbu iOS keeps learner data on the device.** Known Words is a versioned JSON file with one record per word: Language Reference ID, headword, reading, `known`/`unknown`, `updatedAt`. Marking a word unknown keeps the record "so a later sync can tell a removal from no status". A file from a newer app version opens read-only, and unrecognised status values are kept. Notes and photos still use `WordNoteID`, which ADR 0006 says must move to Language Reference IDs before anything syncs.
- **There is no sync backend yet.** The website's writable D1 database has no tables (empty `schema.ts`, empty migration journal). ADR 0007 puts accounts and learner data in a backend behind a `/v1` API, and ADR 0006 leaves the backend undecided. Accounts are issue #468.
- **Language Reference ID** = the first 16 bytes of SHA-256 of `edrdg.jmdict\0<ent_seq>`, as 32 hex characters (`import_jmdict.py`). I checked 犬 (1258330 → `681bff82…`). The IDs are permanent and never reused. Learner data never uses the JMdict entry number (CONTEXT.md).
- **Every demo word is in JMdict, but JMdict mostly doesn't link baby talk to the grown-up word.** Only くっく has one ("See also 靴"). JMdict tags 159 senses as children's language (`&chn;`), including ワンワン "dog" and ブーブー "car", but Zenbu's importer drops that tag.

| Demo word | ent_seq | Language Reference ID | Grown-up word | Its ID |
|---|---|---|---|---|
| ワンワン | 1149310 | `98926421956765ffed928c296cbdffc9` | 犬 いぬ | `681bff8274391329f3ce9ca80a4e04b0` |
| まんま | 2024490 (飯【まんま】) | `d1ce45df7bf08bde9fba2c2869ae6252` | ご飯 ごはん | `100967afadafc009ae9a18618de4ebcb` |
| ブーブー | 1011120 | `9e27ffb688ffafe504a2acb91f4029c3` | 車 くるま | `77f7e3b032090284623ed627e35cf16a` |
| ニャンニャン | 1648200 | `969ce5933815a34e8a4f883477baca74` | 猫 ねこ | `59e7e7802475b49cbe31f60aff9187af` |
| ねんね | 2009350 | `20f07b89a5640ec959cd4d595d27376a` | 寝る ねる | `3ee73bc74b631954edbad00428460bd4` |
| モーモー | 2123170 | `7274871a49a2ade9163ab0ab3b3a981f` | 牛 うし | `eed8b2639d6446e4472942d2e8559cd0` |
| くっく | 2836993 | `1e7afb2ae36ebf973783d74a35cb4a2a` | 靴 くつ | `c11601455f8593ba5c933728a5332d96` |
| だっこ | 1516410 (抱っこ) | `ec771451f177607b478dce93c5e525ea` | the same word | n/a |

These IDs come from language-data release 2026.10.1 (`LanguageReferenceData.sqlite3`, queried read-only).

## Proposal

### Entities

There are two SQLite files, mirroring how Zenbu keeps read-only, versioned language data apart from learner data.

**Content: `TomoContent.sqlite`** (read-only, ships with the app, has a `content_version`):

1. **Item**: a word, phrase or grammar point Tomo can teach, with headword, reading, the age Tomo starts using it, and a baby-talk flag.
2. **Item link**: baby-talk word → grown-up word (ワンワン → 犬), or phrase → the words in it.
3. **Round** and **round item**: a scripted prompt, and which items it *says*, *tests* and *expects the learner to say*.

**Learner: `learner.sqlite`** (read-write):

4. **Learner**: local ID, Zenbu account ID once signed in, transcript setting.
5. **Tomo**: name and hatch date. "Start over" retires the row and hatches a new one.
6. **Growth**: append-only, one row per birthday, with the rules and numbers that earned it.
7. **Visit**: one drop-in or free-play session.
8. **Turn**: one thing Tomo said and the learner's one answer. A retry after ちがう〜 is a new turn.
9. **Evidence**: one row per item, per kind, per turn. The heart of the model.
10. **Item state** (derived): per-item counts, distinct days, level, milestone dates.
11. **SRS card** (derived): FSRS memory state per item, per skill (`understand`, `say`).
12. **Outbox**: log rows waiting to upload.

### The four kinds of evidence

| Kind | Written when | Result |
|---|---|---|
| `exposure` | Tomo says the item, or shows it (the "grown-ups say: いぬ" card) | `seen` |
| `comprehension` | The learner shows they understood: the right picture, the right action, or a reply that fits the question | `right` / `wrong` |
| `production` | The learner says or types the item when asked for it (これ なに？ → いぬ), or while a hint or reply bubbles are showing | `right` / `unclear` |
| `conversation` | The learner uses the item unprompted, with no hint showing, in a reply Tomo understood | `right` |

Each turn gets at most one of `production` or `conversation` per item, whichever is stronger. `UNIQUE (turn_id, item_id, kind)` makes writes safe to retry. Scripted rounds name their items in content, chosen by hand. Free replies at 3さい have to be split into dictionary words with a tokenizer (the Zenbu app uses Sudachi and Kuromoji), and each row records how its item was matched (`matched_by`). How to judge answers is a separate question: [answer-evaluation.md](answer-evaluation.md).

### SQLite DDL

```sql
-- =====================================================================================
-- TomoContent.sqlite: read-only, ships with the app. SQLite 3.37+ for STRICT (this Mac: 3.54).
-- =====================================================================================
CREATE TABLE content_meta (
  key   TEXT PRIMARY KEY,           -- 'content_version', 'language_data' ('2026.10.1')
  value TEXT NOT NULL
) STRICT;

-- A word's id IS its Language Reference ID (32 lowercase hex). Phrases and grammar points use
-- a prefix, which can't collide with hex (the iOS app does the same with 'kanji:').
CREATE TABLE item (
  id         TEXT PRIMARY KEY,      -- '681bff82…' | 'phrase:wanwan-ita' | 'grammar:te-iru'
  kind       TEXT NOT NULL CHECK (kind IN ('word','phrase','grammar')),
  headword   TEXT NOT NULL,         -- 犬 | ワンワン いた！ | 〜てる
  reading    TEXT NOT NULL,
  meaning_en TEXT NOT NULL,
  first_age  INTEGER NOT NULL,      -- さい at which Tomo starts using it
  baby_talk  INTEGER NOT NULL DEFAULT 0 CHECK (baby_talk IN (0,1))
) STRICT;

CREATE TABLE item_link (
  from_item TEXT NOT NULL REFERENCES item(id),
  to_item   TEXT NOT NULL REFERENCES item(id),
  relation  TEXT NOT NULL CHECK (relation IN ('grown_up_word','contains')),
  source    TEXT NOT NULL CHECK (source IN ('tomo','jmdict')),  -- our authoring | JMdict xref
  PRIMARY KEY (from_item, to_item, relation)
) STRICT;

CREATE TABLE round (
  id         TEXT PRIMARY KEY,      -- 'r2.wanwan-ita'; never reused for a different prompt
  age        INTEGER NOT NULL,
  kind       TEXT NOT NULL CHECK (kind IN ('pick_picture','do_action','pick_reply','name_it','talk')),
  say        TEXT NOT NULL,
  romaji     TEXT NOT NULL,
  meaning_en TEXT NOT NULL,
  answer     TEXT,                  -- '🐶' | 'feed' | NULL for open answers
  choices    TEXT NOT NULL DEFAULT '[]',   -- JSON
  praise     TEXT
) STRICT;

CREATE TABLE round_item (
  round_id TEXT NOT NULL REFERENCES round(id),
  item_id  TEXT NOT NULL REFERENCES item(id),
  role     TEXT NOT NULL CHECK (role IN ('says','tests','expects')),
  PRIMARY KEY (round_id, item_id, role)
) STRICT;

-- =====================================================================================
-- learner.sqlite: read-write, local-first.
-- ~/Library/Application Support/Tomodachi/learner.sqlite
-- =====================================================================================
PRAGMA user_version = 1;          -- schema version; migrations only run forward
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;         -- set on every connection

CREATE TABLE meta (
  key   TEXT PRIMARY KEY,           -- 'device_id', 'derived_rules_version', 'fsrs_parameters',
  value TEXT NOT NULL             --   'pulled_until' (server download cursor)
) STRICT;

CREATE TABLE learner (
  id          TEXT PRIMARY KEY,     -- UUIDv7, made on first launch
  account_id  TEXT,                 -- Zenbu account; NULL until sign-in
  transcripts TEXT NOT NULL DEFAULT 'device' CHECK (transcripts IN ('off','device','sync')),
  created_at  TEXT NOT NULL,        -- all timestamps: UTC ISO 8601 with milliseconds
  updated_at  TEXT NOT NULL         -- last writer wins on sync (the only mutable rows)
) STRICT;

CREATE TABLE tomo (
  id         TEXT PRIMARY KEY,
  learner_id TEXT NOT NULL REFERENCES learner(id),
  name       TEXT NOT NULL DEFAULT 'トモ',
  hatched_at TEXT NOT NULL,
  retired_at TEXT,                  -- set by "start over"
  updated_at TEXT NOT NULL
) STRICT;

-- Append-only. Age = COALESCE(MAX(to_age), 1). Never deleted, never recomputed.
CREATE TABLE growth (
  id            TEXT PRIMARY KEY,
  tomo_id       TEXT NOT NULL REFERENCES tomo(id),
  to_age        INTEGER NOT NULL CHECK (to_age >= 2),
  grew_at       TEXT NOT NULL,
  visit_id      TEXT REFERENCES visit(id),
  rules_version TEXT NOT NULL,      -- the leveling rules that decided it
  basis         TEXT NOT NULL       -- JSON: the numbers that earned it
) STRICT;

CREATE TABLE visit (
  id              TEXT PRIMARY KEY,
  tomo_id         TEXT NOT NULL REFERENCES tomo(id),
  device_id       TEXT NOT NULL,
  opened_by       TEXT NOT NULL CHECK (opened_by IN ('drop_in','learner')),
  started_at      TEXT NOT NULL,
  ended_at        TEXT,             -- NULL while open; uploaded only once ended
  end_reason      TEXT CHECK (end_reason IN ('finished','ignored','closed','grew','quit')),
  local_day       TEXT NOT NULL,    -- the learner's calendar day then, '2026-10-03'
  utc_offset_min  INTEGER NOT NULL,
  tomo_age        INTEGER NOT NULL,
  app_version     TEXT NOT NULL,
  content_version TEXT NOT NULL,
  language_data   TEXT NOT NULL     -- language-data release, '2026.10.1'
) STRICT;

CREATE TABLE turn (
  id           TEXT PRIMARY KEY,
  visit_id     TEXT NOT NULL REFERENCES visit(id),
  seq          INTEGER NOT NULL,
  round_id     TEXT,                -- NULL for an AI-led line
  attempt      INTEGER NOT NULL DEFAULT 1,
  tomo_said    TEXT,                -- scripted: always; AI-written: follows learner.transcripts
  answer_mode  TEXT CHECK (answer_mode IN ('picture','action','reply_bubble','typed','spoken')),
  answer_pick  TEXT,                -- '🐶' | 'feed' | a bubble's text
  learner_text TEXT,                -- typed or recognised text; NULL when transcripts = 'off'
  outcome      TEXT NOT NULL CHECK (outcome IN ('right','wrong','not_understood','no_answer')),
  judged_by    TEXT NOT NULL,       -- 'script' | 'offline_rules' | 'ai:<provider>/<model>'
  hint_shown   INTEGER NOT NULL DEFAULT 0,
  replays      INTEGER NOT NULL DEFAULT 0,
  asked_at     TEXT NOT NULL,
  answered_at  TEXT,
  UNIQUE (visit_id, seq)
) STRICT;

CREATE TABLE evidence (
  id          TEXT PRIMARY KEY,
  turn_id     TEXT NOT NULL REFERENCES turn(id),
  item_id     TEXT NOT NULL,        -- no FK: free talk can hit any dictionary word
  kind        TEXT NOT NULL CHECK (kind IN ('exposure','comprehension','production','conversation')),
  result      TEXT NOT NULL CHECK (result IN ('seen','right','wrong','unclear')),
  via         TEXT NOT NULL CHECK (via IN ('tomo_voice','card','picture','action','reply_bubble','typed','spoken')),
  surface     TEXT,                 -- the form heard or said: いた, いぬ
  matched_by  TEXT NOT NULL CHECK (matched_by IN ('script','tokenizer','ai')),
  occurred_at TEXT NOT NULL,
  local_day   TEXT NOT NULL,        -- copied from the visit so day rules need no join
  UNIQUE (turn_id, item_id, kind)
) STRICT;
CREATE INDEX evidence_by_item ON evidence(item_id, kind, local_day);

CREATE TABLE outbox (               -- rows to upload, added in the same transaction as the row
  row_id     TEXT PRIMARY KEY,
  table_name TEXT NOT NULL CHECK (table_name IN ('learner','tomo','growth','visit','turn','evidence'))
) STRICT;

-- ---- Derived: rebuilt from the log when meta.derived_rules_version changes. Never synced.
CREATE TABLE item_state (
  item_id           TEXT PRIMARY KEY,
  headword          TEXT NOT NULL,  -- snapshot from language data, as iOS keeps on its records
  reading           TEXT NOT NULL,
  first_seen_at     TEXT NOT NULL,
  last_evidence_at  TEXT NOT NULL,
  exposures         INTEGER NOT NULL DEFAULT 0,
  understood_right  INTEGER NOT NULL DEFAULT 0,
  understood_wrong  INTEGER NOT NULL DEFAULT 0,
  understood_days   INTEGER NOT NULL DEFAULT 0,
  said_days         INTEGER NOT NULL DEFAULT 0,
  conversation_days INTEGER NOT NULL DEFAULT 0,
  level             TEXT NOT NULL CHECK (level IN ('seen','met','known','can_say','uses')),
  known_since       TEXT,           -- the first time it reached 'known'; never cleared
  can_say_since     TEXT
) STRICT;

CREATE TABLE srs_card (             -- FSRS Card fields (py-fsrs), one card per skill
  item_id        TEXT NOT NULL,
  skill          TEXT NOT NULL CHECK (skill IN ('understand','say')),
  state          INTEGER NOT NULL CHECK (state IN (1,2,3)),  -- Learning, Review, Relearning
  step           INTEGER,
  stability      REAL,
  difficulty     REAL,
  due_at         TEXT NOT NULL,
  last_review_at TEXT,
  PRIMARY KEY (item_id, skill)
) STRICT;

CREATE VIEW tomo_now AS
  SELECT t.id, t.name, COALESCE(MAX(g.to_age), 1) AS age
  FROM tomo t LEFT JOIN growth g ON g.tomo_id = t.id
  WHERE t.retired_at IS NULL GROUP BY t.id;
```

### Swift types sketch

```swift
import Foundation

// Mirrors learner.sqlite. Row IDs are UUIDv7; dates are UTC.
// Like the iOS WordKnowledgeStatus, decode unknown raw values into an `unrecognized` case and keep
// them, so an older Mac never drops rows that a newer device synced. (Left out below for brevity.)

struct LanguageReferenceID: Hashable, Codable, Sendable { let rawValue: String }  // 32 hex chars

/// Stored as one string, like the iOS app's SavedItem.storedID.
enum ItemID: Hashable, Sendable {
  case word(LanguageReferenceID)   // "681bff8274391329f3ce9ca80a4e04b0"
  case phrase(String)              // "phrase:wanwan-ita"
  case grammar(String)             // "grammar:te-iru"
}

enum EvidenceKind: String, Codable, Sendable { case exposure, comprehension, production, conversation }
enum EvidenceResult: String, Codable, Sendable { case seen, right, wrong, unclear }
enum Via: String, Codable, Sendable {
  case tomoVoice = "tomo_voice", card, picture, action, replyBubble = "reply_bubble", typed, spoken
}
enum MatchedBy: String, Codable, Sendable { case script, tokenizer, ai }

struct Evidence: Identifiable, Sendable {
  let id: UUID, turnID: UUID
  let item: ItemID
  let kind: EvidenceKind
  let result: EvidenceResult
  let via: Via
  let surface: String?
  let matchedBy: MatchedBy
  let occurredAt: Date
  let localDay: String                       // "2026-10-03"
}

struct Visit: Identifiable, Sendable {
  enum OpenedBy: String, Sendable { case dropIn = "drop_in", learner }
  enum EndReason: String, Sendable { case finished, ignored, closed, grew, quit }
  let id: UUID, tomoID: UUID, deviceID: UUID
  let openedBy: OpenedBy
  let startedAt: Date
  var endedAt: Date?, endReason: EndReason?
  let localDay: String, utcOffsetMinutes: Int
  let tomoAge: Int
  let appVersion: String, contentVersion: String, languageData: String
}

struct Turn: Identifiable, Sendable {
  enum AnswerMode: String, Sendable { case picture, action, replyBubble = "reply_bubble", typed, spoken }
  enum Outcome: String, Sendable { case right, wrong, notUnderstood = "not_understood", noAnswer = "no_answer" }
  let id: UUID, visitID: UUID
  let seq: Int, roundID: String?, attempt: Int
  let tomoSaid: String?
  let answerMode: AnswerMode?, answerPick: String?
  let learnerText: String?                   // nil when transcripts are off
  let outcome: Outcome
  let judgedBy: String
  let hintShown: Bool, replays: Int
  let askedAt: Date, answeredAt: Date?
}

struct Growth: Identifiable, Sendable {
  let id: UUID, tomoID: UUID
  let toAge: Int, grewAt: Date, visitID: UUID?
  let rulesVersion: String
  let basis: [String: Int]
}

enum TranscriptSetting: String, Sendable { case off, device, sync }

// Derived: rebuildable caches.
enum Level: String, Sendable { case seen, met, known, canSay = "can_say", uses }
enum Skill: String, Sendable { case understand, say }

struct ItemState: Sendable {
  let item: ItemID, headword: String, reading: String
  let exposures: Int, understoodDays: Int, saidDays: Int, conversationDays: Int
  let level: Level
  let knownSince: Date?, canSaySince: Date?
}

struct SRSCard: Sendable {
  enum State: Int, Sendable { case learning = 1, review, relearning }
  let item: ItemID, skill: Skill
  var state: State, step: Int?
  var stability: Double?, difficulty: Double?
  var due: Date, lastReview: Date?
  func recallProbability(at now: Date) -> Double { /* FSRS retrievability */ 0 }
}

/// The only write path: appends log rows and updates the caches in one transaction.
protocol LearnerStore: Sendable {
  func startVisit(_ visit: Visit) async throws
  func record(_ turn: Turn, evidence: [Evidence]) async throws
  func endVisit(_ id: UUID, at: Date, reason: Visit.EndReason) async throws
  func recordGrowth(_ growth: Growth) async throws
  func state(of item: ItemID) async throws -> ItemState?
  func dueCards(_ skill: Skill, now: Date, limit: Int) async throws -> [SRSCard]
  func rebuildDerived(rulesVersion: String) async throws
}
```

### Stored vs derived

| Data | Stored or derived | Why |
|---|---|---|
| Visit, turn, evidence, growth rows | **Stored**, append-only | They are facts and can't be recreated |
| `local_day`, `utc_offset_min` | **Stored** | The time zone at that moment can't be recovered later, and the "different days" rule depends on it |
| `tomo_age` on each visit | **Stored** | Lets analytics group by age without replaying growth |
| Tomo's current age | Derived: `MAX(growth.to_age)` | Growth rows are the truth |
| Tomo's look, mood, needs (hungry at lunch, sleepy at night) | Derived from age and the clock | Nothing to save |
| `item_state` counts, days, level, `known_since` | Derived and cached | The rules will change |
| `srs_card` | Derived and cached, by replaying reviews through FSRS | py-fsrs can rebuild a card from its review logs (`reschedule_card`) |
| Recall probability | Derived when read | It changes every second |
| Progress toward the next age | Derived | It depends on the leveling rules |
| Answer time, rounds per visit, ignore rate | Derived from turn timestamps | |
| `learner_text`, AI-written `tomo_said` | Stored only when transcripts aren't `off` | Privacy |
| Audio | **Never stored** | Privacy |

### How "known" is computed

Each item's level comes from its evidence:

- **seen**: exposure only.
- **met**: at least one `right` answer. Saying an item right counts as understanding it too.
- **known**: right on **two or more different local days**, and the latest answer was right. This is the concepts.md rule "known only after you've understood it on more than one day".
- **can_say**: known, plus a `right` production or conversation row.
- **uses**: conversation use on two or more different days.

```sql
SELECT item_id, COUNT(DISTINCT local_day) AS understood_days
FROM evidence
WHERE result = 'right' AND kind IN ('comprehension','production','conversation')
GROUP BY item_id;
```

Two separate notions:

- **`known_since` sticks.** Once set, it's never cleared. Growth counts it, so a bad day never takes progress away (the "no guilt" rule). The displayed level can drop back to `met`, which just brings the word back for review.
- **Recall probability is live.** FSRS computes it from stability and time since the last review. It picks what Tomo brings up: due items first, then at most one new word per visit ([leveling-points.md](leveling-points.md)).

**FSRS mapping.** One review per item, per skill, per visit, rated from that visit's evidence: any `wrong`/`unclear` → Again; right only after a hint or replay → Hard; right → Good; used in conversation → Easy. Exposures aren't reviews, and a retry after ちがう〜 doesn't earn a second review. FSRS's default same-day learning steps (1 and 10 minutes) don't fit "days, not minutes". py-fsrs accepts empty `learning_steps`, which sends a new card straight to Review. An official [swift-fsrs](https://github.com/open-spaced-repetition/swift-fsrs) exists.

**Baby talk.** ワンワン and 犬 are separate items with separate evidence, and the link passes no credit between them. It lets Tomo show the grown-up word (logged as `exposure`, `via = 'card'`), and lets the leveling rules reward the bridge, for example "said the grown-up word for 5 baby words". Thresholds belong to [leveling-points.md](leveling-points.md). This schema only needs `rules_version` and the evidence.

### Migration and sync

**Local migrations.**

- `PRAGMA user_version` holds the schema version. At launch the app runs forward-only migrations, one transaction each (GRDB's `DatabaseMigrator`, or a short hand-written loop).
- A file from a newer version opens read-only, as the iOS `LocalJSONFile` does.
- If `meta.derived_rules_version` doesn't match the app's rules, drop the derived tables and rebuild them from the log. The log stays small: 10 visits a day at about 10 evidence rows each is around 36,000 rows a year.
- The demo saves nothing, so nothing needs migrating. Its word keys just map to the IDs above.

**Content and language data.** Round and item IDs are never reused for something different. Language Reference IDs are permanent. If a release retires an entry, its evidence stays, and `item_state` and `surface` keep readable text. Each visit records `content_version` and `language_data`, so every row traces to the data it was written against.

**Sync, once there's a backend.**

- **IDs.** Each log row gets a UUIDv7 made on the device. These are time-ordered (RFC 9562), and no device has to ask a server for one.
- **Upload.** Send outbox rows in batches. The server inserts by `id` and ignores duplicates, so retries are safe. Remove rows once the server confirms them. A visit enters the outbox when it ends.
- **Download.** Fetch other devices' rows since `meta.pulled_until`, then rebuild the derived tables. Evidence only ever grows, so merging two devices is a plain union.
- **Growth.** Two offline devices could both record a 3さい birthday. Age is `MAX(to_age)`, so the extra row does no harm.
- **Mutable rows.** Only `learner` and `tomo` change. They merge by last writer wins on `updated_at`, as iOS lists do.
- **Server.** Not chosen yet (ADR 0006). If it runs on D1 like the website, the DDL carries over almost unchanged (D1 "has SQLite's SQL semantics"), with every row scoped to an account. Apps reach it only through `/v1` (ADR 0007).
- **What goes up.** Log rows only. `learner_text` and AI-written `tomo_said` are removed unless transcripts is set to `sync`, because AI replies often echo the learner. Derived tables and audio never go up.
- **Zenbu iOS "Known".** Keep it separate. iOS Known is the learner's own judgement, while Tomo's known comes from evidence. Neither should overwrite the other.

### Example rows: one short visit

A 2さい drop-in with three turns and transcripts set to `device`. Row IDs are shortened here; real ones are UUIDv7. Item IDs show the first 8 hex characters.

**visit**

| id | opened_by | started_at → ended_at | end_reason | local_day | utc_offset_min | tomo_age | content_version | language_data |
|---|---|---|---|---|---|---|---|---|
| v1 | drop_in | 2026-10-03T16:12:05.120Z → 16:12:33.050Z | finished | 2026-10-03 | -420 | 2 | 0.4.0 | 2026.10.1 |

**turn**

| id | seq | round_id | tomo_said | answer_mode | answer_pick | learner_text | outcome | judged_by | hint | asked → answered |
|---|---|---|---|---|---|---|---|---|---|---|
| t1 | 1 | r2.wanwan-ita | ワンワン いた！ | picture | 🐶 | NULL | right | script | 0 | 16:12:06.3 → 16:12:09.0 |
| t2 | 2 | r2.kore-nani-dog | これ なに？ | spoken | NULL | いぬ | right | script | 0 | 16:12:12.5 → 16:12:16.8 |
| t3 | 3 | r2.wanwan-suki | ワンワン すき？ | typed | NULL | うん すき！ | right | offline_rules | 0 | 16:12:20.1 → 16:12:31.4 |

**evidence** (all have `local_day` 2026-10-03)

| id | turn | item | kind | result | via | surface | matched_by |
|---|---|---|---|---|---|---|---|
| e1 | t1 | ワンワン `98926421` | exposure | seen | tomo_voice | ワンワン | script |
| e2 | t1 | いる `86470477` | exposure | seen | tomo_voice | いた | script |
| e3 | t1 | いる `86470477` | comprehension | right | picture | いた | script |
| e4 | t1 | `phrase:wanwan-ita` | comprehension | right | picture | NULL | script |
| e5 | t1 | 犬 `681bff82` | exposure | seen | card | いぬ | script |
| e6 | t2 | これ `52f4294d` | exposure | seen | tomo_voice | これ | script |
| e7 | t2 | 何 `9686ab4f` | exposure | seen | tomo_voice | なに | script |
| e8 | t2 | 犬 `681bff82` | production | right | spoken | いぬ | script |
| e9 | t3 | ワンワン `98926421` | exposure | seen | tomo_voice | ワンワン | script |
| e10 | t3 | 好き `9e6cae1c` | exposure | seen | tomo_voice | すき | script |
| e11 | t3 | 好き `9e6cae1c` | comprehension | right | typed | すき | script |
| e12 | t3 | 好き `9e6cae1c` | conversation | right | typed | すき | tokenizer |
| e13 | t3 | うん `468d59e8` | conversation | right | typed | うん | tokenizer |

e5 is the "grown-ups say: いぬが いた！" card. e8 is where the bridge pays off: the learner heard ワンワン and answered with the grown-up いぬ. If they had tapped a すき！ bubble instead of typing, e11 would be `via = reply_bubble` and e12 and e13 wouldn't exist.

**item_state** after the visit (ワンワン has history from 1さい)

| item | exposures | understood_days | said_days | conversation_days | level | known_since |
|---|---|---|---|---|---|---|
| ワンワン | 14 | 3 | 0 | 0 | known | 2026-09-29 |
| 犬 | 2 | 1 | 1 | 0 | met | NULL |
| 好き | 1 | 1 | 1 | 1 | met | NULL |

犬 isn't `known` yet, even though it was said correctly: one day isn't enough. That's the "can't cram" rule.

**srs_card** (new cards, py-fsrs default parameters, no learning steps)

| item | skill | rating | state | stability | difficulty | due_at |
|---|---|---|---|---|---|---|
| 犬 | understand | Good | 2 | 2.3065 | 2.12 | ≈ 2026-10-05 |
| 犬 | say | Good | 2 | 2.3065 | 2.12 | ≈ 2026-10-05 |
| 好き | say | Easy | 2 | 8.2956 | 1.0 | ≈ 2026-10-11 |

A first rating sets stability to `w[rating−1]` and difficulty to `w4 − e^(w5·(rating−1)) + 1`, clamped to 1–10. FSRS defines stability as the time until recall drops to 90%, so the first interval is about that many days, before fuzzing.

## Options compared

| | A. Current state only | B. Event log only | **C. Log + derived cache (recommended)** |
|---|---|---|---|
| What's saved | One row per word: status, counts, SRS fields, `updated_at` (like iOS `word-knowledge.json`) | Every visit, turn and evidence row; nothing else | The log, plus state tables that can be rebuilt |
| Per-visit and per-turn analytics | No (adding a log turns it into C) | Yes | Yes |
| Change the "known" or leveling rules later | Can't recompute; old counts reflect old rules | Recompute | Rebuild the cache |
| Merging two devices | Last writer wins per word, so updates can be lost | Union, no conflicts | Union of the log; caches rebuilt |
| Speed of "what's due now?" | Fast | Replay or heavy queries every time | Fast |
| Storage | Smallest | About 100 rows a day | Same as B, plus a few thousand state rows |
| Code | Least | Simple writes, complex reads | Most: the write path also updates the cache, and a test must check that a rebuild matches the incremental updates |
| Privacy surface | Least | Most; needs a pruning policy | Same as B |

Sync transports: **CloudKit/SwiftData** is Apple-only and can't reach the website. **CRDT libraries** solve concurrent edits, which log rows never have. A **plain upload of immutable rows** fits ADR 0007's `/v1` API.

## Risks and open questions

**Risks**

- **Picking the wrong Language Reference ID.** Looking up the form まんま ranks まま ("as it is") above 飯【まんま】. For いた, the form 居る ranks 居る【おる】 first, but the right entry is いる (1577980). Scripted content must name its IDs explicitly, reviewed by a person, with a test that each one resolves in the pinned language-data release.
- **IDs cover whole entries, not senses.** ワンワン's one entry means both "woof" and "doggy". That's fine for toddler words. Don't key on JMdict sense numbers; they aren't stable.
- **Free-text matching at 3さい.** The tokenizer can credit the wrong homograph, or a word copied from a hint. `matched_by`, `hint_shown` and the no-hint rule for `conversation` limit the damage.
- **Speech privacy.** The demo sets `requiresOnDeviceRecognition` only when the Mac supports it (`TomoChat.swift`). Apple's documentation says that flag "determines whether a request must keep its audio data on the device", so on other Macs audio may leave the device. Nothing is stored either way, but the privacy text must say so, or the app should refuse the server fallback.
- **AI providers.** A configured provider receives the conversation whatever the storage setting says.
- **Cache drift.** Incremental updates and a rebuild could disagree. This needs a property test.
- **Time zones.** Travel can split or merge a "day". Accept it.

**Open questions**

- What are the growth thresholds ([leveling-points.md](leveling-points.md))? What happens when a rules change lowers progress toward the next age? (The current age is safe.)
- Should transcripts default to `device` (proposed) or `off`? Should `learner_text` be pruned after N days? Does the single-word `surface` count as transcript?
- Should words marked Known in the iOS app seed Tomo as a fifth kind, `self_report`? Should Tomo's evidence show in the Zenbu app?
- Where do the "known" rules run for the website? For search, ADR 0008 chose one TypeScript core with a conformance suite; that pattern could fit here.
- Who owns grammar and phrase IDs? Should they, and JMdict's `&chn;` tag, go into the shared language-data artifact (ADR 0006, "precompute first")?
- Does "start over" keep the old evidence or begin at zero?

## Sources

**This prototype**

- [docs/concepts.md](../concepts.md)
- [TomoGame.swift](../../mac-demo/NotchBuddy/Sources/App/TomoGame.swift) (`known`, `stageGoal`, `start()`), [TomoChat.swift](../../mac-demo/NotchBuddy/Sources/App/TomoChat.swift) (`TomoReply.understood`, `requiresOnDeviceRecognition`)

**Zenbu monorepo** (read-only, commit `738a7231`, 2026-09-30)

- `CONTEXT.md`: Language Reference ID vs JMdict entry number
- ADR 0006 (`docs/adr/0006-share-language-data-as-a-versioned-artifact.md`) (permanent IDs; `WordNoteID` must move before sync; sync backend not chosen), ADR 0007 (`docs/adr/0007-publish-the-dictionary-at-permanent-urls-from-the-websites-copy.md`) (learner data behind `/v1`), ADR 0008 (`docs/adr/0008-share-one-typescript-search-core-built-for-the-most-constrained-client.md`), ADR 0001 (`docs/adr/0001-keep-language-data-and-tools-replaceable.md`)
- `docs/data-sources.md`, `docs/technologies.md` ("Cloudflare D1 through Drizzle")
- Website storage: `apps/web/drizzle.config.ts`, `apps/web/src/db/schema.ts` (empty), `apps/web/wrangler.jsonc` (three D1 bindings), `apps/web/drizzle/meta/_journal.json` (no migrations), `apps/web/docs/product/index.md` (#468)
- iOS learner data: `apps/ios/Modules/Sources/SearchExperience/WordKnowledge.swift`, `apps/ios/Modules/Sources/SearchExperience/SavedItem.swift`, `apps/ios/Modules/Sources/SearchExperience/WordLists.swift`, `apps/ios/Modules/Sources/SearchExperience/WordNoteStore.swift`, `apps/ios/Modules/Sources/SearchExperience/EncounterMediaStore.swift`, `apps/ios/Modules/Sources/SearchExperience/LocalJSONFile.swift`, `apps/ios/Modules/Sources/SearchExperience/DictionaryEntry.swift` (`LanguageReferenceID`)
- `apps/ios/Tools/import_jmdict.py` (`language_reference_id()`, `normalize_usage_notes()`)
- `apps/ios/Modules/Sources/SearchExperience/Resources/LanguageReferenceData.sqlite3` (IDs above) and `apps/ios/LanguageData/Sources/JMdict_e-2026-08-10.gz` (`&chn;` count), both queried read-only
- `language-data/README.md`, `language-data/release.json` (`2026.10.1`)

**External**

- FSRS: [py-fsrs README](https://github.com/open-spaced-repetition/py-fsrs) (`reschedule_card`, `desired_retention` 0.9), [card.py](https://github.com/open-spaced-repetition/py-fsrs/blob/main/fsrs/card.py), [review_log.py](https://github.com/open-spaced-repetition/py-fsrs/blob/main/fsrs/review_log.py), [scheduler.py](https://github.com/open-spaced-repetition/py-fsrs/blob/main/fsrs/scheduler.py) (default parameters and learning steps), [awesome-fsrs](https://github.com/open-spaced-repetition/awesome-fsrs) (swift-fsrs; FSRS in Anki)
- SQLite: [STRICT tables](https://sqlite.org/stricttables.html) (3.37.0+), [PRAGMA user_version](https://sqlite.org/pragma.html#pragma_user_version)
- [RFC 9562 §5.7, UUIDv7](https://www.rfc-editor.org/rfc/rfc9562.html#section-5.7)
- [Cloudflare D1 overview](https://developers.cloudflare.com/d1/)
- [Apple: `requiresOnDeviceRecognition`](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition)
