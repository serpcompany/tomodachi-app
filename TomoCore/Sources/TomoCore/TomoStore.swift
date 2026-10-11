import Foundation
import SQLite3

// MARK: - Saved progress: one SQLite file on this Mac
//
// ~/Library/Application Support/<bundle ID>/learner.sqlite (TOMO_DATA_DIR=<dir> overrides it,
// so test runs never touch the learner's own Tomo). Keyed by (learner language, target language): one Tomo
// per pair. `tomo` and `item` hold the current state; `answer`, `growth` and `visit` are logs, kept to tune
// the rules later and to sync with the Zenbu apps one day (docs/research/learner-data-schema.md). The logs
// stay on this device (TomoSync syncs only `tomo` and `item`); TomoStats counts from them.
// The rules that fill it are in TomoProgress.swift. Saving a Tomo or a word reports it through `didChange`, so
// TomoSync can send it to the learner's other devices; the `Sync` methods below write what arrives without
// reporting it back.

@MainActor
public final class TomoStore {
    public struct TomoRow: Sendable {
        public let metAt: Date; public let level: Int; public let age: Int
        /// The seed of a Tomo moved here from another pair, whose look it keeps (`move`); nil: this pair's own.
        public let seed: String?
        public init(metAt: Date, level: Int, age: Int, seed: String? = nil) {
            self.metAt = metAt; self.level = level; self.age = age; self.seed = seed
        }
    }
    public struct ItemRow: Sendable, Equatable {
        public let id: String
        public var stage: Int
        public var due: Date?              // nil once burned
        public var introduced: Date
        public var answered: Date
        public var right: Int
        public var wrong: Int
        public var peak = 0                // the highest stage it ever reached: the experience bar never goes back

        public init(id: String, stage: Int, due: Date?, introduced: Date, answered: Date, right: Int, wrong: Int,
                    peak: Int = 0) {
            self.id = id; self.stage = stage; self.due = due; self.introduced = introduced; self.answered = answered
            self.right = right; self.wrong = wrong; self.peak = peak
        }
    }

    /// What a save changed, for TomoSync. `cleared`: start over removed these words.
    public struct Change: Sendable {
        public enum Kind: Sendable { case tomo, item(String), cleared([String]) }
        public let directory: URL
        public let learner: String
        public let target: String
        public let kind: Kind
    }
    /// Called after each save of a Tomo or a word (TomoSync listens).
    public static var didChange: ((Change) -> Void)?

    nonisolated(unsafe) private var db: OpaquePointer?
    /// Statements that failed on this connection (`report`): `take` checks none failed before it deletes anything.
    private var failures = 0
    private let learner: String
    private let target: String
    private let directory: URL

    public static var directory: URL {
        if let d = ProcessInfo.processInfo.environment["TOMO_DATA_DIR"] { return URL(fileURLWithPath: d) }
        return defaultDirectory
    }

