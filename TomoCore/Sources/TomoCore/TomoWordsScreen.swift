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
                                    // The level it's landing on, where it's laid out in the list (nil for every other
                                    // level, so a new landing hears where its level already is): when it moves, land again.
                                    .onGeometryChange(for: CGFloat?.self) {
                                        n == landing.level ? $0.frame(in: .named(Self.list)).minY : nil
                                    } action: { top in
                                        if n == landing.level, landing.laidOut(top: top) { proxy.scrollTo(n, anchor: .top) }
                                    }
                                    .onDisappear { if n == landing.level { _ = landing.laidOut(top: nil) } }
                            }
                        }
                        .padding(.vertical, 10)
                        .coordinateSpace(.named(Self.list))   // the content's own: a level landed on is at the list's offset
                    }
                    // The rows are lazy: the jump to a level estimates the heights above it, which move it as they're
                    // laid out, then and whenever the list is laid out again. The list lands on it again, with
                    // `scrollTo` alone, until the learner scrolls (TomoLanding). No `scrollPosition`: it puts the list
                    // back where its own estimates say the level is, which took the level away (#218).
                    .onScrollGeometryChange(for: TomoLanding.Geometry.self) { g in
                        TomoLanding.Geometry(height: g.contentSize.height, offset: g.contentOffset.y + g.contentInsets.top,
                                             maxOffset: g.contentSize.height + g.contentInsets.bottom + g.contentInsets.top
                                                 - g.containerSize.height)
                    } action: { old, new in
                        if landing.changed(from: old, to: new), let level = landing.level {
                            proxy.scrollTo(level, anchor: .top)
                        }
                    }
                    .onScrollPhaseChange { _, phase in
                        if phase != .idle { landing.scrolled() }
                    }
                    .onAppear { if !opened { opened = true; land(game.level, proxy) } }
                    .onChange(of: game.level) { _, level in land(level, proxy) }
                }
            }
        }
    }

    /// Words has opened at Tomo's level; coming back to it keeps the list where it was.
    @State private var opened = false
    /// Landing on Tomo's level, until the learner scrolls.
    @State private var landing = TomoLanding()
    /// The list's content, where a level's place doesn't change as it scrolls.
    private static let list = "words.list"
    /// More stage chips past the row's trailing edge.
    @State private var chipsMore = false
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The space between a reading's words, which grows with its text.
    @ScaledMetric(relativeTo: .caption) private var readingSpace: CGFloat = 3
    @ScaledMetric(relativeTo: .callout) private var meaningSpace: CGFloat = 4

    /// Opens the list at `level`: Words opens, or Tomo's level changes.
    private func land(_ level: Int, _ proxy: ScrollViewProxy) {
        landing.start(level)
        proxy.scrollTo(level, anchor: .top)
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
/// the teal stage by stage; dark mode brightens it. Every stage reads at 5:1 or more on its mode's card (#195 dark,
/// #207 light; checked by `selfTest`), and a light colour keeps its hue as it darkens (OKLCH).
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
        case "heard":   dark ? "#87BDBA" : "#0E625F"
        case "knows":   dark ? "#28D79F" : "#035C42"
        case "good":    dark ? "#47E5BE" : "#02513E"
        case "loves":   dark ? "#7EEDD2" : "#024635"
        case "forever": dark ? "#B9ABEB" : "#6042B8"
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

// MARK: - Landing on Tomo's level (#193, #218)

/// When Words lands on Tomo's level, and when the list becomes the learner's. The rows are lazy, so the jump to the
/// level estimates the heights above it, and the level moves as they're laid out: as the list opens, and again whenever
/// it's laid out anew (VoiceOver or a UI test reading the screen, the text size, a word's stage). Each time the level
/// moves, the list lands on it again, so its header and first word show under the chips. Rows laid out below it don't
/// move it, so they don't land. Nothing ends it on a timer: a landing that ended while the rows above were still
/// estimates left the list on Lv 16 when they were laid out again (#218). The list is the learner's from whichever
/// comes first:
/// - a scroll phase other than idle (a drag, a trackpad, a mouse wheel);
/// - the list moving away from the level after it rested there, with no change in the content's height: the keyboard
///   or VoiceOver may scroll with no phase. SwiftUI's own moves come before the list rests at the level after a
///   landing (it moves it there, away and back while it lays the rows out), or with the heights estimated again.
/// Plain values in, so `selfTest` checks it without a screen.
public struct TomoLanding: Equatable, Sendable {
    /// What the rule reads of the list: its content's height, how far it's scrolled (the content's y at the list's top),
    /// and how far it can be.
    public struct Geometry: Equatable, Sendable {
        public var height: CGFloat, offset: CGFloat, maxOffset: CGFloat
        public init(height: CGFloat, offset: CGFloat, maxOffset: CGFloat) {
            self.height = height; self.offset = offset; self.maxOffset = maxOffset
        }

        /// The level whose top is at `top` in the content is at the list's top, or the list is as far as it goes.
        func shows(_ top: CGFloat) -> Bool {
            abs(offset - min(max(top, 0), max(maxOffset, 0))) <= 1
        }
    }

    /// The level it's landing on; nil once the list is the learner's.
    public private(set) var level: Int?
    /// The level's top in the list's content, as last laid out; nil until it is.
    private var top: CGFloat?
    /// The level is laid out now.
    private var laid = false
    /// Since the last landing, the list has held still at the level while rows were laid out: a move now is no
    /// landing's.
    private var rested = false
    /// The list as last seen, so a level laid out where the list already is doesn't land again.
    private var seen: Geometry?

    public init() {}

    /// Lands on `level` (Words opens, or Tomo's level changes).
    public mutating func start(_ level: Int) {
        self.level = level
        top = nil
        laid = false
        rested = false
    }

    /// The level's top in the list's content, as it's laid out (nil: no longer laid out). True: land on it.
    public mutating func laidOut(top new: CGFloat?) -> Bool {
        guard level != nil else { return false }
        guard let new else { laid = false; return false }
        let moved = top.map { abs(new - $0) > 0.5 } ?? true   // first laid out, or moved by the rows above
        laid = true
        top = new
        guard moved, seen?.shows(new) != true else { return false }   // the list is already there
        rested = false
        return true
    }

    /// The list's geometry changed. True: land again, when the level isn't laid out and the content's height changed.
    public mutating func changed(from old: Geometry, to new: Geometry) -> Bool {
        seen = new
        guard level != nil else { return false }
        let moved = abs(new.offset - old.offset) > 0.5, grew = abs(new.height - old.height) > 0.5
        if laid, let top, new.shows(top) {   // at the level
            if !moved { rested = true }
            return false
        }
        if moved && !grew && rested { level = nil; return false }   // the learner scrolled, with no phase
        guard grew, !laid else { return false }
        rested = false
        return true
    }

    /// A scroll phase other than idle: the learner is scrolling.
    public mutating func scrolled() { level = nil }
}

extension TomoLanding {
    /// The rule (TOMO_SELFTEST, swift test), on made-up geometry of a list 600 pt tall, in the order the iPhone 17 Pro
    /// reports it (#218): the list lands again each time the level moves, as it opens and seconds later, until the
    /// learner scrolls; a scroll with or without a phase makes it the learner's, and nothing lands after that.
    public static func selfTest(_ check: (Bool, String) -> Void) {
        func list(_ h: CGFloat, _ y: CGFloat) -> Geometry { Geometry(height: h, offset: y, maxOffset: h - 600) }
        /// Opens Words at Lv 14: the first layout, the jump there on estimated heights, the levels above laid out
        /// shorter (the level moves up, and the list lands on it again), and SwiftUI's own moves as it estimates.
        func opened() -> (TomoLanding, [Bool]) {
            var l = TomoLanding(), landed: [Bool] = []
            l.start(14)
            landed.append(l.changed(from: list(20, 0), to: list(156_000, 0)))   // laid out, the level not yet: land
            landed.append(l.laidOut(top: 7428))                                 // the level, before the list moved
            landed.append(l.changed(from: list(156_000, 0), to: list(120_000, 7428)))   // the jump: there
            landed.append(l.changed(from: list(120_000, 7428), to: list(137_000, 7428)))
            landed.append(l.changed(from: list(137_000, 7428), to: list(120_000, 6826)))   // SwiftUI's own move
            landed.append(l.laidOut(top: 6749))                                 // the levels above, laid out shorter
            landed.append(l.changed(from: list(120_000, 6826), to: list(120_000, 6749)))   // landed
            landed.append(l.changed(from: list(120_000, 6749), to: list(136_000, 5717)))   // SwiftUI's own bounce
            landed.append(l.changed(from: list(136_000, 5717), to: list(134_000, 6749)))   // and back
            landed.append(l.changed(from: list(134_000, 6749), to: list(132_000, 6749)))   // rows below laid out
            return (l, landed)
        }

        var (l, landed) = opened()
        check(l.level == 14 && landed == [true, true, false, false, false, true, false, false, false, false],
              "words landing: as the list opens, it lands each time the level moves (\(landed.filter { $0 }.count) "
                + "times), not for rows below it or SwiftUI's own moves, and it's still landing after")

        // Seconds later the list is laid out anew (VoiceOver or a UI test reading the screen): the rows above are
        // estimated again, the level moves up 550 pt and SwiftUI moves the list down 288 pt, to Lv 16 (#218).
        _ = l.changed(from: list(132_000, 6749), to: list(133_000, 6749))
        let again = l.laidOut(top: 6199)
        _ = l.changed(from: list(133_000, 6749), to: list(133_000, 7037))
        let held = l.level == 14
        _ = l.changed(from: list(133_000, 7037), to: list(133_000, 6199))
        check(again && held && l.level == 14,
              "words landing: seconds later, the list laid out anew moves the level, and it lands on it again")

        (l, _) = opened()
        _ = l.changed(from: list(132_000, 6749), to: list(132_000, 7049))   // VoiceOver, the keyboard
        let after = l.laidOut(top: 6199)
        let gone = l.laidOut(top: nil)
        let rows = l.changed(from: list(132_000, 7049), to: list(131_000, 7049))
        check(l.level == nil && !after && !gone && !rows,
              "words landing: a scroll with no phase ends it, and nothing lands after, when the level moves or rows "
                + "are laid out")

        (l, _) = opened()
        _ = l.changed(from: list(132_000, 6749), to: list(131_800, 6800))   // into rows not laid out yet
        let into = l.changed(from: list(131_800, 6800), to: list(131_800, 6900))
        check(l.level == nil && !into,
              "words landing: a scroll with no phase that lays out new rows ends it at its first move that lays out none")

        (l, _) = opened()
        l.scrolled()
        check(l.level == nil, "words landing: a scroll phase (a drag, a trackpad, a mouse wheel) ends it")

        l = TomoLanding()
        l.start(14)
        _ = l.changed(from: list(20, 0), to: list(20_000, 0))
        let bounced = [l.changed(from: list(20_000, 0), to: list(20_000, 7029)),   // the jump there, back and there
                       l.changed(from: list(20_000, 7029), to: list(20_000, 0)),   // again, before the level is
                       l.changed(from: list(20_000, 0), to: list(20_000, 7029))]   // laid out (the Mac)
        let first = l.laidOut(top: 7029)
        check(l.level == 14 && bounced == [false, false, false] && !first,
              "words landing: the jump's own moves are the landing's, and a level first laid out where the list is "
                + "doesn't land again")

        // A screen reader lays the list out anew: the level is reported at places it isn't, the list lands, and SwiftUI
        // moves it away from the level and back with no change in height (the iPhone 17 Pro, #218).
        (l, _) = opened()
        let burst = [l.laidOut(top: 11_650), l.laidOut(top: 6336), l.laidOut(top: 6572)]
        _ = l.changed(from: list(139_700, 7575), to: list(141_900, 6572))   // landed
        let away = l.changed(from: list(141_900, 6572), to: list(141_900, 7575))
        let stayed = l.level == 14
        _ = l.changed(from: list(141_900, 7575), to: list(140_000, 6572))   // and back
        _ = l.changed(from: list(140_000, 6572), to: list(140_050, 6572))   // rows laid out, the list still: it rests
        let rested = l.level == 14
        _ = l.changed(from: list(140_050, 6572), to: list(140_050, 6872))   // the keyboard
        check(burst == [true, true, true] && !away && stayed && rested && l.level == nil,
              "words landing: SwiftUI's own moves away from the level are the landing's until the list rests there; "
                + "a scroll with no phase after that ends it")

        (l, _) = opened()
        _ = l.laidOut(top: nil)   // moved out of the laid-out rows
        let out = l.changed(from: list(132_000, 6749), to: list(131_000, 6749))
        check(l.level == 14 && out, "words landing: while the level isn't laid out, a change in height lands again")

        l = TomoLanding()
        l.start(5)
        _ = l.changed(from: list(20, 0), to: list(5000, 0))
        _ = l.laidOut(top: 4500)                                      // the last level: the list goes only to 4400
        _ = l.changed(from: list(5000, 0), to: list(5000, 4400))
        let end = l.changed(from: list(5000, 4400), to: list(4900, 4300))   // a level above laid out shorter
        let pulled = l.laidOut(top: 4400)
        check(l.level == 5 && !end && !pulled,
              "words landing: at the list's end, a level laid out shorter pulls the list back with it, and it's still "
                + "landing")
    }
}
