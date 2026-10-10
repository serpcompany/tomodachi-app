import CloudKit
import Foundation
import Security

// MARK: - iCloud sync: one Tomo across Mac and iPhone (issue #62)
//
// The learner's own iCloud (CloudKit private database, zone "Tomo"), through Apple's CKSyncEngine: no server of
// ours. TomoStore stays the truth on each device. Saving a Tomo or a word marks its record changed
// (TomoStore.didChange); what arrives from another device is merged by the rules in `merge`, which never move
// progress back, and TomoGame reloads. One record per Tomo (level, age, met, last start over) and one per word
// (its stage and wait). Start over wins over older progress: a word record carries the start over it belongs to.
// The answer and growth logs stay on each device for now.
//
// CloudKit tells the other devices about a change with a push notification, and CKSyncEngine fetches when one
// arrives. Debug builds use CloudKit's Development environment, Developer ID and App Store builds Production.
// Off when the build has no iCloud, for testing Tomos (they live in memory), and for test runs (TOMO_DATA_DIR)
// unless they ask for it (TOMO_SYNC=1; docs/verification.md).

@MainActor
public final class TomoSync {
    public static let shared = TomoSync()
    /// The app's iCloud container, named in its Info.plist (`TomoCloudContainer`): the host app's identity, never
    /// TomoCore's. The Mac and iPhone apps name the same one.
    static let containerID = Bundle.main.object(forInfoDictionaryKey: "TomoCloudContainer") as? String
    static let zoneID = CKRecordZone.ID(zoneName: "Tomo")

    public struct Pair: Hashable, Sendable {
        public let learner: String
        public let target: String
        public init(learner: String, target: String) { self.learner = learner; self.target = target }
    }

    /// A Tomo as it syncs: its row plus when this pair last started over (1970: never).
    struct TomoState: Equatable {
        var metAt: Date
        var level: Int
        var age: Int
        var resetAt: Date
    }

    /// Another device's progress was merged into the store: the pairs that changed.
    public var onArrived: ((Set<Pair>) -> Void)?
    /// Set by the shell: register for push notifications (NSApplication / UIApplication), so CloudKit can say
    /// when another device changed Tomo.
    public var registerForPushes: (() -> Void)?
    public var isOn: Bool { engine != nil }

    private var engine: CKSyncEngine?
    private var directory = TomoStore.directory
    private var stores: [Pair: TomoStore] = [:]
    private var fileStore: TomoStore?
    private var fetchTimer: Timer?
    private static let fetchEvery: TimeInterval = 5 * 60
    /// Saves iCloud refused for a reason the engine doesn't retry (say, the schema isn't live yet): sent again on
    /// the next timer tick, and everything again at the next launch (the `cloud-resend` file says so).
    private var retryLater: Set<CKRecord.ID> = []
    /// Words of a newer start over whose Tomo record hasn't arrived yet (a fetch can come in several parts).
    private var waiting: [CKRecord] = []

    /// The CloudKit environment this build signs for (Info.plist TomoICloudEnvironment); nil without iCloud.
    static var environment: String? {
        guard let env = Bundle.main.object(forInfoDictionaryKey: "TomoICloudEnvironment") as? String,
              env == "Production" || env == "Development" else { return nil }
        #if os(macOS)
        // CloudKit stops the app when the entitlement is missing (an unsigned build): check the signature.
        guard let task = SecTaskCreateFromSelf(nil),
              SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-identifiers" as CFString, nil) != nil
        else { return nil }
        #endif
        return env
    }

