import SwiftUI
import TomoCore

// MARK: - Settings → Words: every level and its words, with each word's stage
//
// Opened from the menu bar ("Tomo's words…") or the sidebar in Settings. Locked levels are listed too,
// so you can see what's coming. Reads TomoGame.progress (TomoProgress.swift); all text comes from the
// learner's interface strings and the target pack.

struct TomoWordsPane: View {
    @ObservedObject var game = TomoGame.shared
    @ObservedObject var lang = TomoLanguages.shared

    private var progress: TomoProgress { game.progress }
    private var levels: [TargetPack.Level] { progress.pack.levels }

    var body: some View {
        // Re-read every 30 s so "due in…" stays current; game.progressVersion re-renders after each answer.
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    summary
                    ForEach(Array(levels.enumerated()), id: \.offset) { i, level in
                        levelSection(number: i + 1, level: level)
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 14)
                .id(game.progressVersion)
            }
        }
    }

    // MARK: Summary: words per stage (age, level and the level bar are on the Tomo page)

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(["heard", "knows", "good", "loves", "forever"], id: \.self) { g in
                    StagePill(group: g, text: "\(lang.learner("stage.\(g)")) \(count(group: g))")
                }
            }
            if game.isScratch {
                Label(lang.learner("words.testing"), systemImage: "flask")
                    .font(.callout).foregroundStyle(.orange)
            }
        }
    }

    private func count(group: String) -> Int {
        progress.items.values.filter { TomoSRS.group($0.stage) == group }.count
    }

    // MARK: One level

    private func levelSection(number: Int, level: TargetPack.Level) -> some View {
        let state = number < game.level ? "done" : number == game.level ? "now" : "locked"
        let previousAge = number > 1 ? levels[number - 2].age : 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: state == "done" ? "checkmark.circle.fill" : state == "now" ? "location.circle.fill" : "lock.fill")
                    .foregroundStyle(state == "done" ? Color.teal : state == "now" ? Color.orange : Color.secondary)
                Text(lang.learner("level", ["n": "\(number)"])).font(.headline)
                Text(lang.target.ageLabel(level.age)).font(.subheadline).foregroundStyle(.secondary)
                if level.age > previousAge && number > 1 {
                    Label(lang.learner("words.birthday", ["age": lang.target.ageLabel(level.age)]),
                          systemImage: "birthday.cake")
                        .font(.caption).foregroundStyle(.orange)
                }
                Spacer()
                Text(lang.learner("words.state.\(state)")).font(.caption).foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(level.itemIDs, id: \.self) { id in
                    wordRow(id, locked: state == "locked")
                    if id != level.itemIDs.last { Divider().padding(.leading, 44) }
                }
            }
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .opacity(state == "locked" ? 0.6 : 1)
        }
    }

    // MARK: One word: picture, the word, its reading and meaning, its stage and when it's due

    private func wordRow(_ id: String, locked: Bool) -> some View {
        let w = word(id)
        let item = progress.items[id]
        return HStack(alignment: .center, spacing: 10) {
            Group {
                if let emoji = w.emoji { Text(emoji).font(.system(size: 22)) }
                else { Image(systemName: "text.bubble").foregroundStyle(.secondary) }   // asked by meaning
            }
            .frame(width: 30)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(w.say).font(.system(size: 15, weight: .semibold))
                    if let r = w.reading { Text(r).font(.caption).foregroundStyle(.secondary) }
                }
                Text(w.meaning).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                let group = locked && item == nil ? "locked" : TomoSRS.group(item?.stage ?? 0)
                StagePill(group: group, text: lang.learner("stage.\(group)"))
                    .help(item.map { lang.learner("words.stageOf", ["n": "\($0.stage)"]) } ?? "")
                if let due = dueText(item) {
                    Text(due).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
    }

    private struct Word { let say: String; let reading: String?; let meaning: String; let emoji: String? }

    private func word(_ id: String) -> Word {
        if let r = progress.round(id) {
            let emoji = r.need.flatMap(TomoNeed.init(rawValue:))?.emoji ?? r.answer
            return Word(say: r.say, reading: r.romanization, meaning: r.meaning(lang.learner.id), emoji: emoji)
        }
        if let s = progress.starter(id) {
            return Word(say: s.say, reading: s.romanization, meaning: s.translation(lang.learner.id), emoji: nil)
        }
        return Word(say: id, reading: nil, meaning: "", emoji: nil)
    }

    private func dueText(_ item: TomoStore.ItemRow?) -> String? {
        guard let item, let due = item.due else { return nil }
        if due <= TomoClock.now { return lang.learner("words.dueNow") }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: lang.learner.id)
        f.unitsStyle = .short
        return lang.learner("words.due", ["when": f.localizedString(for: due, relativeTo: TomoClock.now)])
    }
}

/// A word's stage as a colored capsule: grey (not met, locked) to deep teal (forever).
private struct StagePill: View {
    let group: String
    let text: String

    private var color: Color {
        switch group {
        case "heard":   return Color(hex: "#5BA4A0")
        case "knows":   return Color(hex: "#1D9E75")
        case "good":    return Color(hex: "#13876A")
        case "loves":   return Color(hex: "#0F6E56")
        case "forever": return Color(hex: "#7B61D9")
        default:        return .secondary
        }
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
            .fixedSize()
    }
}
