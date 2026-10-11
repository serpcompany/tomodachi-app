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
                                    // The level it's landing on, where it's laid out in the list, told to each landing
                                    // (nil for every other level): when it moves, land again.
                                    .onGeometryChange(for: TomoLanding.Row?.self) {
                                        n == landing.level
                                            ? TomoLanding.Row(top: $0.frame(in: .named(Self.list)).minY, landing: landing.landings)
                                            : nil
                                    } action: { row in
                                        if n == landing.level, landing.laidOut(top: row?.top) { proxy.scrollTo(n, anchor: .top) }
                                    }
                                    .onDisappear { if n == landing.level { _ = landing.laidOut(top: nil) } }
                            }
                        }
                        .padding(.vertical, 10)
                        .coordinateSpace(.named(Self.list))   // the content's own: a level landed on is at the list's offset
                    }
                    .accessibilityIdentifier("words.list")
                    // The rows are lazy: the jump to a level estimates the heights above it, which move it as they're
                    // laid out, then and whenever the list is laid out again. The list lands on it again, with
                    // `scrollTo` alone, until the learner scrolls (TomoLanding). No `scrollPosition`: it puts the list
                    // back where its own estimates say the level is, which took the level away (#218). Once the list
                    // is the learner's, the rule isn't asked again, so scrolling never touches the screen's state.
                    .onScrollGeometryChange(for: TomoLanding.Geometry.self) { g in
                        TomoLanding.Geometry(height: g.contentSize.height, offset: g.contentOffset.y + g.contentInsets.top,
                                             maxOffset: g.contentSize.height + g.contentInsets.bottom + g.contentInsets.top
                                                 - g.containerSize.height)
                    } action: { old, new in
                        seen.list = new
                        if landing.level != nil, landing.changed(from: old, to: new), let level = landing.level {
                            proxy.scrollTo(level, anchor: .top)
                        }
                    }
                    .onScrollPhaseChange { _, phase in
                        if phase != .idle, landing.level != nil { landing.scrolled() }
                    }
                    // Each time Words shows (opened, or switched to from another screen or tab), it lands on Tomo's
                    // level, unless the learner has scrolled it since: then it stays where they left it. Back on the
                    // iPhone's tab with the list still at the level, it just rests there; while another tab shows,
                    // it hears nothing.
                    .onAppear {
                        landing.show()
                        if !opened || landing.level != nil { opened = true; land(game.level, proxy) }
                    }
                    .onDisappear { landing.hide() }
                    .onChange(of: game.level) { _, level in land(level, proxy) }
                }
            }
        }
    }

    /// Words has opened at Tomo's level; coming back to it after the learner scrolled keeps the list where it was.
    @State private var opened = false
    /// Landing on Tomo's level, until the learner scrolls.
    @State private var landing = TomoLanding()
    /// Where the list is, kept while it's the learner's too, without updating the screen as it scrolls.
    @State private var seen = TomoLanding.Seen()
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
        if landing.start(level, list: seen.list) { proxy.scrollTo(level, anchor: .top) }
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

/// A word's stage as a colored capsule: grey (not met, locked), then teal to green, and purple for forever. Dark mode
/// tints each capsule with its text's colour, brighter stage by stage; light mode fills it from a pale tone to a solid
/// one (#236). Every stage reads at 5:1 or more on its mode's card (#195 dark, #207 light) and stands apart from the
/// stage before it (#236), checked by `selfTest`.
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

    /// How a stage's capsule looks in one mode: its text's colour, and its fill (a colour at an opacity).
    struct Look { let text: String; let fill: String; let opacity: Double }

    /// A stage's look in light or dark mode; nil for one without (not met, locked), drawn in the secondary colour.
    static func look(_ group: String, dark: Bool) -> Look? {
        if dark {
            let hex: String? = switch group {
            case "heard":   "#87BDBA"
            case "knows":   "#28D79F"
            case "good":    "#47E5BE"
            case "loves":   "#7EEDD2"
            case "forever": "#B9ABEB"
            default:        nil
            }
            return hex.map { Look(text: $0, fill: $0, opacity: 0.15) }
        }
        // Light: opaque fills, so a pill looks the same on the page and on a word card. Pale sky, mint, green, then
        // solid green and solid purple with white text: each step darker than the last, so the order shows without
        // telling the hues apart (#236).
        return switch group {
        case "heard":   Look(text: "#036D87", fill: "#E0F6FF", opacity: 1)
        case "knows":   Look(text: "#036455", fill: "#AEEBDC", opacity: 1)
        case "good":    Look(text: "#005226", fill: "#87D49C", opacity: 1)
        case "loves":   Look(text: "#FFFFFF", fill: "#017C3E", opacity: 1)
        case "forever": Look(text: "#FFFFFF", fill: "#7850DA", opacity: 1)
        default:        nil
        }
    }

    public var body: some View {
        let look = Self.look(group, dark: scheme == .dark)
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(look.map { Color(hex: $0.text) } ?? .secondary)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(look.map { Color(hex: $0.fill).opacity($0.opacity) } ?? Color.secondary.opacity(0.15))
            .clipShape(Capsule())
            .fixedSize()
    }
}