    /// Starts syncing this device's saved Tomos, if this build and run may.
    public func start() {
        let env = ProcessInfo.processInfo.environment
        guard engine == nil, Self.environment != nil, let containerID = Self.containerID,
              env["TOMO_DATA_DIR"] == nil || env["TOMO_SYNC"] == "1" else { return }
        directory = TomoStore.directory.standardizedFileURL
        guard let file = TomoStore(learner: "", target: "", directory: directory) else { return }
        fileStore = file
        TomoStore.didChange = { [weak self] change in self?.changed(change) }

        let saved = loadState()
        var config = CKSyncEngine.Configuration(
            database: CKContainer(identifier: containerID).privateCloudDatabase,
            stateSerialization: saved, delegate: self)
        config.automaticallySync = true
        let engine = CKSyncEngine(config)
        self.engine = engine
        if saved == nil {                   // first run here: make the zone and send what this device has
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
            queueEverything()
        } else if FileManager.default.fileExists(atPath: resendURL.path) {
            queueEverything()
        }
        try? FileManager.default.removeItem(at: resendURL)
        registerForPushes?()
        // Pushes can be late or dropped: look now and then too, and when asked (the app comes to the front).
        fetchTimer = Timer.scheduledTimer(withTimeInterval: Self.fetchEvery, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.retryRefused()
                self?.fetchSoon()
            }
        }
        fetchSoon()
    }

    /// Look for changes from other devices (the iPhone calls it when the app comes to the front).
    public func fetchSoon() {
        guard let engine else { return }
        Task { try? await engine.fetchChanges() }
    }

    private func retryRefused() {
        guard let engine, !retryLater.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: retryLater.map { .saveRecord($0) })
        retryLater = []
    }

    // MARK: Local changes → pending records

    private func changed(_ c: TomoStore.Change) {
        guard let engine, c.directory.standardizedFileURL == directory else { return }
        let pair = Pair(learner: c.learner, target: c.target)
        switch c.kind {
        case .tomo:
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(Self.tomoID(pair))])
        case .item(let id):
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(Self.itemID(pair, id))])
        case .cleared(let words):
            let ids = words.map { Self.itemID(pair, $0) }
            dropPendingSaves(Set(ids))      // they would send the old Tomo's words
            engine.state.add(pendingRecordZoneChanges: ids.map { .deleteRecord($0) } + [.saveRecord(Self.tomoID(pair))])
        }
    }

    private func dropPendingSaves(_ ids: Set<CKRecord.ID>) {
        guard let engine else { return }
        engine.state.remove(pendingRecordZoneChanges: engine.state.pendingRecordZoneChanges.filter {
            if case .saveRecord(let id) = $0 { return ids.contains(id) }
            return false
        })
    }

    /// Every saved Tomo and word on this device (first run, or a new iCloud account).
    private func queueEverything() {
        guard let engine, let file = fileStore else { return }
        var changes: [CKSyncEngine.PendingRecordZoneChange] = []
        for p in file.syncPairs() {
            let pair = Pair(learner: p.learner, target: p.target)
            guard let store = store(pair) else { continue }
            changes.append(.saveRecord(Self.tomoID(pair)))
            changes += store.loadItems().keys.sorted().map { .saveRecord(Self.itemID(pair, $0)) }
        }
        engine.state.add(pendingRecordZoneChanges: changes)
    }

    // MARK: Records

    static func tomoID(_ p: Pair) -> CKRecord.ID {
        CKRecord.ID(recordName: "tomo.\(p.learner).\(p.target)", zoneID: zoneID)
    }

    static func itemID(_ p: Pair, _ item: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "item.\(p.learner).\(p.target).\(item)", zoneID: zoneID)
    }

    /// `tomo.<learner>.<target>` or `item.<learner>.<target>.<item id>`.
    static func parse(_ id: CKRecord.ID) -> (pair: Pair, item: String?)? {
        let parts = id.recordName.split(separator: ".", maxSplits: 3).map(String.init)
        switch (parts.first, parts.count) {
        case ("tomo", 3): return (Pair(learner: parts[1], target: parts[2]), nil)
        case ("item", 4): return (Pair(learner: parts[1], target: parts[2]), parts[3])
        default: return nil
        }
    }

    private func store(_ pair: Pair) -> TomoStore? {
        if let s = stores[pair] { return s }
        let s = TomoStore(learner: pair.learner, target: pair.target, directory: directory)
        stores[pair] = s
        return s
    }

    /// The record to send for a pending save, from the store as it is now; nil when it's gone.
    private func record(for id: CKRecord.ID) -> CKRecord? {
        guard let (pair, item) = Self.parse(id), let store = store(pair), let tomo = store.syncTomo() else {
            engine?.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
            return nil
        }
        let record = known(id, type: item == nil ? "Tomo" : "Item")
        record["learner"] = pair.learner
        record["target"] = pair.target
        if let item {
            guard let row = store.loadItems()[item] else {
                engine?.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
                return nil
            }
            record["item"] = item
            record["life"] = tomo.resetAt
            record["stage"] = row.stage
            record["due"] = row.due
            record["introduced"] = row.introduced
            record["answered"] = row.answered
            record["right"] = row.right
            record["wrong"] = row.wrong
            record["peak"] = row.peak
        } else {
            record["metAt"] = tomo.row.metAt
            record["level"] = tomo.row.level
            record["age"] = tomo.row.age
            record["resetAt"] = tomo.resetAt
        }
        return record
    }

    /// The record with the CloudKit fields we last saw (so a save isn't a conflict), or a new one.
    private func known(_ id: CKRecord.ID, type: String) -> CKRecord {
        if let data = fileStore?.cloudFields(id.recordName),
           let coder = try? NSKeyedUnarchiver(forReadingFrom: data) {
            coder.requiresSecureCoding = true
            defer { coder.finishDecoding() }
            if let r = CKRecord(coder: coder), r.recordID == id { return r }
        }
        return CKRecord(recordType: type, recordID: id)
    }

    private func remember(_ record: CKRecord) {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        fileStore?.setCloudFields(record.recordID.recordName, coder.encodedData)
    }

    static func tomoState(_ r: CKRecord) -> TomoState? {
        guard let met = r["metAt"] as? Date, let level = r["level"] as? Int, let age = r["age"] as? Int else { return nil }
        return TomoState(metAt: met, level: level, age: age, resetAt: r["resetAt"] as? Date ?? .init(timeIntervalSince1970: 0))
    }

    static func itemRow(_ r: CKRecord) -> TomoStore.ItemRow? {
        guard let id = r["item"] as? String, let stage = r["stage"] as? Int, let introduced = r["introduced"] as? Date,
              let answered = r["answered"] as? Date else { return nil }
        return TomoStore.ItemRow(id: id, stage: stage, due: r["due"] as? Date, introduced: introduced, answered: answered,
                                 right: r["right"] as? Int ?? 0, wrong: r["wrong"] as? Int ?? 0,
                                 peak: max(r["peak"] as? Int ?? 0, stage))
    }

    // MARK: Merge rules (they never move progress back)

    /// A newer start over wins (`reset`: clear this device's words); otherwise the higher level and age and the
    /// earlier meeting. A device meeting the iCloud Tomo for the first time (`first`) didn't miss that start over:
    /// its own Tomo joins in, whenever it hatched.
    static func mergeTomo(local: TomoState?, remote: TomoState, first: Bool = false) -> (tomo: TomoState, reset: Bool) {
        guard let local else { return (remote, false) }
        if !first, remote.resetAt > local.resetAt { return (remote, true) }
        if !first, remote.resetAt < local.resetAt { return (local, false) }
        return (TomoState(metAt: min(local.metAt, remote.metAt), level: max(local.level, remote.level),
                          age: max(local.age, remote.age), resetAt: max(local.resetAt, remote.resetAt)), false)
    }

    /// The copy answered last decides the stage and wait; the best stage and the counts take the higher, the first
    /// meeting the earlier.
    static func mergeItem(local: TomoStore.ItemRow?, remote: TomoStore.ItemRow) -> TomoStore.ItemRow {
        guard let local else { return remote }
        var m = remote.answered > local.answered ? remote : local
        m.introduced = min(local.introduced, remote.introduced)
        m.peak = max(local.peak, remote.peak, m.stage)
        m.right = max(local.right, remote.right)
        m.wrong = max(local.wrong, remote.wrong)
        return m
    }

    /// Merges one record from iCloud into the store. Returns the pair if this device's progress changed.
    @discardableResult
    private func merge(_ r: CKRecord) -> Pair? {
        guard let engine, let (pair, item) = Self.parse(r.recordID), let store = store(pair) else { return nil }
        let local = store.syncTomo().map { TomoState(metAt: $0.row.metAt, level: $0.row.level, age: $0.row.age,
                                                     resetAt: $0.resetAt) }
        if item == nil {
            guard let remote = Self.tomoState(r) else { return nil }
            let first = fileStore?.cloudFields(r.recordID.recordName) == nil
            remember(r)
            let m = Self.mergeTomo(local: local, remote: remote, first: first)
            if m.reset {
                dropPendingSaves(Set(store.loadItems().keys.map { Self.itemID(pair, $0) }))
                store.syncClear(resetAt: remote.resetAt)
            }
            if m.tomo != local || m.reset {
                store.syncWriteTomo(.init(metAt: m.tomo.metAt, level: m.tomo.level, age: m.tomo.age), resetAt: m.tomo.resetAt)
            }
            if m.tomo != remote { engine.state.add(pendingRecordZoneChanges: [.saveRecord(r.recordID)]) }
            if !m.reset, let local, m.tomo.resetAt > local.resetAt {   // joined: send our words as part of it
                engine.state.add(pendingRecordZoneChanges: store.loadItems().keys.sorted().map { .saveRecord(Self.itemID(pair, $0)) })
            }
            return m.tomo != local || m.reset ? pair : nil
        }
        guard let remote = Self.itemRow(r) else { return nil }
        let life = r["life"] as? Date ?? .init(timeIntervalSince1970: 0)
        let ours = local?.resetAt ?? .init(timeIntervalSince1970: 0)
        if life > ours {                    // its Tomo record hasn't been merged yet: after it is
            waiting.append(r)
            return nil
        }
        remember(r)
        if life < ours {                    // a word of a Tomo that has since started over
            engine.state.add(pendingRecordZoneChanges: [.deleteRecord(r.recordID)])
            return nil
        }
        let before = store.loadItems()[remote.id]
        let m = Self.mergeItem(local: before, remote: remote)
        if m != before { store.syncWriteItem(m) }
        if m != remote { engine.state.add(pendingRecordZoneChanges: [.saveRecord(r.recordID)]) }
        return m != before ? pair : nil
    }

    private func arrived(_ records: [CKRecord]) {
        // Tomos first: a newer start over clears the old words before any word is merged. Then the words that
        // were waiting for their Tomo.
        let earlier = waiting
        waiting = []
        let ordered = records.filter { $0.recordType == "Tomo" } + records.filter { $0.recordType != "Tomo" } + earlier
        let changed = Set(ordered.compactMap { merge($0) })
        if !changed.isEmpty { onArrived?(changed) }
    }

    private func sent(_ e: CKSyncEngine.Event.SentRecordZoneChanges) {
        guard let engine else { return }
        e.savedRecords.forEach(remember)
        e.deletedRecordIDs.forEach { fileStore?.setCloudFields($0.recordName, nil) }
        var retry: [CKSyncEngine.PendingRecordZoneChange] = []
        var conflicts: [CKRecord] = []
        for failure in e.failedRecordSaves {
            let id = failure.record.recordID
            switch failure.error.code {
            case .serverRecordChanged:      // another device saved it first: merge theirs, send ours on top
                if let server = failure.error.serverRecord { conflicts.append(server) }
            case .zoneNotFound:
                engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
                fileStore?.setCloudFields(id.recordName, nil)
                retry.append(.saveRecord(id))
            case .unknownItem:              // deleted on the server since we saw it
                fileStore?.setCloudFields(id.recordName, nil)
                retry.append(.saveRecord(id))
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .requestRateLimited,
                 .notAuthenticated, .accountTemporarilyUnavailable, .operationCancelled:
                break                       // the engine tries again by itself
            default:
                NSLog("Tomo sync: couldn't save \(id.recordName): \(failure.error.localizedDescription)")
                retryLater.insert(id)
                FileManager.default.createFile(atPath: resendURL.path, contents: nil)
            }
        }
        engine.state.add(pendingRecordZoneChanges: retry)
        if !conflicts.isEmpty { arrived(conflicts) }
    }

    private func accountChanged(_ e: CKSyncEngine.Event.AccountChange) {
        switch e.changeType {
        case .signIn:
            queueEverything()
        case .switchAccounts:               // this device's Tomo goes to the new account
            fileStore?.clearCloudFields()
            queueEverything()
        case .signOut:
            fileStore?.clearCloudFields()
        @unknown default:
            break
        }
    }

    // MARK: Self-test (TOMO_SELFTEST=1) and the two-folder check (TOMO_SYNC_CHECK)

    /// The merge rules and the store's sync columns, in a temporary folder. No iCloud.
    public static func selfTest() -> Bool {
        var ok = true
        func check(_ c: Bool, _ what: String) {
            print((c ? "ok    " : "FAIL  ") + what)
            if !c { ok = false }
        }
        let t0 = Date(timeIntervalSince1970: 1_800_000_000), never = Date(timeIntervalSince1970: 0)
        func day(_ n: Double) -> Date { t0.addingTimeInterval(n * 86400) }
        let mac = TomoState(metAt: day(0), level: 4, age: 1, resetAt: never)
        let phone = TomoState(metAt: day(-2), level: 2, age: 2, resetAt: never)
        let both = mergeTomo(local: mac, remote: phone)
        check(both.tomo == TomoState(metAt: day(-2), level: 4, age: 2, resetAt: never) && !both.reset,
              "two Tomos merge: the higher level and age, the earlier meeting")
        let restarted = TomoState(metAt: day(5), level: 1, age: 1, resetAt: day(5))
        let r = mergeTomo(local: mac, remote: restarted)
        check(r.tomo == restarted && r.reset, "a newer start over on the other device wins and clears the words here")
        check(mergeTomo(local: restarted, remote: mac).tomo == restarted, "an older Tomo can't come back after a start over")
        let joined = mergeTomo(local: phone, remote: restarted, first: true)
        check(!joined.reset && joined.tomo == TomoState(metAt: day(-2), level: 2, age: 2, resetAt: day(5)),
              "a device meeting the iCloud Tomo for the first time joins it, even after a start over elsewhere")

        typealias Item = TomoStore.ItemRow
        let early = Item(id: "ja:wanwan", stage: 5, due: day(7), introduced: day(-9), answered: day(0), right: 6, wrong: 1, peak: 5)
        let late = Item(id: "ja:wanwan", stage: 4, due: day(2), introduced: day(-3), answered: day(1), right: 3, wrong: 2, peak: 4)
        let w = mergeItem(local: early, remote: late)
        check(w.stage == 4 && w.due == day(2) && w.answered == day(1), "a word: the copy answered last decides its stage and wait")
        check(w.peak == 5 && w.right == 6 && w.wrong == 2 && w.introduced == day(-9),
              "a word: the best stage, the counts and the first meeting are kept")
        check(mergeItem(local: nil, remote: late) == late, "a word only the other device knows is added")

        let pair = Pair(learner: "en", target: "ja")
        check(parse(itemID(pair, "ja:inaiinaibaa"))?.item == "ja:inaiinaibaa" && parse(tomoID(pair))?.pair == pair,
              "record names round-trip")

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tomo-sync-selftest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        guard let store = TomoStore(learner: "en", target: "ja", directory: dir) else {
            check(false, "the store opens"); return false
        }
        var heard: [TomoStore.Change.Kind] = []
        let listener = TomoStore.didChange
        TomoStore.didChange = { heard.append($0.kind) }
        defer { TomoStore.didChange = listener }
        store.saveTomo(.init(metAt: day(0), level: 3, age: 1))
        store.saveItem(early)
        store.clear(at: day(3))
        store.saveTomo(.init(metAt: day(3), level: 1, age: 1))                  // the new Tomo hatches
        let saved = store.syncTomo()
        check(saved?.resetAt == day(3) && saved?.row.level == 1 && store.loadItems().isEmpty,
              "start over is remembered, and the new Tomo keeps that time")
        if case .cleared(let words) = heard.dropLast().last { check(words == ["ja:wanwan"], "start over reports its words")
        } else { check(false, "start over reports its words") }
        check(heard.count == 4, "each save is reported: \(heard.count)")
        let before = heard.count
        store.syncWriteItem(late)
        check(heard.count == before && store.loadItems()["ja:wanwan"] == late, "what arrives is saved without echoing back")
        store.setCloudFields("tomo.en.ja", Data([1, 2, 3]))
        check(store.cloudFields("tomo.en.ja") == Data([1, 2, 3]), "CloudKit's record fields are kept")
        return ok
    }

    /// Sync from a test folder (TOMO_SYNC_CHECK with TOMO_DATA_DIR and TOMO_SYNC=1, a Debug build: CloudKit's
    /// Development environment). `play:N` fetches, answers N new words and sends; `blind:N` does the same without
    /// fetching first (a device that was offline: its saves conflict); `reset` starts over; `show` only fetches.
    /// Prints this pair's Tomo. CloudKit doesn't send a device its own changes, so a second folder on the same Mac
    /// sees them only on its first fetch (docs/verification.md).
    public static func check(_ step: String) async -> Bool {
        let sync = TomoSync.shared
        sync.start()
        guard let engine = sync.engine else {
            print("FAIL  sync is off: it needs a build with iCloud, and TOMO_SYNC=1 with TOMO_DATA_DIR")
            return false
        }
        let lang = TomoLanguages.shared
        do {
            if !step.hasPrefix("blind:") { try await engine.fetchChanges() }
            let p = TomoProgress(pack: lang.target, learner: lang.learner.id)
            if let n = Int(step.split(separator: ":").last ?? ""), step.hasPrefix("play:") || step.hasPrefix("blind:") {
                for id in p.newItems.prefix(n) { p.answeredRight(id, mode: "picture", wrongTries: 0, hint: false) }
            } else if step == "reset" {
                p.startOver()
            }
            // A conflict fails the send; it's merged and queued again, so send until nothing is left.
            for _ in 0..<4 where !engine.state.pendingRecordZoneChanges.isEmpty || !engine.state.pendingDatabaseChanges.isEmpty {
                do { try await engine.sendChanges() } catch let e as CKError where e.code == .partialFailure { continue }
            }
            let now = TomoProgress(pack: lang.target, learner: lang.learner.id)
            let words = now.items.values.sorted { $0.id < $1.id }.map { "\($0.id)=\($0.stage)" }
            print("tomo level=\(now.level) age=\(now.age) met=\(Int(now.metAt.timeIntervalSince1970)) words=\(words.count) "
                  + "unsent=\(engine.state.pendingRecordZoneChanges.count)")
            print("words " + words.joined(separator: " "))
            return engine.state.pendingRecordZoneChanges.isEmpty
        } catch {
            print("FAIL  \(error)")
            return false
        }
    }

    // MARK: Engine state (TomoStore.directory/cloud-state.json, cloud-resend)

    private var stateURL: URL { directory.appendingPathComponent("cloud-state.json") }
    private var resendURL: URL { directory.appendingPathComponent("cloud-resend") }

    private func loadState() -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func saveState(_ s: CKSyncEngine.State.Serialization) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }
}

extension TomoSync: CKSyncEngineDelegate {
    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let e):
            saveState(e.stateSerialization)
        case .accountChange(let e):
            accountChanged(e)
        case .fetchedDatabaseChanges(let e):
            if e.deletions.contains(where: { $0.zoneID == Self.zoneID }) {   // iCloud data deleted: send ours again
                fileStore?.clearCloudFields()
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
                queueEverything()
            }
        case .fetchedRecordZoneChanges(let e):
            arrived(e.modifications.map(\.record))
            e.deletions.forEach { fileStore?.setCloudFields($0.recordID.recordName, nil) }
        case .sentRecordZoneChanges(let e):
            sent(e)
        case .didFetchChanges:
            if !waiting.isEmpty { arrived([]) }
        default:
            break
        }
    }

    public func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                          syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { id in
            await self.record(for: id)
        }
    }
}
