# The learner store and sync

Where a Tomo's progress is saved on each device, and how one Tomo follows the learner across their
Mac and iPhone. What a learner sees is in [concepts.md](concepts.md) ("Saved progress"); what the
logs feed is in [stats.md](stats.md); the other systems are mapped in
[architecture.md](architecture.md).

## Learner store

`TomoStore.swift`: one SQLite file on the device, keyed by (learner, target), so each language pair
has its own Tomo. `tomo` and `item` hold the current state; `answer`, `growth` and `visit` (each
time together, from TomoGame) are logs, read by `TomoStats` ([stats.md](stats.md)). Start over
clears the words and notes when (`tomo.reset_at`), never the logs. `TOMO_DATA_DIR` moves the file.
A pair the language rule forbids (ja:ja, from before
[#199](https://github.com/serpcompany/tomodachi-app/issues/199)) moves at launch (`TomoStore.move`): its
Tomo, words and logs go to the pair it's allowed, and every Tomo is sent to iCloud again (`cloud-resend`).
Most ja:ja testers also have the en:ja Tomo their first run hatched: then the two merge by sync's rules, so the
earlier-met Tomo and its look are kept, with its own growth log (the other's stays behind; answers and visits move). The
move is all or nothing: a failed read or write undoes it and keeps the saved pair, so the next launch tries again. The moved Tomo keeps its look in `tomo.seed`, kept while it's
the same Tomo (the same `met_at` second); the seed stays on the device, so another device that only ever
gets this Tomo from iCloud draws it from its own pair's seed. Its old records stay in iCloud, where no allowed pair reads them.
Planned: Language Reference IDs as item ids and sync with the Zenbu apps
([#28](https://github.com/serpcompany/tomodachi-app/issues/28)).

## Sync

`TomoSync.swift`: one Tomo across the learner's Mac and iPhone through their own iCloud (CloudKit
private database, zone `Tomo`, container `iCloud.com.zenbujapanese.tomo`) with Apple's
`CKSyncEngine`; no server of ours. `TomoStore` stays the truth on each device: a save reports itself
(`TomoStore.didChange`) and becomes a pending record, one per Tomo and one per word; what arrives is
merged (`mergeTomo`, `mergeItem`) and written back without echoing, then `TomoGame` reloads.
Invariants: a merge never moves progress back (the higher level and age, the copy of a word answered
last, its best stage); a start over wins over older progress, and each word record carries the start
over it belongs to; a device meeting the iCloud Tomo for the first time joins it. CloudKit pushes
tell the other devices (the shells register through `TomoSync.registerForPushes`); a timer and the
iPhone coming to the front fetch too. Debug builds use CloudKit's Development environment, Developer
ID and App Store builds Production. The logs and settings stay on each device for now.