    /// The folder without TOMO_DATA_DIR, named by the bundle ID: a Debug build's (`….debug`) is never the owner's (#54).
    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "Tomodachi")
    }

    public init?(learner: String, target: String, directory: URL = TomoStore.directory) {
        self.learner = learner
        self.target = target
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("learner.sqlite").path
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            NSLog("Tomo: couldn't open \(path)")
            sqlite3_close(db)
            return nil
        }
        exec("""
            PRAGMA journal_mode = WAL;
            CREATE TABLE IF NOT EXISTS tomo (
              learner TEXT NOT NULL, target TEXT NOT NULL,
              met_at REAL NOT NULL, level INTEGER NOT NULL, age INTEGER NOT NULL,
              PRIMARY KEY (learner, target));
            CREATE TABLE IF NOT EXISTS item (
              learner TEXT NOT NULL, target TEXT NOT NULL, item_id TEXT NOT NULL,
              stage INTEGER NOT NULL, due_at REAL, introduced_at REAL NOT NULL, answered_at REAL NOT NULL,
              right_count INTEGER NOT NULL, wrong_count INTEGER NOT NULL,
              PRIMARY KEY (learner, target, item_id));
            CREATE TABLE IF NOT EXISTS answer (
              at REAL NOT NULL, learner TEXT NOT NULL, target TEXT NOT NULL, item_id TEXT,
              level INTEGER NOT NULL, mode TEXT NOT NULL, result TEXT NOT NULL,
              wrong_tries INTEGER NOT NULL, hint INTEGER NOT NULL, counted INTEGER NOT NULL,
              stage_before INTEGER, stage_after INTEGER);
            CREATE TABLE IF NOT EXISTS growth (
              at REAL NOT NULL, learner TEXT NOT NULL, target TEXT NOT NULL,
              kind TEXT NOT NULL, value INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS visit (
              started_at REAL NOT NULL, learner TEXT NOT NULL, target TEXT NOT NULL,
              opened TEXT NOT NULL, card_at REAL, ended_at REAL, ended TEXT,
              PRIMARY KEY (learner, target, started_at));
            CREATE TABLE IF NOT EXISTS cloud (record TEXT PRIMARY KEY, fields BLOB NOT NULL);
            """)
        // Added after the first saved Tomos: each fails harmlessly once the column exists.
        sqlite3_exec(db, "ALTER TABLE item ADD COLUMN peak INTEGER NOT NULL DEFAULT 0", nil, nil, nil)
        // When this pair last started over (0: never), so an older Tomo from another device can't come back.
        sqlite3_exec(db, "ALTER TABLE tomo ADD COLUMN reset_at REAL NOT NULL DEFAULT 0", nil, nil, nil)
        // The look of a Tomo moved here from another pair (`move`, #199). It stays on this device: TomoSync doesn't send it.
        sqlite3_exec(db, "ALTER TABLE tomo ADD COLUMN seed TEXT", nil, nil, nil)
    }

    deinit { sqlite3_close(db) }

    // MARK: Tomo

    public func loadTomo() -> TomoRow? { tomo(learner: learner)?.row }

    /// A learner language's Tomo for this target, and when that pair last started over (0: never).
    private func tomo(learner who: String) -> (row: TomoRow, resetAt: Date)? {
        query("SELECT met_at, level, age, reset_at, seed FROM tomo WHERE learner = ? AND target = ?", [who, target]) {
            (TomoRow(metAt: Date(timeIntervalSince1970: sqlite3_column_double($0, 0)),
                     level: Int(sqlite3_column_int64($0, 1)), age: Int(sqlite3_column_int64($0, 2)),
                     seed: sqlite3_column_type($0, 4) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text($0, 4))),
             Date(timeIntervalSince1970: sqlite3_column_double($0, 3)))
        }.first
    }

    public func saveTomo(_ t: TomoRow) {
        writeTomo(t)
        announce(.tomo)
    }

    /// A row without a seed keeps the saved one while it's the same Tomo (met in the same second, as the look's seed
    /// counts it); a new one (a start over, or an earlier Tomo merged in from another device) takes its pair's own.
    @discardableResult
    private func writeTomo(_ t: TomoRow, resetAt: Date? = nil) -> Bool {
        run("""
            INSERT INTO tomo (learner, target, met_at, level, age, reset_at, seed) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (learner, target) DO UPDATE SET met_at = excluded.met_at, level = excluded.level,
              age = excluded.age, reset_at = COALESCE(?, reset_at),
              seed = COALESCE(excluded.seed, CASE WHEN CAST(met_at AS INTEGER) = CAST(excluded.met_at AS INTEGER) THEN seed END)
            """, [learner, target, t.metAt.timeIntervalSince1970, t.level, t.age,
                  resetAt?.timeIntervalSince1970 ?? 0, t.seed, resetAt?.timeIntervalSince1970])
    }

    // MARK: Items

    public func loadItems() -> [String: ItemRow] { items(learner: learner) }

    private func items(learner who: String) -> [String: ItemRow] {
        let rows = query("""
            SELECT item_id, stage, due_at, introduced_at, answered_at, right_count, wrong_count, peak
            FROM item WHERE learner = ? AND target = ?
            """, [who, target]) { s in
            ItemRow(id: String(cString: sqlite3_column_text(s, 0)),
                    stage: Int(sqlite3_column_int64(s, 1)),
                    due: sqlite3_column_type(s, 2) == SQLITE_NULL
                        ? nil : Date(timeIntervalSince1970: sqlite3_column_double(s, 2)),
                    introduced: Date(timeIntervalSince1970: sqlite3_column_double(s, 3)),
                    answered: Date(timeIntervalSince1970: sqlite3_column_double(s, 4)),
                    right: Int(sqlite3_column_int64(s, 5)), wrong: Int(sqlite3_column_int64(s, 6)),
                    peak: max(Int(sqlite3_column_int64(s, 7)), Int(sqlite3_column_int64(s, 1))))
        }
        return Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    public func saveItem(_ i: ItemRow) {
        writeItem(i)
        announce(.item(i.id))
    }

    @discardableResult
    private func writeItem(_ i: ItemRow) -> Bool {
        run("""
            INSERT OR REPLACE INTO item
              (learner, target, item_id, stage, due_at, introduced_at, answered_at, right_count, wrong_count, peak)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [learner, target, i.id, i.stage, i.due?.timeIntervalSince1970, i.introduced.timeIntervalSince1970,
                  i.answered.timeIntervalSince1970, i.right, i.wrong, i.peak])
    }

    // MARK: Logs

    /// One row per answer, counted or not. `result`: right | wrong | help | language.
    public func logAnswer(at: Date, item: String?, level: Int, mode: String, result: String, wrongTries: Int,
                   hint: Bool, counted: Bool, before: Int?, after: Int?) {
        run("""
            INSERT INTO answer (at, learner, target, item_id, level, mode, result, wrong_tries, hint, counted,
                                stage_before, stage_after)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [at.timeIntervalSince1970, learner, target, item, level, mode, result, wrongTries,
                  hint ? 1 : 0, counted ? 1 : 0, before, after])
    }

    /// `kind`: level | age | reset.
    public func logGrowth(at: Date, kind: String, value: Int) {
        run("INSERT INTO growth (at, learner, target, kind, value) VALUES (?, ?, ?, ?, ?)",
            [at.timeIntervalSince1970, learner, target, kind, value])
    }

    /// The growth log since a time, oldest first: (kind, value) as `logGrowth` wrote it.
    public func growthLog(since: Date = .distantPast) -> [(kind: String, value: Int)] {
        growthEvents(since: since).map { ($0.kind, $0.value) }
    }

    /// One row of the growth log: a level-up (`level`, the new level), a birthday (`age`) or a start over (`reset`).
    public struct GrowthRow: Sendable, Equatable { public let at: Date; public let kind: String; public let value: Int }

    /// The growth log since a time, oldest first, with when each happened.
    public func growthEvents(since: Date = .distantPast) -> [GrowthRow] {
        query("SELECT at, kind, value FROM growth WHERE learner = ? AND target = ? AND at >= ? ORDER BY at, rowid",
              [learner, target, since.timeIntervalSince1970]) {
            GrowthRow(at: Date(timeIntervalSince1970: sqlite3_column_double($0, 0)),
                      kind: String(cString: sqlite3_column_text($0, 1)), value: Int(sqlite3_column_int64($0, 2)))
        }
    }

    /// One row of the answer log, as `logAnswer` wrote it.
    public struct AnswerRow: Sendable, Equatable {
        public let at: Date
        public let item: String?
        public let level: Int
        public let mode: String            // picture | need | meaning | reply | chat…
        public let result: String          // right | wrong | help | language
        public let wrongTries: Int
        public let hint: Bool
        public let counted: Bool
        public let before: Int?            // nil: the word was new
        public let after: Int?
    }

    /// The answer log in `[from, to)`, oldest first.
    public func answerLog(from: Date, to: Date) -> [AnswerRow] {
        func int(_ s: OpaquePointer, _ i: Int32) -> Int? {
            sqlite3_column_type(s, i) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(s, i))
        }
        return query("""
            SELECT at, item_id, level, mode, result, wrong_tries, hint, counted, stage_before, stage_after FROM answer
            WHERE learner = ? AND target = ? AND at >= ? AND at < ? ORDER BY at, rowid
            """, [learner, target, from.timeIntervalSince1970, to.timeIntervalSince1970]) { s in
            AnswerRow(at: Date(timeIntervalSince1970: sqlite3_column_double(s, 0)),
                      item: sqlite3_column_type(s, 1) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(s, 1)),
                      level: Int(sqlite3_column_int64(s, 2)), mode: String(cString: sqlite3_column_text(s, 3)),
                      result: String(cString: sqlite3_column_text(s, 4)), wrongTries: Int(sqlite3_column_int64(s, 5)),
                      hint: sqlite3_column_int64(s, 6) == 1, counted: sqlite3_column_int64(s, 7) == 1,
                      before: int(s, 8), after: int(s, 9))
        }
    }

    /// When this device first logged an answer for this pair at or after `since` (nil: none yet).
    public func firstAnswer(since: Date) -> Date? {
        query("SELECT MIN(at) FROM answer WHERE learner = ? AND target = ? AND at >= ?",
              [learner, target, since.timeIntervalSince1970]) { s -> Date? in
            sqlite3_column_type(s, 0) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(s, 0))
        }.first ?? nil
    }

    /// The visit log: a visit as it starts, again when its card opens, and when it ends (one row per visit, by when
    /// it started).
    public func logVisit(_ v: TomoVisit) {
        run("""
            INSERT INTO visit (started_at, learner, target, opened, card_at, ended_at, ended) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (learner, target, started_at) DO UPDATE SET opened = excluded.opened,
              card_at = excluded.card_at, ended_at = excluded.ended_at, ended = excluded.ended
            """, [v.started.timeIntervalSince1970, learner, target, v.opened.rawValue,
                  v.cardAt?.timeIntervalSince1970, v.endedAt?.timeIntervalSince1970, v.ended?.rawValue])
    }

    /// Visits that started in `[from, to)`, oldest first.
    public func visitLog(from: Date, to: Date) -> [TomoVisit] {
        func date(_ s: OpaquePointer, _ i: Int32) -> Date? {
            sqlite3_column_type(s, i) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(s, i))
        }
        return query("""
            SELECT started_at, opened, card_at, ended_at, ended FROM visit
            WHERE learner = ? AND target = ? AND started_at >= ? AND started_at < ? ORDER BY started_at
            """, [learner, target, from.timeIntervalSince1970, to.timeIntervalSince1970]) { s in
            TomoVisit(started: Date(timeIntervalSince1970: sqlite3_column_double(s, 0)),
                      opened: TomoVisit.Opened(rawValue: String(cString: sqlite3_column_text(s, 1))) ?? .card,
                      cardAt: date(s, 2), endedAt: date(s, 3),
                      ended: sqlite3_column_type(s, 4) == SQLITE_NULL
                        ? nil : TomoVisit.Ended(rawValue: String(cString: sqlite3_column_text(s, 4))))
        }
    }

    /// Start over: this pair's words are cleared and the time noted; the Tomo row waits for the new Tomo
    /// (TomoProgress hatches it). The logs stay.
    public func clear(at: Date) {
        let words = loadItems().keys.sorted()
        clearWords(resetAt: at)
        announce(.cleared(words))
    }

    private func clearWords(resetAt: Date) {
        run("DELETE FROM item WHERE learner = ? AND target = ?", [learner, target])
        run("""
            INSERT INTO tomo (learner, target, met_at, level, age, reset_at) VALUES (?, ?, ?, 1, 1, ?)
            ON CONFLICT (learner, target) DO UPDATE SET reset_at = excluded.reset_at
            """, [learner, target, resetAt.timeIntervalSince1970, resetAt.timeIntervalSince1970])
        logGrowth(at: resetAt, kind: "reset", value: 0)
    }

    private func announce(_ kind: Change.Kind) {
        Self.didChange?(Change(directory: directory, learner: learner, target: target, kind: kind))
    }

    // MARK: A pair the rule no longer allows (#199)

    /// What `move` did. `failed`: something couldn't be read or written, so it was all undone.
    public enum Moved: Sendable { case nothing, moved, failed }

    /// Moves the Tomo saved for (`from`, target) to (`to`, target), so a learner set up before the pair rule
    /// (`TomoLanguages.allows`: ja:ja) keeps its Tomo, words and logs under the pair it's allowed. With no Tomo there
    /// yet, everything moves as it is, and the Tomo keeps its look (`seed`). With one, the two merge as two devices'
    /// Tomos meeting do (`TomoSync.mergeTomo`, `mergeItem`): the earlier meeting and its look, the higher level and age,
    /// each word's copy answered last; the answer and visit logs come along, and the growth log of the Tomo kept is
    /// the one this pair keeps (the other stays behind with the life it tells). Without a saved Tomo for `from` nothing happens, and no file is made. iCloud
    /// gets every Tomo again when sync starts (`TomoSync.resendAtStart`). All or nothing: if any read or write fails
    /// (a full disk, a busy file), it's all undone and `from`'s Tomo stays where it was, so the next launch tries again.
    @discardableResult
    public static func move(learner from: String, to: String, target: String,
                            directory: URL = TomoStore.directory) -> Moved {
        guard from != to, FileManager.default.fileExists(atPath: directory.appendingPathComponent("learner.sqlite").path)
        else { return .nothing }
        guard let store = TomoStore(learner: to, target: target, directory: directory) else { return .failed }
        return store.take(from: from)
    }

    private func take(from other: String) -> Moved {
        let failed = failures
        /// Nothing failed so far, and the transaction is still open: SQLite undoes it by itself on some errors (a full
        /// disk, an I/O error), and a write after that would be saved on its own. A failed read returns nothing.
        func fine() -> Bool { failures == failed && sqlite3_get_autocommit(db) == 0 }
        func copy() -> Moved {
            guard exec("BEGIN IMMEDIATE") else { return .failed }
            let found = tomo(learner: other), ours = tomo(learner: learner)
            let mine = loadItems(), theirItems = items(learner: other)
            guard fine() else { return .failed }
            guard let theirs = found else { return .nothing }
            let theirSeed = theirs.row.seed ?? TomoLook.pairSeed(learner: other, target: target, metAt: theirs.row.metAt)
            if let ours {
                func state(_ t: (row: TomoRow, resetAt: Date)) -> TomoSync.TomoState {
                    .init(metAt: t.row.metAt, level: t.row.level, age: t.row.age, resetAt: t.resetAt)
                }
                let m = TomoSync.mergeTomo(local: state(ours), remote: state(theirs), first: true).tomo
                let theirsKept = m.metAt == theirs.row.metAt
                // Each growth log stays with the life it tells: if the moved Tomo is kept (it met first, as it always
                // did before a Tomo hatched here after a failed move), the two pairs' logs swap; if not, the moved one's
                // stays behind.
                let swap = "UPDATE growth SET learner = CASE learner WHEN ? THEN ? ELSE ? END WHERE target = ? AND learner IN (?, ?)"
                guard writeTomo(TomoRow(metAt: m.metAt, level: m.level, age: m.age,
                                        seed: theirsKept ? theirSeed : ours.row.seed), resetAt: m.resetAt),
                      !theirsKept || run(swap, [other, learner, other, target, other, learner])
                else { return .failed }
            } else {
                guard writeTomo(TomoRow(metAt: theirs.row.metAt, level: theirs.row.level, age: theirs.row.age,
                                        seed: theirSeed), resetAt: theirs.resetAt),
                      run("UPDATE growth SET learner = ? WHERE learner = ? AND target = ?", [learner, other, target])
                else { return .failed }
            }
            for (id, row) in theirItems {
                guard writeItem(TomoSync.mergeItem(local: mine[id], remote: row)) else { return .failed }
            }
            guard run("UPDATE answer SET learner = ? WHERE learner = ? AND target = ?", [learner, other, target]),
                  run("UPDATE OR IGNORE visit SET learner = ? WHERE learner = ? AND target = ?", [learner, other, target]),
                  fine(),
                  run("DELETE FROM item WHERE learner = ? AND target = ?", [other, target]),
                  run("DELETE FROM tomo WHERE learner = ? AND target = ?", [other, target]),
                  exec("COMMIT")
            else { return .failed }
            return .moved
        }
        let result = copy()
        if sqlite3_get_autocommit(db) == 0 { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) }
        switch result {
        case .moved: TomoSync.resendAtStart(in: directory)
        case .failed:
            NSLog("Tomo store: couldn't move \(other):\(target)'s Tomo to \(learner):\(target), so nothing moved; the next launch tries again")
        case .nothing: break
        }
        return result
    }

    // MARK: Sync (TomoSync): writes what another device sent, without reporting it back

    /// This pair's Tomo and when it last started over (0: never).
    func syncTomo() -> (row: TomoRow, resetAt: Date)? { tomo(learner: learner) }

    func syncWriteTomo(_ t: TomoRow, resetAt: Date) { writeTomo(t, resetAt: resetAt) }
    func syncWriteItem(_ i: ItemRow) { writeItem(i) }
    /// Another device started over: this one's words go too.
    func syncClear(resetAt: Date) { clearWords(resetAt: resetAt) }

    /// Every language pair with a saved Tomo, in this file.
    func syncPairs() -> [(learner: String, target: String)] {
        query("SELECT learner, target FROM tomo", []) {
            (String(cString: sqlite3_column_text($0, 0)), String(cString: sqlite3_column_text($0, 1)))
        }
    }

    /// CloudKit's own fields of a record we last saw (its change tag), so the next save isn't a conflict.
    func cloudFields(_ record: String) -> Data? {
        query("SELECT fields FROM cloud WHERE record = ?", [record]) { s in
            Data(bytes: sqlite3_column_blob(s, 0), count: Int(sqlite3_column_bytes(s, 0)))
        }.first
    }

    func setCloudFields(_ record: String, _ fields: Data?) {
        if let fields { run("INSERT OR REPLACE INTO cloud (record, fields) VALUES (?, ?)", [record, fields]) }
        else { run("DELETE FROM cloud WHERE record = ?", [record]) }
    }

    func clearCloudFields() { run("DELETE FROM cloud", []) }

    // MARK: SQLite

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Whether it worked: a failure is logged (`report`) and otherwise ignored, except by `take`.
    @discardableResult
    private func exec(_ sql: String) -> Bool {
        if sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK { return true }
        report(sql)
        return false
    }

    @discardableResult
    private func run(_ sql: String, _ args: [Any?]) -> Bool {
        guard let s = prepare(sql, args) else { return false }
        defer { sqlite3_finalize(s) }
        if sqlite3_step(s) == SQLITE_DONE { return true }
        report(sql)
        return false
    }

    private func query<T>(_ sql: String, _ args: [Any?], _ row: (OpaquePointer) -> T) -> [T] {
        guard let s = prepare(sql, args) else { return [] }
        defer { sqlite3_finalize(s) }
        var out: [T] = []
        var rc = sqlite3_step(s)
        while rc == SQLITE_ROW { out.append(row(s)); rc = sqlite3_step(s) }
        if rc != SQLITE_DONE { report(sql) }
        return out
    }

    private func prepare(_ sql: String, _ args: [Any?]) -> OpaquePointer? {
        var s: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &s, nil) == SQLITE_OK, let s else { report(sql); return nil }
        for (i, a) in args.enumerated() {
            let n = Int32(i + 1)
            switch a {
            case let v as Int:    sqlite3_bind_int64(s, n, Int64(v))
            case let v as Double: sqlite3_bind_double(s, n, v)
            case let v as String: sqlite3_bind_text(s, n, v, -1, Self.transient)
            case let v as Data:   _ = v.withUnsafeBytes { sqlite3_bind_blob(s, n, $0.baseAddress, Int32(v.count), Self.transient) }
            default:              sqlite3_bind_null(s, n)
            }
        }
        return s
    }

    private func report(_ sql: String) {
        failures += 1
        NSLog("Tomo store: \(String(cString: sqlite3_errmsg(db))) in \(sql.prefix(60))")
    }
}
