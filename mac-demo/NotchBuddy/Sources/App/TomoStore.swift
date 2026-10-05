import Foundation
import SQLite3

// MARK: - Saved progress: one SQLite file on this Mac
//
// ~/Library/Application Support/com.zenbujapanese.tomodachi/learner.sqlite (TOMO_DATA_DIR=<dir> overrides it,
// so test runs never touch the learner's own Tomo). Keyed by (learner language, target language): one Tomo
// per pair. `tomo` and `item` hold the current state; `answer` and `growth` are append-only logs, kept to tune
// the rules later and to sync with the Zenbu apps one day (docs/research/learner-data-schema.md).
// The rules that fill it are in TomoProgress.swift.

@MainActor
final class TomoStore {
    struct TomoRow { let metAt: Date; let level: Int; let age: Int }
    struct ItemRow {
        let id: String
        var stage: Int
        var due: Date?              // nil once burned
        var introduced: Date
        var answered: Date
        var right: Int
        var wrong: Int
        var peak = 0                // the highest stage it ever reached: the experience bar never goes back
    }

    nonisolated(unsafe) private var db: OpaquePointer?
    private let learner: String
    private let target: String

    static var directory: URL {
        if let d = ProcessInfo.processInfo.environment["TOMO_DATA_DIR"] { return URL(fileURLWithPath: d) }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.zenbujapanese.tomodachi")
    }

    init?(learner: String, target: String, directory: URL = TomoStore.directory) {
        self.learner = learner
        self.target = target
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
            """)
        // Added after the first saved Tomos: fails harmlessly once the column exists.
        sqlite3_exec(db, "ALTER TABLE item ADD COLUMN peak INTEGER NOT NULL DEFAULT 0", nil, nil, nil)
    }

    deinit { sqlite3_close(db) }

    // MARK: Tomo

    func loadTomo() -> TomoRow? {
        query("SELECT met_at, level, age FROM tomo WHERE learner = ? AND target = ?", [learner, target]) {
            TomoRow(metAt: Date(timeIntervalSince1970: sqlite3_column_double($0, 0)),
                    level: Int(sqlite3_column_int64($0, 1)), age: Int(sqlite3_column_int64($0, 2)))
        }.first
    }

    func saveTomo(_ t: TomoRow) {
        run("INSERT OR REPLACE INTO tomo (learner, target, met_at, level, age) VALUES (?, ?, ?, ?, ?)",
            [learner, target, t.metAt.timeIntervalSince1970, t.level, t.age])
    }

    // MARK: Items

    func loadItems() -> [String: ItemRow] {
        let rows = query("""
            SELECT item_id, stage, due_at, introduced_at, answered_at, right_count, wrong_count, peak
            FROM item WHERE learner = ? AND target = ?
            """, [learner, target]) { s in
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

    func saveItem(_ i: ItemRow) {
        run("""
            INSERT OR REPLACE INTO item
              (learner, target, item_id, stage, due_at, introduced_at, answered_at, right_count, wrong_count, peak)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [learner, target, i.id, i.stage, i.due?.timeIntervalSince1970, i.introduced.timeIntervalSince1970,
                  i.answered.timeIntervalSince1970, i.right, i.wrong, i.peak])
    }

    // MARK: Logs

    /// One row per answer, counted or not. `result`: right | wrong | help | language.
    func logAnswer(at: Date, item: String?, level: Int, mode: String, result: String, wrongTries: Int,
                   hint: Bool, counted: Bool, before: Int?, after: Int?) {
        run("""
            INSERT INTO answer (at, learner, target, item_id, level, mode, result, wrong_tries, hint, counted,
                                stage_before, stage_after)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [at.timeIntervalSince1970, learner, target, item, level, mode, result, wrongTries,
                  hint ? 1 : 0, counted ? 1 : 0, before, after])
    }

    /// Answers since a time (right and wrong tries), and how many of them moved a word up a stage.
    func answerCounts(since: Date) -> (answers: Int, stronger: Int) {
        query("""
            SELECT COUNT(*),
                   COALESCE(SUM(CASE WHEN counted = 1 AND stage_after > COALESCE(stage_before, 0) THEN 1 ELSE 0 END), 0)
            FROM answer WHERE learner = ? AND target = ? AND at >= ? AND result IN ('right', 'wrong')
            """, [learner, target, since.timeIntervalSince1970]) {
            (Int(sqlite3_column_int64($0, 0)), Int(sqlite3_column_int64($0, 1)))
        }.first ?? (0, 0)
    }

    /// `kind`: level | age | reset.
    func logGrowth(at: Date, kind: String, value: Int) {
        run("INSERT INTO growth (at, learner, target, kind, value) VALUES (?, ?, ?, ?, ?)",
            [at.timeIntervalSince1970, learner, target, kind, value])
    }

    /// Start over: this pair's Tomo and words are cleared; the logs stay.
    func clear(at: Date) {
        run("DELETE FROM item WHERE learner = ? AND target = ?", [learner, target])
        run("DELETE FROM tomo WHERE learner = ? AND target = ?", [learner, target])
        logGrowth(at: at, kind: "reset", value: 0)
    }

    // MARK: SQLite

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func exec(_ sql: String) {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK { report(sql) }
    }

    private func run(_ sql: String, _ args: [Any?]) {
        guard let s = prepare(sql, args) else { return }
        defer { sqlite3_finalize(s) }
        if sqlite3_step(s) != SQLITE_DONE { report(sql) }
    }

    private func query<T>(_ sql: String, _ args: [Any?], _ row: (OpaquePointer) -> T) -> [T] {
        guard let s = prepare(sql, args) else { return [] }
        defer { sqlite3_finalize(s) }
        var out: [T] = []
        while sqlite3_step(s) == SQLITE_ROW { out.append(row(s)) }
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
            default:              sqlite3_bind_null(s, n)
            }
        }
        return s
    }

    private func report(_ sql: String) {
        NSLog("Tomo store: \(String(cString: sqlite3_errmsg(db))) in \(sql.prefix(60))")
    }
}
