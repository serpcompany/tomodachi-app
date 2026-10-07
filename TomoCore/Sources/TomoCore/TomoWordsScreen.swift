import SwiftUI

// MARK: - Words: every level and its words, with each word's stage (the Mac window's Words page, the iPhone's tab)
//
// Locked levels are listed too, so you can see what's coming. It opens at Tomo's current level; the words per stage
// stay on top. Reads TomoGame.progress (TomoProgress.swift); all text comes from the learner's interface strings and
// the target pack.

public struct TomoWordsScreen: View {
    @ObservedObject var game = TomoGame.shared
    @ObservedObject var lang = TomoLanguages.shared

    public init() {}

    private var progress: TomoProgress { game.progress }
    private var levels: [TargetPack.Level] { progress.pack.levels }

    public var body: some View {
        // Re-read every 30 s so "due in…" stays current; an answer re-renders it too (`game` publishes
        // progressVersion), without rebuilding the list, so the scroll position stays.
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            VStack(spacing: 0) {
                summary
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(1..<levels.count + 1, id: \.self) { n in   // identified by level number
                            levelSection(number: n, level: levels[n - 1])
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, horizontalPadding).padding(.vertical, 10)
                }
                .scrollPosition(id: $shown, anchor: .top)
                .onAppear { if shown == nil { shown = game.level } }
                .onChange(of: game.level) { _, level in shown = level }
            }
        }
    }

    /// The level at the top of the list: it opens at Tomo's level.
    @State private var shown: Int?

    private var horizontalPadding: CGFloat {
        #if os(iOS)
        16
        #else
        24
        #endif
    }

    // MARK: Summary: words per stage (age, level and the bar are on the Tomo screen)

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(["heard", "knows", "good", "loves", "forever"], id: \.self) { g in
                        TomoStagePill(group: g, text: "\(lang.learner("stage.\(g)")) \(progress.count(group: g))")
                    }
                }
                .padding(.horizontal, horizontalPadding)
            }
            if game.isScratch {
                Label(lang.learner("words.testing"), systemImage: "flask")
                    .font(.callout).foregroundStyle(.orange)
                    .padding(.horizontal, horizontalPadding)
            }
        }
        .padding(.vertical, 10)
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
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(lang.learner("words.state.\(state)")).font(.caption).foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(level.itemIDs, id: \.self) { id in
                    wordRow(id, locked: state == "locked")
                    if id != level.itemIDs.last { Divider().padding(.leading, 44) }
                }
            }
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .opacity(state == "locked" ? 0.6 : 1)
        }
        .padding(.top, 6)   // room above the level when it's scrolled to the top
    }

    // MARK: One word: picture, the word, its reading and meaning, its stage and when it's due

    private func wordRow(_ id: String, locked: Bool) -> some View {
        let w = progress.word(id, learner: lang.learner.id)
        let item = progress.items[id]
        return HStack(alignment: .center, spacing: 10) {
            Group {
                if let emoji = w.emoji { Text(emoji).font(.system(size: 22)) }
                else { Image(systemName: "text.bubble").foregroundStyle(.secondary) }   // asked by meaning
            }
            .frame(width: 30)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(w.say).font(.system(size: 15, weight: .semibold))
                    if let r = w.reading { Text(r).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                Text(w.meaning).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                let group = locked && item == nil ? "locked" : TomoSRS.group(item?.stage ?? 0)
                TomoStagePill(group: group, text: lang.learner("stage.\(group)"))
                    .help(item.map { lang.learner("words.stageOf", ["n": "\($0.stage)"]) } ?? "")
                if let due = dueText(item) {
                    Text(due).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }

    private func dueText(_ item: TomoStore.ItemRow?) -> String? {
        guard let item, let due = item.due, item.stage < TomoSRS.forever else { return nil }
        if due <= TomoClock.now { return lang.learner("words.dueNow") }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: lang.learner.id)
        f.unitsStyle = .short
        return lang.learner("words.due", ["when": f.localizedString(for: due, relativeTo: TomoClock.now)])
    }
}

/// A word's stage as a colored capsule: grey (not met, locked) to deep teal, and purple for forever.
public struct TomoStagePill: View {
    let group: String
    let text: String

    public init(group: String, text: String) {
        self.group = group
        self.text = text
    }

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

    public var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
            .fixedSize()
    }
}

extension TomoProgress {
    /// A word as the Words screen shows it: what Tomo says, its reading, its meaning in the learner's language, and
    /// its picture (nil: asked by its meaning).
    public struct WordInfo: Sendable { public let say: String; public let reading: String?; public let meaning: String; public let emoji: String? }

    public func word(_ id: String, learner: String) -> WordInfo {
        if let r = round(id) {
            let emoji = r.need.flatMap(TomoNeed.init(rawValue:))?.emoji ?? r.answer
            return WordInfo(say: r.say, reading: r.romanization, meaning: r.meaning(learner), emoji: emoji)
        }
        if let s = starter(id) {
            return WordInfo(say: s.say, reading: s.romanization, meaning: s.translation(learner), emoji: nil)
        }
        return WordInfo(say: id, reading: nil, meaning: "", emoji: nil)
    }

    /// How many of the learner's words are at a stage group ("heard", "knows", "good", "loves", "forever").
    public func count(group: String) -> Int {
        items.values.filter { TomoSRS.group($0.stage) == group }.count
    }
}
