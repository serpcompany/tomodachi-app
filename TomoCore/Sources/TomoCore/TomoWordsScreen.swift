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
                                    // The level it's landing on, as it's laid out: when it moves, land on it again.
                                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.list)).minY } action: { top in
                                        if n == landing.level, landing.laidOut(top: top, at: .now) { proxy.scrollTo(n, anchor: .top) }
                                    }
                                    .onDisappear { if n == landing.level { _ = landing.laidOut(top: nil, at: .now) } }
                            }
                        }
                        .scrollTargetLayout()
                        .coordinateSpace(.named(Self.list))
                        .padding(.vertical, 10)
                    }
                    .scrollPosition(id: $shown, anchor: .top)
                    // The rows are lazy: the jump to a level estimates the heights above it, which move it as they're
                    // laid out. The list lands on it again until the learner scrolls or it holds still (TomoLanding).
                    .onScrollGeometryChange(for: TomoLanding.Geometry.self) { g in
                        TomoLanding.Geometry(height: g.contentSize.height, offset: g.contentOffset.y,
                                             maxOffset: g.contentSize.height + g.contentInsets.bottom - g.containerSize.height)
                    } action: { old, new in
                        if landing.changed(from: old, to: new, at: .now), let level = landing.level {
                            proxy.scrollTo(level, anchor: .top)
                        }
                    }
                    .onScrollPhaseChange { _, phase in
                        if phase != .idle { landing.scrolled() }
                    }
                    // Still for a moment since the last landing: the list is the learner's.
                    .task(id: landing.count) {
                        guard landing.level != nil else { return }
                        do { try await Task.sleep(for: .seconds(TomoLanding.still)) } catch { return }
                        landing.tick(at: .now)
                    }
                    .onAppear { if shown == nil { land(game.level) } }
                    .onChange(of: game.level) { _, level in land(level) }
                }
            }
        }
    }

    /// The level at the top of the list: it opens at Tomo's level.
    @State private var shown: Int?
    /// Landing on Tomo's level, until the learner scrolls or the list holds still.
    @State private var landing = TomoLanding()
    /// The list's content, where a level's place doesn't change as it scrolls.
    private static let list = "words.list"
    /// More stage chips past the row's trailing edge.
    @State private var chipsMore = false
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The space between a reading's words, which grows with its text.
    @ScaledMetric(relativeTo: .caption) private var readingSpace: CGFloat = 3
    @ScaledMetric(relativeTo: .callout) private var meaningSpace: CGFloat = 4

    private func land(_ level: Int) {
        shown = level
        landing.start(level, at: .now)
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
            .accessibilityIdentifier("words.stages")
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
        let mark = HStack(spacing: 8) {
            Image(systemName: state == "done" ? "checkmark.circle.fill" : state == "now" ? "location.circle.fill" : "lock.fill")
                .foregroundStyle(state == "done" ? Color.teal : state == "now" ? Color.orange : Color.secondary)
            Text(lang.learner("level", ["n": "\(number)"])).font(.headline)
                .accessibilityIdentifier("words.level.\(number)")
        }
        let age = Text(lang.target.ageLabel(level.age)).font(.subheadline).foregroundStyle(.secondary)
        let birthday = level.age > previousAge && number > 1
            ? Label(lang.learner("words.birthday", ["age": lang.target.ageLabel(level.age)]), systemImage: "birthday.cake")
                .font(.caption).foregroundStyle(.orange)
            : nil
        let status = Text(lang.learner("words.state.\(state)")).font(.caption).foregroundStyle(.secondary)
        return VStack(alignment: .leading, spacing: 6) {
            // On one line, or wrapped between its parts when they don't all fit (large text): none is cut short.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    mark.fixedSize(); age.fixedSize(); birthday?.fixedSize()
                    Spacer(minLength: 4)
                    status.fixedSize()
                }
                TomoFlowLayout(spacing: 8, lineSpacing: 2) { mark; age; birthday; status }
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
        // At the accessibility text sizes the stage and when it's due go under the meaning, so the word and its
        // meaning keep the row's width.
        let stacked = typeSize.isAccessibilitySize
        return HStack(alignment: stacked ? .top : .center, spacing: 10) {
            Group {
                if let emoji = w.emoji { TomoPictureView(emoji, size: 22) }   // a dark one on a light disc in dark mode
                else { Image(systemName: "text.bubble").foregroundStyle(.secondary) }   // asked by meaning
            }
            .frame(width: 30)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)   // the bubble stays inside its column at the largest text
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                // The word and its reading on one line, or the reading under the word when both don't fit. Either
                // wraps only at its spaces, and a word too long for the line on its own shrinks to fit: nothing
                // breaks mid-word ("イナイイ / ナイバー！") or ends in "…".
                let say = Font.system(size: 15, weight: .semibold)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(w.say).font(say).fixedSize()
                        if let r = w.reading { Text(r).font(.caption).foregroundStyle(.secondary).fixedSize() }
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        TomoWordFlow(text: w.say, spacing: 4, lineSpacing: 0).font(say)
                            .accessibilityElement(children: .ignore).accessibilityLabel(w.say)
                        if let r = w.reading {
                            TomoWordFlow(text: r, spacing: readingSpace, lineSpacing: 0).font(.caption).foregroundStyle(.secondary)
                                .accessibilityElement(children: .ignore).accessibilityLabel(r)
                        }
                    }
                }
                // The meaning wraps at its spaces too; only a word longer than the line breaks inside.
                TomoFlowLayout(spacing: meaningSpace, lineSpacing: 0) {
                    ForEach(Array(w.meaning.split(separator: " ").enumerated()), id: \.offset) { _, word in Text(word) }
                }
                .font(.callout).foregroundStyle(.secondary)
                .accessibilityElement(children: .ignore).accessibilityLabel(w.meaning)
                if stacked { stage(item, locked: locked, alignment: .leading).padding(.top, 4) }
            }
            if !stacked {
                Spacer(minLength: 8)
                stage(item, locked: locked, alignment: .trailing)
            }
        }
        // Every row starts at the card's leading edge: a stacked row has no spacer, and the card would centre it.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("words.word.\(id)")
    }

    /// A word's stage, and when it's due.
    private func stage(_ item: TomoStore.ItemRow?, locked: Bool, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            let group = locked && item == nil ? "locked" : TomoSRS.group(item?.stage ?? 0)
            TomoStagePill(group: group, text: lang.learner("stage.\(group)"))
                .help(item.map { lang.learner("words.stageOf", ["n": "\($0.stage)"]) } ?? "")
            if let due = dueText(item) {
                Text(due).font(.caption2).foregroundStyle(.secondary)
            }
        }
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

    /// The darkest light card a pill sits on: the Mac's word card measures #F4F4F4 in light mode; the Mac's page is
    /// white, where a stage reads better still. The iPhone is always dark.
    static let lightCard = "#F2F2F2"

    /// The rule (TOMO_SELFTEST, swift test): in each mode each stage's text reads at 5:1 or more (WCAG contrast) against
    /// its own 15% fill on that mode's card, so a palette change can't bring back the 2.1:1 "Loves it" in dark mode
    /// (#195) or the 2.3:1 "Just heard" in light mode (#207).
    public static func selfTest(_ check: (Bool, String) -> Void) {
        for (dark, card) in [(true, darkCard), (false, lightCard)] {
            let mode = dark ? "dark" : "light"
            for stage in stages {
                guard let hex = hex(stage, dark: dark) else { check(false, "stages: \(stage) has a \(mode) colour"); continue }
                let ratio = contrast(hex, onItsFillOver: card)
                check(ratio >= 5, "stages: \(stage) (\(hex)) reads at \(String(format: "%.2f", ratio)):1 on a \(mode) card, 5:1 or more")
            }
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

// MARK: - Landing on Tomo's level (#193)

/// When Words lands on Tomo's level, and when the list becomes the learner's. The rows are lazy, so the first jump to
/// the level estimates the heights above it, and the level moves as they're laid out: each time it moves, the list
/// lands on it again, so its header and first word show under the chips. Rows laid out below it don't move it, so
/// they don't land. The list is the learner's from whichever comes first:
/// - a scroll phase other than idle (a drag, a trackpad, a mouse wheel);
/// - the list moving when no landing moved it: the keyboard or VoiceOver may scroll with no phase;
/// - `still` with nothing to land on again.
/// Plain values in, so `selfTest` checks it without a screen.
public struct TomoLanding: Equatable, Sendable {
    /// What the rule reads of the list: its content's height, how far it's scrolled, and how far it can be.
    public struct Geometry: Equatable, Sendable {
        public var height: CGFloat, offset: CGFloat, maxOffset: CGFloat
        public init(height: CGFloat, offset: CGFloat, maxOffset: CGFloat) {
            self.height = height; self.offset = offset; self.maxOffset = maxOffset
        }
    }

    /// How long the level holds still before the list is the learner's (it settles in a few quick moves).
    public static let still: TimeInterval = 0.5
    /// How soon a landing moves the list: SwiftUI moves it within about 0.15 s (the first jump there, back and there
    /// again as it measures). A move later than this, with no landing since, is the learner's.
    public static let settle: TimeInterval = 0.3

    /// The level it's landing on; nil once the list is the learner's.
    public private(set) var level: Int?
    /// Counts the landings, so the view's timer starts over with each.
    public private(set) var count = 0
    /// The level's top in the list's content; nil while it isn't laid out.
    private var top: CGFloat?
    private var landedAt = Date.distantPast

    public init() {}

    /// Lands on `level` (Words opens, or Tomo's level changes).
    public mutating func start(_ level: Int, at now: Date) {
        self.level = level
        top = nil
        land(at: now)
    }

    /// The level's top in the list's content, as it's laid out (nil: no longer laid out). True: land on it again.
    public mutating func laidOut(top new: CGFloat?, at now: Date) -> Bool {
        guard level != nil else { return false }
        defer { top = new }
        guard let new, let top, abs(new - top) > 0.5 else { return false }   // first laid out where the jump put it
        land(at: now)
        return true
    }

    /// The list's geometry changed. True: land again, when the level isn't laid out and the list's height changed.
    public mutating func changed(from old: Geometry, to new: Geometry, at now: Date) -> Bool {
        guard level != nil else { return false }
        let grew = abs(new.height - old.height) > 0.5
        if abs(new.offset - old.offset) > 0.5 {
            // A list that got shorter under one scrolled to its end pulls the offset back with it.
            let clamped = grew && new.height < old.height && new.offset >= new.maxOffset - 0.5
            if now.timeIntervalSince(landedAt) >= Self.settle && !clamped {   // moved when nothing landed: the learner scrolled
                level = nil
                return false
            }
        }
        guard grew, top == nil else { return false }
        land(at: now)
        return true
    }

    /// A scroll phase other than idle: the learner is scrolling.
    public mutating func scrolled() { level = nil }

    /// The view's timer, `still` after a landing: if nothing landed since, the list is the learner's.
    public mutating func tick(at now: Date) {
        if now.timeIntervalSince(landedAt) >= Self.still { level = nil }
    }

    private mutating func land(at now: Date) {
        landedAt = now
        count += 1
    }
}

extension TomoLanding {
    /// The rule (TOMO_SELFTEST, swift test), on made-up geometry of a list 600 pt tall: the list lands again each time
    /// the level moves, until it holds still; a scroll with or without a phase makes it the learner's, and nothing
    /// lands after that.
    public static func selfTest(_ check: (Bool, String) -> Void) {
        func at(_ s: TimeInterval) -> Date { Date(timeIntervalSinceReferenceDate: 1000 + s) }
        func list(_ h: CGFloat, _ y: CGFloat) -> Geometry { Geometry(height: h, offset: y, maxOffset: h - 600) }
        /// Opens Words at Lv 14: the jump there, back and there again (SwiftUI's, as it measures), and the level laid out.
        func opened() -> TomoLanding {
            var l = TomoLanding()
            l.start(14, at: at(0))
            _ = l.changed(from: list(20000, 0), to: list(20000, 7029), at: at(0.05))
            _ = l.changed(from: list(20000, 7029), to: list(20000, 0), at: at(0.06))
            _ = l.changed(from: list(20000, 0), to: list(19900, 6668), at: at(0.08))
            _ = l.laidOut(top: 6668, at: at(0.08))
            return l
        }

        var l = opened()
        let jumped = l.level == 14
        // A level above laid out shorter moves Lv 14 up: land again, and the list moves (ours). Twice.
        let first = l.laidOut(top: 6611, at: at(0.3))
        _ = l.changed(from: list(19900, 6668), to: list(19843, 6611), at: at(0.35))
        let second = l.laidOut(top: 6600, at: at(0.4))
        _ = l.changed(from: list(19843, 6611), to: list(19832, 6600), at: at(0.45))
        // Rows below laid out: the level doesn't move, nothing lands.
        let below = l.changed(from: list(19832, 6600), to: list(19700, 6600), at: at(0.5))
        l.tick(at: at(0.4 + still - 0.05))
        let held = l.level == 14
        l.tick(at: at(0.4 + still))
        check(jumped && first && second && !below && held && l.level == nil,
              "words landing: the jump's own moves are ours, the list lands again each time the level moves "
                + "(\(first), \(second)) and not for rows below it (\(below)), until it holds still for \(still) s")

        l = opened()
        _ = l.changed(from: list(19900, 6668), to: list(19900, 6968), at: at(0.6))   // VoiceOver, the keyboard
        let after = l.laidOut(top: 6600, at: at(0.7))
        check(l.level == nil && !after,
              "words landing: a scroll with no phase ends it, and the list doesn't land again when the level moves")

        l = opened()
        let into = l.changed(from: list(19900, 6668), to: list(19750, 6968), at: at(0.6))   // into rows not laid out
        check(l.level == nil && !into, "words landing: a scroll that lays out new rows as it goes ends it too")

        l = opened()
        l.scrolled()
        check(l.level == nil, "words landing: a scroll phase (a drag, a trackpad, a mouse wheel) ends it")

        l = opened()
        _ = l.laidOut(top: nil, at: at(0.3))   // moved out of the laid-out rows
        let gone = l.changed(from: list(19900, 6668), to: list(19000, 6668), at: at(0.35))
        check(l.level == 14 && gone, "words landing: while the level isn't laid out, a change in height lands again")

        l = TomoLanding()
        l.start(5, at: at(0))
        _ = l.changed(from: list(5000, 0), to: list(5000, 4400), at: at(0.05))   // the last level: as far as it goes
        _ = l.laidOut(top: 4500, at: at(0.05))
        _ = l.changed(from: list(5000, 4400), to: list(4900, 4300), at: at(0.5))   // a level above laid out shorter
        let pulled = l.laidOut(top: 4400, at: at(0.5))
        check(l.level == 5 && pulled,
              "words landing: at the list's end, a level laid out shorter pulls the list back with it, and it lands again")
    }
}
