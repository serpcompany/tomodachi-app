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
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(1..<levels.count + 1, id: \.self) { n in   // identified by level number
                                levelSection(number: n, level: levels[n - 1])
                                    .padding(.horizontal, horizontalPadding)   // inside the target: landing never shifts the list sideways
                            }
                        }
                        .scrollTargetLayout()
                        .padding(.vertical, 10)
                    }
                    .scrollPosition(id: $shown, anchor: .top)
                    // The rows are lazy: the jump to a level estimates the heights above it, which change as they're
                    // measured. Until the learner scrolls, each change lands on the level again, so its header and
                    // first word show under the chips.
                    .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { _, _ in
                        if let landing { proxy.scrollTo(landing, anchor: .top) }
                    }
                    .onScrollPhaseChange { _, phase in
                        if phase == .tracking || phase == .interacting { landing = nil }
                    }
                    .task(id: landing) {
                        guard landing != nil else { return }
                        try? await Task.sleep(for: .seconds(1))
                        landing = nil
                    }
                    .onAppear { if shown == nil { land(game.level) } }
                    .onChange(of: game.level) { _, level in land(level) }
                }
            }
        }
    }

    /// The level at the top of the list: it opens at Tomo's level.
    @State private var shown: Int?
    /// The level the list is landing on, until the learner scrolls or a second has passed.
    @State private var landing: Int?
    /// More stage chips past the row's trailing edge.
    @State private var chipsMore = false

    private func land(_ level: Int) {
        shown = level
        landing = level
    }

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
                    ForEach(TomoStagePill.stages, id: \.self) { g in
                        TomoStagePill(group: g, text: "\(lang.learner("stage.\(g)")) \(progress.count(group: g))")
                    }
                }
                .padding(.horizontal, horizontalPadding)
            }
            // When the chips don't all fit (an iPhone), the trailing edge fades while more are past it, so the row
            // shows it scrolls. A row that fits (the Mac) never fades.
            .onScrollGeometryChange(for: Bool.self) { g in
                g.visibleRect.maxX < g.contentSize.width - 1
            } action: { _, more in
                chipsMore = more
            }
            .mask {
                HStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: chipsMore ? 44 : 0)
                }
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
                if let emoji = w.emoji { TomoPictureView(emoji, size: 22) }   // a dark one on a light disc in dark mode
                else { Image(systemName: "text.bubble").foregroundStyle(.secondary) }   // asked by meaning
            }
            .frame(width: 30)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                // The word never breaks mid-word: its reading goes under it when both don't fit on a line, and a
                // word too long for the line on its own shrinks to fit.
                let say = Text(w.say).font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
                let reading = w.reading.map { Text($0).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) { say.fixedSize(); reading?.fixedSize() }
                    VStack(alignment: .leading, spacing: 1) { say; reading }
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

/// A word's stage as a colored capsule: grey (not met, locked) to deep teal, and purple for forever. Light mode deepens
/// the teal stage by stage; dark mode brightens it, so every stage reads at 5:1 or more on a dark card (#195; checked by
/// `selfTest`).
public struct TomoStagePill: View {
    let group: String
    let text: String
    @Environment(\.colorScheme) private var scheme

    public init(group: String, text: String) {
        self.group = group
        self.text = text
    }

    /// The stage groups that have a colour, from just heard to forever.
    static let stages = ["heard", "knows", "good", "loves", "forever"]

    /// A stage's colour in light or dark mode; nil for one without (not met, locked), drawn in the secondary colour.
    static func hex(_ group: String, dark: Bool) -> String? {
        switch group {
        case "heard":   dark ? "#87BDBA" : "#5BA4A0"
        case "knows":   dark ? "#28D79F" : "#1D9E75"
        case "good":    dark ? "#47E5BE" : "#13876A"
        case "loves":   dark ? "#7EEDD2" : "#0F6E56"
        case "forever": dark ? "#B9ABEB" : "#7B61D9"
        default:        nil
        }
    }

    private var color: Color {
        Self.hex(group, dark: scheme == .dark).map { Color(hex: $0) } ?? .secondary
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

extension TomoStagePill {
    /// The lightest dark card a pill sits on: the Mac's word card measures #282828 in dark mode; the Mac's page and the
    /// iPhone's cards are darker, where a stage reads better still.
    static let darkCard = "#2B2B2B"

    /// The rule (TOMO_SELFTEST, swift test): in dark mode each stage's text reads at 5:1 or more (WCAG contrast) against
    /// its own 15% fill on the dark card, so a palette change can't bring back the 2.1:1 "Loves it" (#195).
    public static func selfTest(_ check: (Bool, String) -> Void) {
        for stage in stages {
            guard let hex = hex(stage, dark: true) else { check(false, "stages: \(stage) has a dark colour"); continue }
            let ratio = contrast(hex, onItsFillOver: darkCard)
            check(ratio >= 5, "stages: \(stage) (\(hex)) reads at \(String(format: "%.2f", ratio)):1 on a dark card, 5:1 or more")
        }
    }

    /// WCAG contrast of text in `hex` against its 15% fill composited over `card`.
    static func contrast(_ hex: String, onItsFillOver card: String) -> Double {
        func rgb(_ hex: String) -> [Double] {
            let v = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
            return [Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255]
        }
        func luminance(_ c: [Double]) -> Double {
            let l = c.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return 0.2126 * l[0] + 0.7152 * l[1] + 0.0722 * l[2]
        }
        let text = rgb(hex), under = rgb(card)
        let fill = zip(text, under).map { 0.15 * $0 + 0.85 * $1 }
        let a = luminance(text), b = luminance(fill)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
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