extension TomoStagePill {
    /// The lightest dark card a pill sits on: the Mac's word card measures #282828 in dark mode; the Mac's page and the
    /// iPhone's cards are darker, where a stage reads better still.
    static let darkCard = "#2B2B2B"

    /// The darkest light card a pill sits on: the Mac's word card measures #F4F4F4 in light mode, and the Mac's page is
    /// white. Light fills are opaque, so a stage reads the same on either. The iPhone is always dark.
    static let lightCard = "#F2F2F2"

    /// How far apart two neighbouring stages must look, in OKLab: about 0.02 is just noticeable side by side. The light
    /// stages of #207 were 0.036 to 0.047 apart and read as one green (#236).
    static let minimumStep = 0.05

    /// The rule (TOMO_SELFTEST, swift test), in each mode on that mode's card: each stage's text reads at 5:1 or more
    /// (WCAG contrast) on its own fill, so a palette change can't bring back the 2.1:1 "Loves it" in dark mode (#195) or
    /// the 2.3:1 "Just heard" in light mode (#207); and each stage stands apart from the one before it, its text or its
    /// fill `minimumStep` or more away, so the stages can't fade back into one colour (#236).
    public static func selfTest(_ check: (Bool, String) -> Void) {
        for (dark, card) in [(true, darkCard), (false, lightCard)] {
            let mode = dark ? "dark" : "light"
            var before: (stage: String, look: Look)?
            for stage in stages {
                guard let look = look(stage, dark: dark) else { check(false, "stages: \(stage) has a \(mode) look"); continue }
                let ratio = contrast(look, over: card)
                check(ratio >= 5, "stages: \(stage) (\(look.text) on \(look.fill)) reads at \(String(format: "%.2f", ratio)):1 on a \(mode) card, 5:1 or more")
                if let before {
                    let apart = distance(before.look, look, over: card)
                    check(apart >= minimumStep, "stages: \(before.stage) and \(stage) are \(String(format: "%.3f", apart)) apart on a \(mode) card (OKLab), \(minimumStep) or more")
                }
                before = (stage, look)
            }
        }
    }

    /// WCAG contrast of a stage's text against its fill composited over `card`.
    static func contrast(_ look: Look, over card: String) -> Double {
        let a = luminance(rgb(look.text)), b = luminance(fill(look, over: card))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// How different two stages look on `card`: the larger of the OKLab distances between their texts and between their
    /// fills, so a step can show in either.
    static func distance(_ a: Look, _ b: Look, over card: String) -> Double {
        func apart(_ x: [Double], _ y: [Double]) -> Double {
            sqrt(zip(oklab(x), oklab(y)).map { ($0 - $1) * ($0 - $1) }.reduce(0, +))
        }
        return max(apart(rgb(a.text), rgb(b.text)), apart(fill(a, over: card), fill(b, over: card)))
    }

    private static func rgb(_ hex: String) -> [Double] {
        let v = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        return [Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255]
    }

    /// A stage's fill composited over the card, as the screen draws it.
    private static func fill(_ look: Look, over card: String) -> [Double] {
        zip(rgb(look.fill), rgb(card)).map { look.opacity * $0 + (1 - look.opacity) * $1 }
    }

    private static func linear(_ c: [Double]) -> [Double] {
        c.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
    }

    private static func luminance(_ c: [Double]) -> Double {
        let l = linear(c)
        return 0.2126 * l[0] + 0.7152 * l[1] + 0.0722 * l[2]
    }

    /// An sRGB colour in OKLab (Björn Ottosson's matrices), where distance follows how different colours look.
    private static func oklab(_ c: [Double]) -> [Double] {
        let r = linear(c)
        let l = cbrt(0.4122214708 * r[0] + 0.5363325363 * r[1] + 0.0514459929 * r[2])
        let m = cbrt(0.2119034982 * r[0] + 0.6806995451 * r[1] + 0.1073969566 * r[2])
        let s = cbrt(0.0883024619 * r[0] + 0.2817188376 * r[1] + 0.6299787005 * r[2])
        return [0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s]
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
/// it's laid out anew (VoiceOver or a UI test reading the screen, the text size, a word's stage). Until the learner
/// moves the list, it lands on the level again whenever:
/// - the level moves in the list (the rows above it were laid out);
/// - SwiftUI puts the list back where it was during the landing. It does after a jump, on the Mac and the iPhone, and
///   on a switch to Words it sometimes leaves the list there, at Lv 1;
/// - the list stops where the level isn't laid out, or reports a change before SwiftUI has started to land.
/// For SwiftUI's own moves (put back, stopped short), it lands again at most 3 times before the list rests at the
/// level. Past that, it stops: the list stays where SwiftUI left it, and is the learner's.
/// The list is the learner's, for good, at the first:
/// - scroll phase other than idle (a drag, a trackpad, a mouse wheel);
/// - move anywhere else, with or without a phase or new rows (the keyboard, VoiceOver), while no `scrollTo` is under
///   way. SwiftUI moves the list on its own only while it carries out a `scrollTo`, or back to where it was. When the
///   rows above are laid out anew, the level's new place is reported first, and lands.
/// Nothing ends it on a timer (#218), and it never waits on something that may not come:
/// - a landing that finds the list already at the level (the iPhone's Words tab, shown again before the learner
///   scrolled) rests there at once, with no `scrollTo`. While another tab shows, it hears nothing, so it doesn't ask
///   the hidden list to land (it did, 20 times a second, as the list's height kept changing);
/// - the level's row tells each new landing where it is, moved or not;
/// - each `scrollTo` is over at the list's first report that shows the level, or that it stopped.
/// What's left: a move with no phase while a `scrollTo` is under way (a fraction of a second as Words opens, or as the
/// level changes) counts as SwiftUI's, and one back to exactly where the list was during it, before the list rests,
/// lands once more. Plain values in, so `selfTest` checks it without a screen.
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

    /// What the level's row reports: its top in the list's content, and the landing it tells, so a new landing hears
    /// it even when the level hasn't moved.
    public struct Row: Equatable, Sendable {
        public var top: CGFloat, landing: Int
        public init(top: CGFloat, landing: Int) { self.top = top; self.landing = landing }
    }

    /// The list as last reported, kept while it's the learner's too, where writing it doesn't update the screen: a new
    /// landing starts from where the list is.
    @MainActor public final class Seen {
        public var list: Geometry?
        public init() {}
    }

    /// A `scrollTo` under way: asked (the list hasn't moved since), then moving, until the list shows the level or
    /// stops.
    enum Flight: Equatable, Sendable { case none, asked, moving }

    /// The level it's landing on; nil once the list is the learner's.
    public private(set) var level: Int?
    /// How many landings there have been: the level's row tells each one where it is.
    public private(set) var landings = 0
    /// The level's top in the list's content, while it's laid out.
    private var top: CGFloat?
    /// The list as last seen. SwiftUI skips some changes, so this, not its `old`, is what moved.
    private var list: Geometry?
    private var flight = Flight.none
    /// Where the list was when the landing asked, since it last rested at the level, and where SwiftUI moved it without
    /// reporting it: SwiftUI may put it back at one.
    private var trail: [CGFloat] = []
    /// How often it landed again for SwiftUI's own moves since then.
    private var again = 0
    /// Words is hidden: another tab shows.
    private var away = false

    public init() {}

    /// Lands on `level`, with the list at `list` (nil before its first report): Words shows, or Tomo's level changes.
    /// True: the caller scrolls there. False: the list already shows the level, and rests there, or Words is hidden,
    /// and it lands as Words shows again.
    public mutating func start(_ level: Int, list: Geometry?) -> Bool {
        if level != self.level { top = nil }   // its row tells this landing where it is
        self.level = level
        self.list = list
        landings += 1
        trail = []
        again = 0
        if away { flight = .none; return false }   // it lands as Words shows again
        if let list, let top, list.shows(top) { flight = .none; return false }   // already there
        return ask()
    }

    /// The level's top in the list's content, as it's laid out (nil: no longer laid out). True: land on it.
    public mutating func laidOut(top new: CGFloat?) -> Bool {
        guard level != nil, !away else { return false }
        let old = top
        top = new
        guard let new else { return false }   // the list's next report says whether it moved
        if list?.shows(new) == true { flight = .none; return false }   // the list is there
        guard old.map({ abs(new - $0) > 0.5 }) ?? true else { return false }
        return ask()   // laid out, or moved by the rows above
    }

    /// The list's geometry changed (`old` as SwiftUI last had it). True: land on the level again.
    public mutating func changed(from old: Geometry, to new: Geometry) -> Bool {
        guard level != nil, !away else { return false }
        let last = list ?? old
        // Where it was as the landing began, or a place SwiftUI moved it without reporting it.
        if list == nil || abs(old.offset - last.offset) > 0.5 { note(old.offset) }
        let moved = abs(new.offset - last.offset) > 0.5
        list = new
        if let top, new.shows(top) {   // at the level
            flight = .none
            if !moved { trail = []; again = 0 }   // rested there
            return false
        }
        if moved {
            if trail.contains(where: { abs($0 - new.offset) <= 0.5 }) {   // put back where it was
                flight = .moving
                return landAgain()
            }
            if flight != .none { flight = .moving; return false }   // on its way
            level = nil   // the learner moved it
            return false
        }
        if flight == .asked { return true }   // SwiftUI hasn't started: ask again
        flight = .none   // it stopped short of the level
        return top == nil ? landAgain() : false   // where the level isn't laid out; if it is, its next move lands
    }

    /// A scroll phase other than idle: the learner is scrolling.
    public mutating func scrolled() { level = nil }

    /// Words is hidden (the iPhone's tab, as another one shows). The level's row goes with it, and the list's height
    /// can keep changing; none of it lands, and nor does a new level. The `start` as Words shows again picks up from
    /// where the list is.
    public mutating func hide() { away = true }

    /// Words shows: what the list and the level's row report counts again.
    public mutating func show() { away = false }

    private mutating func ask() -> Bool {
        if let list { note(list.offset) }
        flight = .asked
        return true
    }

    /// For SwiftUI's own moves, at most 3 times before the list rests at the level; then the landing stops where the
    /// list is, and the list is the learner's.
    private mutating func landAgain() -> Bool {
        guard again < 3 else { level = nil; return false }
        again += 1
        return ask()
    }

    private mutating func note(_ offset: CGFloat) {
        if !trail.contains(where: { abs($0 - offset) <= 0.5 }) { trail.append(offset) }
    }
}

extension TomoLanding {
    /// The rule (TOMO_SELFTEST, swift test), on geometry of a list 600 pt tall, in the order SwiftUI reports it on the
    /// iPhone 17 Pro and the Mac (#218): one check for each way Words shows, each way the learner moves the list, and
    /// each way SwiftUI moves it on its own, including every case from #206's and #223's reviews.
    public static func selfTest(_ check: (Bool, String) -> Void) {
        func list(_ h: CGFloat, _ y: CGFloat) -> Geometry { Geometry(height: h, offset: y, maxOffset: h - 600) }
        /// A landing on `level` before the list's first report.
        func landing(_ level: Int) -> TomoLanding {
            var l = TomoLanding()
            _ = l.start(level, list: nil)
            return l
        }
        /// Feeds the list's reports in order, the first from `from`; returns which of them landed.
        func reports(_ l: inout TomoLanding, _ from: Geometry, _ to: [Geometry]) -> [Bool] {
            var last = from
            return to.map { g in defer { last = g }; return l.changed(from: last, to: g) }
        }
        /// Opens Words at Lv 14 (the iPhone 17 Pro): the first layout before SwiftUI starts, the jump there on
        /// estimated heights, the level laid out where the list is, and rows below laid out as it rests; then the rows
        /// above laid out shorter, so the level moves up and the list lands on it again. It ends resting at 6749.
        func opened() -> (TomoLanding, [Bool]) {
            var l = landing(14)
            var landed = reports(&l, list(20, 0), [list(156_371, 0), list(156_371, 7441)])
            landed.append(l.laidOut(top: 7441))
            landed += reports(&l, list(156_371, 7441), [list(151_248, 7441), list(147_594, 7441)])
            landed.append(l.laidOut(top: 6749))
            landed += reports(&l, list(147_594, 7441), [list(140_000, 6749), list(139_000, 6749)])
            return (l, landed)
        }

        // 1. Words lands on Tomo's level each time it shows.
        var (l, landed) = opened()
        check(l.level == 14 && landed == [true, false, false, false, false, true, false, false],
              "words landing: opened, it lands, and again when the level moves, not for rows below it, and holds it")

        // Switched to on the Mac (Lv 31): SwiftUI jumps there, puts the list back at Lv 1, and sometimes stops there.
        l = landing(31)
        landed = reports(&l, list(147_694, 0), [list(147_694, 16_192), list(147_694, 0)])
        landed += reports(&l, list(147_694, 0), [list(147_694, 16_192)])
        landed.append(l.laidOut(top: 16_192))
        landed += reports(&l, list(147_694, 16_192), [list(147_706, 16_192)])
        check(l.level == 31 && landed == [false, true, false, false, false],
              "words landing: switched to, it lands again when SwiftUI puts the list back at Lv 1, and holds the level")

        // Back on the iPhone's Words tab before the learner scrolled: the list is still at the level and doesn't move,
        // so nothing reports. It rests there at once, and the learner's first page with no phase (VoiceOver, the
        // keyboard) is theirs, rows laid out after it or not (#223's review, replayed as it was given).
        (l, _) = opened()
        var scrolls = l.start(14, list: list(139_000, 6749))
        landed = reports(&l, list(139_000, 6749), [list(139_000, 7349), list(139_400, 7349)])
        check(!scrolls && l.level == nil && !landed.contains(true),
              "words landing: back on Words with the list still at the level, it rests there without a scrollTo, and "
                + "a scroll with no phase then ends it")

        // The same, as the iPhone 17 Pro reports it: as another tab shows, Words hides, then the level's row goes, and
        // the list's height keeps changing for seconds. None of it lands. Back on Words, the row tells the new landing
        // it's there; then the learner pages until the level leaves, and rows are laid out.
        (l, _) = opened()
        l.hide()
        landed = [l.laidOut(top: nil)]
        landed += reports(&l, list(139_000, 6749), [list(139_500, 6749), list(141_000, 6749)])
        l.show()
        scrolls = l.start(14, list: list(141_000, 6749))
        landed.append(l.laidOut(top: 6749))
        landed += reports(&l, list(141_000, 6749), [list(141_000, 7349), list(141_000, 7949)])
        landed.append(l.laidOut(top: nil))
        landed += reports(&l, list(141_000, 7949), [list(141_400, 7949)])
        check(!scrolls && l.level == nil && !landed.contains(true),
              "words landing: while another tab shows, nothing lands; back on Words, it rests, and a scroll with no "
                + "phase then ends it, and never pulls back")

        // If the level's row goes before Words hides, the new landing asks, and the row tells it it's there.
        (l, _) = opened()
        landed = [l.laidOut(top: nil)]
        l.hide()
        l.show()
        scrolls = l.start(14, list: list(139_000, 6749))
        landed.append(l.laidOut(top: 6749))
        landed += reports(&l, list(139_000, 6749), [list(139_000, 7349)])
        check(scrolls && l.level == nil && !landed.contains(true),
              "words landing: back on Words where the level's row went first, the row tells it it's there, and a "
                + "scroll with no phase then ends it")

        // Rows above the level laid out anew while Words was hidden: back on Words, the row's new place lands.
        (l, _) = opened()
        l.hide()
        l.show()
        scrolls = l.start(14, list: list(139_000, 6749))
        landed = [l.laidOut(top: 6199)]
        landed += reports(&l, list(139_000, 6749), [list(139_000, 6199), list(139_100, 6199)])
        check(!scrolls && l.level == 14 && landed == [true, false, false],
              "words landing: back on Words where the level moved while it was hidden, it lands on its new place")

        // Tomo levels up on Play, with Words hidden: nothing lands until Words shows, then it lands on the new level.
        (l, _) = opened()
        l.hide()
        let hidden = l.start(15, list: list(139_000, 6749))
        landed = [l.laidOut(top: nil)]
        landed += reports(&l, list(139_000, 6749), [list(140_000, 6749), list(141_000, 6749)])
        l.show()
        scrolls = l.start(15, list: list(141_000, 6749))
        landed.append(l.laidOut(top: 7500))
        landed += reports(&l, list(141_000, 6749), [list(141_000, 7500), list(141_100, 7500)])
        check(!hidden && scrolls && l.level == 15 && landed == [false, false, false, true, false, false],
              "words landing: Tomo's level changes while another tab shows, and nothing lands until Words shows, then "
                + "it lands on the new level")

        // Shown again while SwiftUI was still landing: it lands from where the list is.
        l = landing(14)
        landed = reports(&l, list(20, 0), [list(156_371, 0), list(156_371, 7441)])
        landed.append(l.laidOut(top: 6749))
        scrolls = l.start(14, list: list(156_371, 7441))
        landed += reports(&l, list(156_371, 7441), [list(150_000, 6749), list(149_000, 6749)])
        landed += reports(&l, list(149_000, 6749), [list(149_000, 7349)])
        check(scrolls && l.level == nil && landed == [true, false, true, false, false, false],
              "words landing: shown again before it landed, it lands from where the list is, then rests, and a scroll "
                + "with no phase ends it")

        // Tomo's level changes as Words opens (a sync): the new landing takes over, on the new level (#206's review),
        // and SwiftUI gets there in steps.
        l = landing(14)
        landed = reports(&l, list(20, 0), [list(156_371, 0)])
        scrolls = l.start(15, list: list(156_371, 0))
        landed += reports(&l, list(156_371, 0), [list(156_371, 4000), list(156_371, 7980)])
        landed += [l.laidOut(top: 7980)]
        landed += reports(&l, list(156_371, 7980), [list(155_000, 7980)])
        check(scrolls && l.level == 15 && landed == [true, false, false, false, false],
              "words landing: Tomo's level changes as it lands, and it lands on the new level, in SwiftUI's steps")

        // Tomo's level changes after the learner scrolled: it lands on the new one, or rests if the list is there.
        (l, _) = opened()
        l.scrolled()
        scrolls = l.start(15, list: list(139_000, 9000))
        landed = [l.laidOut(top: 7500)]
        landed += reports(&l, list(139_000, 9000), [list(139_000, 7500), list(139_100, 7500)])
        let landedThere = scrolls && l.level == 15 && landed == [true, false, false]
        (l, _) = opened()
        l.scrolled()
        _ = l.start(15, list: list(139_000, 7500))
        landed = [l.laidOut(top: 7500)]
        landed += reports(&l, list(139_000, 7500), [list(139_000, 8100)])
        check(landedThere && l.level == nil && landed == [false, false],
              "words landing: Tomo's level changes after the learner scrolled, and it lands on the new one, or rests "
                + "where the list already shows it, and a scroll with no phase ends it")

        // 2. Any move by the learner ends it for good.
        (l, _) = opened()
        l.scrolled()
        check(l.level == nil, "words landing: a scroll phase (a drag, a trackpad, a mouse wheel) ends it")

        (l, _) = opened()
        landed = reports(&l, list(139_000, 6749), [list(139_000, 7049)])   // the keyboard, VoiceOver, a wheel
        landed += [l.laidOut(top: 6199), l.laidOut(top: nil)]
        landed += reports(&l, list(139_000, 7049), [list(138_000, 7049), list(140_000, 7049)])
        check(l.level == nil && !landed.contains(true),
              "words landing: a scroll with no phase ends it, and nothing lands after, when the level moves or leaves, "
                + "or the height changes")

        // Paging down with no phase (the keyboard, VoiceOver) lays out rows on each page, until the level leaves.
        (l, _) = opened()
        landed = reports(&l, list(139_000, 6749), [list(138_700, 7349)])
        let first = l.level == nil
        landed += reports(&l, list(138_700, 7349), [list(138_500, 7949)])
        landed.append(l.laidOut(top: nil))
        landed += reports(&l, list(138_500, 7949), [list(138_300, 8549)])
        check(first && l.level == nil && !landed.contains(true),
              "words landing: paging with no phase that lays out new rows ends it at the first page, and never pulls "
                + "the list back once the level leaves")

        // A landing whose last report both moves and lays out rows: no report shows it resting.
        l = landing(14)
        landed = reports(&l, list(20, 0), [list(20_000, 0)])
        landed.append(l.laidOut(top: 7029))
        landed += reports(&l, list(20_000, 0), [list(19_900, 7029), list(19_900, 7329)])
        check(l.level == nil && landed == [true, true, false, false],
              "words landing: a scroll with no phase ends it right after it lands, with no report of the list resting")

        // 3. It never waits on something that may not come.
        l = landing(14)
        landed = reports(&l, list(20, 0), [list(156_371, 0), list(140_000, 0)])
        landed += reports(&l, list(140_000, 0), [list(140_000, 7441), list(139_000, 7441)])   // stopped, not laid out
        check(l.level == 14 && landed == [true, true, false, true],
              "words landing: until SwiftUI starts to land, each report asks again, and it asks again if the list "
                + "stops where the level isn't laid out")

        // SwiftUI keeps putting the list back, or stopping short: past 3 times, it stops where the list is, and the
        // list is the learner's (#223's review).
        l = landing(14)
        landed = []
        for _ in 1...2 { landed += reports(&l, list(140_000, 0), [list(140_000, 7441), list(140_000, 0)]) }
        landed += reports(&l, list(140_000, 0), [list(140_000, 7441), list(139_000, 7441)])   // stopped short
        let thrice = l.level == 14 && landed.filter { $0 }.count == 3
        landed += reports(&l, list(139_000, 7441), [list(139_000, 0)])   // put back once more
        let stopped = l.level == nil
        landed += reports(&l, list(139_000, 0), [list(139_000, 300), list(139_400, 300)])
        check(thrice && stopped && landed.filter { $0 }.count == 3,
              "words landing: when SwiftUI keeps putting the list back or stopping short, it lands again 3 times, "
                + "then stops where the list is, which is the learner's")

        // 4. Rows laid out above the level while it lands never leave it off screen.
        // Seconds later, the list laid out anew (VoiceOver, a UI test reading the screen): the level moves up 550 pt,
        // and SwiftUI moves the list down 288 pt, to Lv 16 (#218).
        (l, _) = opened()
        landed = reports(&l, list(139_000, 6749), [list(140_000, 6749)])
        landed.append(l.laidOut(top: 6199))
        landed += reports(&l, list(140_000, 6749), [list(140_000, 7037), list(140_000, 6199), list(140_100, 6199)])
        check(l.level == 14 && landed == [false, true, false, false, false],
              "words landing: seconds later, the list laid out anew moves the level, and it lands on it again")

        // A screen reader lays the list out anew (the iPhone 17 Pro): the level is reported at places it isn't, it
        // leaves and comes back, SwiftUI moves the list without reporting it, lands, puts it back there, and lands.
        (l, _) = opened()
        landed = [6749, 11_650, 10_509, 6336, 6438, 6573].map { l.laidOut(top: $0) }
        landed.append(l.laidOut(top: nil))
        landed += [10_644, 6572].map { l.laidOut(top: $0) }
        landed += [l.changed(from: list(139_740, 7575), to: list(141_940, 6572)),   // from where it wasn't reported
                   l.changed(from: list(141_940, 6572), to: list(141_940, 7575))]   // put back there
        landed += reports(&l, list(141_940, 7575), [list(139_978, 7575), list(140_045, 6572), list(140_048, 6572)])
        let held = l.level == 14
        landed += reports(&l, list(140_048, 6572), [list(140_048, 6872)])   // then the keyboard
        check(held && l.level == nil
                && landed == [false, true, true, true, true, true, false, true, true, false, true, true, false, false,
                              false],
              "words landing: a screen reader's layout lands each time the level moves, and when SwiftUI puts the list "
                + "back; a scroll with no phase after it ends it")

        // At the list's end: the level can't reach the top, and a level above laid out shorter pulls the list with it.
        l = landing(5)
        landed = reports(&l, list(20, 0), [list(5000, 0)])
        landed.append(l.laidOut(top: 4500))
        landed += reports(&l, list(5000, 0), [list(5000, 4400), list(4900, 4300)])
        landed.append(l.laidOut(top: 4400))
        check(l.level == 5 && landed == [true, true, false, false, false],
              "words landing: at the list's end, a level laid out shorter pulls the list back with it, and it's still "
                + "landing")
    }
}
