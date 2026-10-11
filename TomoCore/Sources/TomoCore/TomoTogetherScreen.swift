import SwiftUI
import UniformTypeIdentifiers

// MARK: - Together: what you and Tomo did (#137 item 2), the Mac window's page and the iPhone's tab
//
// Today ("12 answers · 3 new words · 5 days in a row"), the word garden (TomoGarden.swift: every word met, growing, for
// today, this week or since you met, with a replay, Copy recap, and the learner's own log to export as Markdown or
// JSON), and Tomo's week, as a postcard that comes every Monday morning: the newest one, turned over with a tap, shared
// as a picture (#29), and every earlier one in a row underneath; then Tomo's diary, a page for each day you played,
// in its own words (TomoDiaryView.swift). On the Monday a postcard comes, it's at the top. A
// brand-new Tomo gets an empty bed and its first postcard instead of a row of zeros. Everything shown comes from
// TomoStats, for the Tomo passed in (its progress, look and material), so a friend could have its own; the screen
// decides nothing. Test runs: TOMO_GARDEN=today|week|all picks the range, TOMO_GARDEN_REPLAY=<seconds> starts the
// replay that long after it shows, TOMO_GARDEN_WORD=newest shows the newest word's card; TOMO_POSTCARD=<n> shows the
// postcard n weeks before the newest, TOMO_POSTCARD_TURN=<seconds> turns it over; TOMO_SNAPSHOT_DIR keeps the exports.

public struct TomoTogetherScreen: View {
    private let progress: TomoProgress
    private let look: TomoLook
    private let material: TomoMaterial
    private let version: Int
    private let copy: ((String) -> Void)?
    @ObservedObject private var lang = TomoLanguages.shared
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    /// `progress`, `look` and `material`: the Tomo these are about (the learner's own: its progress, its look and
    /// `.own`). `version`: bump it when its progress changes (TomoGame's `progressVersion`), so the numbers are read again.
    /// `copy`: puts text on the clipboard (the shell's; TomoCore has no pasteboard). Nil hides Copy recap.
    public init(progress: TomoProgress, look: TomoLook, material: TomoMaterial, version: Int,
                copy: ((String) -> Void)? = nil) {
        self.progress = progress
        self.look = look
        self.material = material
        self.version = version
        self.copy = copy
    }

    private struct Loaded {
        var key = ""
        var today: [String] = []
        var cards: [TomoPostcard] = []
        var first: TomoPostcard?
        var postcardToday = false
        var plants: [TomoStats.Plant] = []
        var summaries: [TomoStats.Range: TomoStats.Summary] = [:]
        var lines: [TomoStats.Range: ([String], [String])] = [:]
        var recaps: [TomoStats.Range: String] = [:]
        var since = Date()
        var diary: [TomoDiaryPage] = []
    }

    @State private var range: TomoStats.Range =
        ProcessInfo.processInfo.environment["TOMO_GARDEN"].flatMap(TomoStats.Range.init(rawValue:)) ?? .week
    @State private var plantShown: String?
    @State private var replayStart: Date?
    @State private var scrub: Double?
    @State private var copied = false
    @State private var exportFile: TomoLogFile?
    @State private var exporting = false
    private static let replayLength = 6.0

    @State private var loaded = Loaded()
    @State private var selected: Date?
    @State private var flipped = false
    @State private var shared: (file: TomoPostcardFile, preview: Image)?

    private var shown: TomoPostcard? {
        loaded.cards.first { $0.id == selected } ?? loaded.cards.last ?? loaded.first
    }

    private var phone: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    /// The accessibility text sizes (the iPhone's AX1 to AX5; the Mac never has them). There, what sits side by side
    /// goes one under another and the range picker is a menu, so nothing on the screen is wider than the phone (#216).
    private var largeText: Bool { typeSize.isAccessibilitySize }

    public var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if progress.isScratch {
                    Label(lang.learner("words.testing"), systemImage: "flask").foregroundStyle(.orange)
                }
                today
                if loaded.postcardToday { week; garden } else { garden; week }
                TomoDiarySection(progress: progress, look: look, material: material, pages: loaded.diary, copy: copy)
                    .id("diary")
            }
            .padding(.horizontal, phone ? 16 : 24)
            .padding(.vertical, phone ? 12 : 16)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task {
            // Test runs that look at the diary (TOMO_DIARY) scroll to it.
            guard ProcessInfo.processInfo.environment["TOMO_DIARY"] != nil else { return }
            try? await Task.sleep(for: .seconds(1.2))
            proxy.scrollTo("diary", anchor: .top)
        }
        }
        .onAppear {
            load()
            let env = ProcessInfo.processInfo.environment
            if let back = env["TOMO_POSTCARD"].flatMap(Int.init), loaded.cards.count > back {
                selected = loaded.cards[loaded.cards.count - 1 - back].id
            }
            if let s = env["TOMO_POSTCARD_TURN"].flatMap(Double.init) {
                DispatchQueue.main.asyncAfter(deadline: .now() + s) { flipped = true }
            }
            if let s = env["TOMO_GARDEN_REPLAY"].flatMap(Double.init) {
                DispatchQueue.main.asyncAfter(deadline: .now() + s) { replay() }
            }
            if env["TOMO_GARDEN_WORD"] == "newest" { plantShown = loaded.plants.last?.id }
            if let dir = env["TOMO_SNAPSHOT_DIR"] { writeExports(to: URL(fileURLWithPath: dir)) }
        }
        .fileExporter(isPresented: $exporting, document: exportFile, contentType: exportFile?.type ?? .json,
                      defaultFilename: exportFile?.name) { _ in exportFile = nil }
        .onChange(of: version) { _, _ in load() }
        .onChange(of: lang.learner.id) { _, _ in load() }
        .task {                                     // a new day, a new Monday: read again (only when the key changes)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                load()
            }
        }
        .task(id: shown.map { "\($0.id.timeIntervalSince1970) \($0.recap) \(lang.learner.id)" }) {
            shared = shown.flatMap { $0.isFirst ? nil : TomoPostcardImage.render($0, look: look, material: material) }
        }
    }

    /// Reads the numbers again when the progress, the day or the interface language changed.
    private func load() {
        let key = "\(version) \(TomoStats.dayStart(of: TomoClock.now).timeIntervalSince1970) \(lang.learner.id)"
        guard key != loaded.key else { return }
        let stats = TomoStats(progress), ui = lang.learner
        let cards = stats.postcards(ui), plants = stats.garden()
        var l = Loaded(key: key, today: stats.todayParts(ui), cards: cards, first: cards.isEmpty ? stats.firstPostcard(ui) : nil,
                       postcardToday: stats.postcardCameToday(ui) != nil, plants: plants)
        l.since = plants.first?.met ?? progress.metAt
        for r in TomoStats.Range.allCases {
            let s = stats.summary(r)
            l.summaries[r] = s
            l.lines[r] = Self.lines(r, s, plants: plants.count, stats: stats, ui)
            l.recaps[r] = stats.recap(s, range: stats.rangeText(r, ui), ui)
        }
        l.diary = stats.diary(ui)
        loaded = l
    }

    /// The garden's two lines for a range: what grew ("3 new sprouts", "5 grew"), then the watering, misses and when,
    /// as phrases (`TomoPhrases`); or a title and a sentence.
    private static func lines(_ r: TomoStats.Range, _ s: TomoStats.Summary, plants: Int, stats: TomoStats,
                              _ ui: LearnerPack) -> ([String], [String]) {
        guard plants > 0 else { return ([ui("garden.empty.title")], [ui("garden.empty.note")]) }
        if r == .all { return ([ui.counted("garden.planted", plants)], [ui("garden.order")]) }
        guard s.played else { return ([ui("garden.quiet.\(r.rawValue)")], [ui("garden.quiet.note")]) }
        var top: [String] = [], bottom: [String] = []
        if !s.newWords.isEmpty { top.append(ui.counted("garden.sprouts", s.newWords.count)) }
        if !s.stronger.isEmpty { top.append(ui.counted("garden.grew", s.stronger.count)) }
        var rest: [String] = []
        if s.practice > 0 { rest.append(ui.counted("garden.watered", s.practice)) }
        if s.misses > 0 { rest.append(ui.counted("postcard.misses", s.misses)) }
        if top.isEmpty, let first = rest.first { top.append(first); rest.removeFirst() }
        bottom += rest
        bottom.append(stats.rangeText(r, ui))
        return (top, bottom)
    }

    // MARK: The word garden

    private var garden: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(lang.learner("garden.title")).font(.title3.weight(.bold))
                    Text(lang.learner("garden.note")).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !phone, !largeText, !loaded.plants.isEmpty {
                    Spacer(minLength: 0)
                    rangePicker
                }
            }
            if phone || largeText, !loaded.plants.isEmpty { rangePicker }
            TimelineView(.animation(minimumInterval: 1 / 20, paused: replayStart == nil)) { tl in
                let at = gardenTime(tl.date)
                VStack(alignment: .leading, spacing: 10) {
                    if phone {
                        // Square on the iPhone, so the summary shows above the tabs; a tapped word shows over the
                        // garden's front, where the thumb is.
                        field(at: at).aspectRatio(1, contentMode: .fit)
                            .overlay(alignment: .bottom) { if let card = plantCard { card.padding(8) } }
                        summary
                        TomoGardenLegend(horizontal: !largeText)
                    } else {
                        HStack(alignment: .top, spacing: 14) {
                            VStack(alignment: .leading, spacing: 10) {
                                field(at: at).aspectRatio(16 / 10, contentMode: .fit)
                                if let card = plantCard { card }
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                summary
                                Text(lang.learner("garden.howItGrows").uppercased())
                                    .font(.system(size: 10.5, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                                TomoGardenLegend(horizontal: false)
                            }
                            .frame(width: 180, alignment: .leading)
                        }
                    }
                    if !loaded.plants.isEmpty { replayRow(at: tl.date) }
                }
            }
            if !loaded.plants.isEmpty { gardenActions }
        }
    }

    /// Today, this week or since we met: a segmented control, or at the accessibility sizes a menu showing the range
    /// chosen, since a segmented control can't wrap (#216). The menu's label is a `TomoPhrase` (one line, a little
    /// smaller if it must be): the stock menu picker wrapped "出会っ / てから" and cut both lines at its edges.
    private var rangePicker: some View {
        let picker = Picker(lang.learner("garden.title"), selection: $range) {
            ForEach(TomoStats.Range.allCases, id: \.self) { r in Text(lang.learner("garden.range.\(r.rawValue)")).tag(r) }
        }
        .labelsHidden()
        let chosen = lang.learner("garden.range.\(range.rawValue)")
        return Group {
            if largeText {
                Menu {
                    picker.pickerStyle(.inline)
                } label: {
                    HStack(spacing: 6) {
                        TomoPhrase(text: chosen)
                        Image(systemName: "chevron.up.chevron.down").imageScale(.small)
                    }
                }
                .accessibilityLabel(lang.learner("garden.title"))
                .accessibilityValue(chosen)
            } else {
                picker.pickerStyle(.segmented).fixedSize()
            }
        }
        .onChange(of: range) { _, _ in plantShown = nil }
    }

    private func field(at: Date?) -> some View {
        let s = loaded.summaries[range]
        let glowing = range == .all ? [] : Set((s?.newWords ?? []) + (s?.stronger ?? []))
        let watered = range == .all ? [] : Set(s?.practiced ?? [])
        return TomoGardenField(plants: loaded.plants, glowing: glowing, watered: watered, at: at, look: look,
                               material: material, growth: CGFloat(min(max(progress.age - 1, 0), TomoLook.ages - 1)),
                               tall: phone, emptyNote: lang.learner("garden.empty.field"), selected: $plantShown)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(lang.learner("garden.a11y", ["n": "\(loaded.plants.count)"]))
    }

    private var plantCard: TomoPlantCard? {
        guard let id = plantShown, let plant = loaded.plants.first(where: { $0.id == id }) else { return nil }
        return TomoPlantCard(plant: plant, progress: progress) { plantShown = nil }
    }

    private var summary: some View {
        let lines = loaded.lines[range] ?? ([], [])
        let sep = lang.learner("list.separator")
        return VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                TomoPhrases(parts: lines.0, separator: sep).font(.headline)
                if !lines.1.isEmpty {
                    TomoPhrases(parts: lines.1, separator: sep).font(.callout).foregroundStyle(.secondary)
                }
            }
            if !loaded.plants.isEmpty {
                let c = TomoGardenColors(dark: scheme == .dark)   // as the garden draws them in this mode
                let key = [(c.win, "garden.key.win"), (c.practice, "garden.key.practice")]
                ViewThatFits {
                    HStack(spacing: 12) { ForEach(key, id: \.1) { dotLabel($0.0, $0.1) } }
                    VStack(alignment: .leading, spacing: 4) { ForEach(key, id: \.1) { dotLabel($0.0, $0.1) } }
                }
            }
        }
    }

    private func dotLabel(_ color: Color, _ key: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(lang.learner(key)).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: The replay: the garden grows again from the first day

    /// Where the garden is in time: nil is now; during the replay or with the slider moved, a day since the first word.
    private func gardenTime(_ now: Date) -> Date? {
        guard let k = replayPosition(now), k < 0.999 else { return nil }
        let end = TomoClock.now
        return loaded.since.addingTimeInterval(k * end.timeIntervalSince(loaded.since))
    }

    private func replayPosition(_ now: Date) -> Double? {
        if let start = replayStart { return min(1, now.timeIntervalSince(start) / Self.replayLength) }
        return scrub
    }

    private func replay() {
        scrub = nil
        plantShown = nil
        let start = Date()
        replayStart = start
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.replayLength) {
            if replayStart == start { replayStart = nil }
        }
    }

    /// Replay, the slider and the day in one row; at the accessibility sizes, one under another, so the slider keeps
    /// the screen's width.
    @ViewBuilder private func replayRow(at now: Date) -> some View {
        let k = replayPosition(now) ?? 1
        let day = gardenTime(now) ?? TomoClock.now
        let button = Button(action: replay) {
            Label(lang.learner(replayStart == nil ? "garden.replay" : "garden.replaying"), systemImage: "play.fill")
        }
        .buttonStyle(.bordered)
        .disabled(replayStart != nil)
        // Its knob shows at the track's end in light mode too (TomoSlider, #195).
        let slider = TomoSlider(value: Binding(get: { k }, set: { scrub = $0 >= 0.999 ? nil : $0; replayStart = nil; plantShown = nil }),
                                tint: TomoGardenColors(dark: scheme == .dark).win)
            .accessibilityLabel(lang.learner("garden.day"))
            .accessibilityValue(TomoStats.shortDay(day, lang.learner))
        let date = Text(TomoStats.shortDay(day, lang.learner)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            .frame(minWidth: 52, alignment: .trailing)
        if largeText {
            VStack(alignment: .leading, spacing: 8) {
                button
                date.fixedSize(horizontal: false, vertical: true)
                slider
            }
        } else {
            HStack(spacing: 10) { button; slider; date }
        }
    }

    // MARK: Copy recap, and the learner's own log

    /// Copy recap and Export side by side; at the accessibility sizes, Export below, and both wrap their words.
    private var gardenActions: some View {
        let layout = largeText ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            if let copy {
                Button {
                    copy(loaded.recaps[range] ?? "")
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                } label: {
                    Label(lang.learner(copied ? "garden.copied" : "garden.copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }
            Menu {
                Button(lang.learner("export.markdown")) { export(markdown: true) }
                Button(lang.learner("export.json")) { export(markdown: false) }
            } label: {
                Label(lang.learner("export.button"), systemImage: "square.and.arrow.down")
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .fixedSize(horizontal: !largeText, vertical: true)
            if !largeText { Spacer(minLength: 0) }
        }
    }

    private func export(markdown: Bool) {
        let stats = TomoStats(progress), ui = lang.learner
        exportFile = markdown ? TomoLogFile(markdown: stats.exportMarkdown(ui), name: fileName)
                              : TomoLogFile(json: stats.exportJSON(ui), name: fileName)
        exporting = true
    }

    private var fileName: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "\(lang.learner("export.filename")) \(f.string(from: TomoClock.now))"
    }

    /// Test runs (TOMO_SNAPSHOT_DIR): the exports and the recaps, as files to look at.
    private func writeExports(to dir: URL) {
        let stats = TomoStats(progress), ui = lang.learner
        try? stats.exportMarkdown(ui).write(to: dir.appendingPathComponent("export.md"), atomically: true, encoding: .utf8)
        try? stats.exportJSON(ui).write(to: dir.appendingPathComponent("export.json"))
        for r in TomoStats.Range.allCases {
            try? (loaded.recaps[r] ?? "").write(to: dir.appendingPathComponent("recap-\(r.rawValue).txt"), atomically: true, encoding: .utf8)
        }
    }

    // MARK: Today

    /// "Today" and the line, in one row; at the accessibility sizes, the line under "Today".
    private var today: some View {
        let layout = largeText ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                               : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return layout {
            Text(lang.learner("growth.today")).font(.headline)
            TomoTodayLine(parts: loaded.today, separator: lang.learner("list.separator")).font(.body.weight(.medium))
            if !largeText { Spacer(minLength: 0) }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Tomo's week

    /// The title with what to do with the postcard beside it (icons only on the iPhone), so the card fits the window or
    /// the screen above the tabs; then the postcard and every postcard so far. At the accessibility sizes, the buttons
    /// go under the title, which would otherwise have room for a syllable a line.
    private var week: some View {
        let header = largeText ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                               : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return VStack(alignment: .leading, spacing: 12) {
            header {
                VStack(alignment: .leading, spacing: 3) {
                    Text(lang.learner("postcard.title")).font(.title3.weight(.bold))
                    Text(lang.learner("postcard.note")).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let card = shown {
                    if !largeText { Spacer(minLength: 0) }
                    actions(card)
                }
            }
            if let card = shown {
                TomoPostcardView(card: card, look: look, material: material, portrait: phone, flipped: $flipped)
                    .frame(maxWidth: phone ? .infinity : 460)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                if loaded.cards.count > 1 { album }
            }
        }
    }

    /// Turn over, and share the postcard's picture (not a first postcard: there's nothing of the week on it yet).
    @ViewBuilder private func actions(_ card: TomoPostcard) -> some View {
        let row = HStack(spacing: phone ? 8 : 10) {
            Button { flipped.toggle() } label: {
                Label(lang.learner("postcard.turnOver"), systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
            }
            .buttonStyle(.bordered)
            if !card.isFirst, let shared {
                let title = lang.learner("postcard.shareTitle", ["range": card.range])
                ShareLink(item: shared.file, subject: Text(title), message: Text(card.recap),
                          preview: SharePreview(title, image: shared.preview)) {
                    Label(lang.learner("postcard.share"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
            }
        }
        if phone { row.labelStyle(.iconOnly).controlSize(.large) } else { row.controlSize(.regular) }
    }

    /// Every postcard so far, oldest first, scrolled to the newest. Tapping one shows it.
    private var album: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lang.learner("postcard.earlier")).font(.headline)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(loaded.cards) { card in
                            Button {
                                selected = card.id
                                flipped = false
                            } label: {
                                TomoPostcardMini(card: card, current: card.id == shown?.id)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(lang.learner("postcard.a11y.week", ["range": card.range]))
                            .id(card.id)
                        }
                    }
                    .padding(.vertical, 4).padding(.horizontal, 2)
                }
                .onAppear { proxy.scrollTo(shown?.id, anchor: .trailing) }
            }
        }
    }
}

/// The garden's summary line, the Today line and the Tomo screen's lines: one part wraps like a sentence; several are
/// phrases ("17 misses", "10月5日〜10月11日", "5 days in a row") joined by the list separator, which wrap between phrases
/// and never inside one, so a number stays with its unit and a date stays whole. Each is a `TomoPhrase`, keeping the
/// separator on its last word. A part that marks its own phrases (`TomoLineBreaks`: 「次の1語は 明日から」) is a
/// `TomoPhrase` alone too, so it wraps only there (#233).
struct TomoPhrases: View {
    let parts: [String]
    let separator: String
    /// How far a phrase shrinks before it wraps (`TomoPhrase`).
    var scale: CGFloat = 0.75

    var body: some View {
        if parts.count < 2 {
            let part = parts.first ?? ""
            if TomoLineBreaks.isMarked(part) { TomoPhrase(text: part, scale: scale) }
            else { Text(part).fixedSize(horizontal: false, vertical: true) }
        } else {
            TomoChipFlow(spacing: 4, lineSpacing: 1) {
                ForEach(Array(parts.enumerated()), id: \.offset) { i, part in
                    // The separator ends its line, never starts the next or stands alone
                    let mark = separator.trimmingCharacters(in: .whitespaces)
                    let phrase = i < parts.count - 1
                        ? part + (separator.first?.isWhitespace == true ? "\u{00A0}" : "") + mark : part
                    TomoPhrase(text: phrase, scale: scale)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// One phrase on one line. Too wide for a whole line, it shrinks a little (to `scale`, 0.75); only one wider still (the
/// iPhone's largest text) wraps: between the phrases it marks (`TomoLineBreaks`), each on a line of its own shrinking a
/// little if it must, so 「次の1語は / 明日から」 never breaks inside a word (#233); one with no marks, inside itself
/// rather than being cut (#197).
struct TomoPhrase: View {
    let text: String
    var scale: CGFloat = 0.75

    var body: some View {
        let line = TomoLineBreaks.spoken(text)   // on one line, a mark takes no room
        ViewThatFits(in: .horizontal) {
            Text(line).lineLimit(1)
            TomoShrinkable(scale: scale) { Text(line).lineLimit(1).minimumScaleFactor(scale) }
            if TomoLineBreaks.isMarked(text) {
                TomoChipFlow(spacing: 0, lineSpacing: 1) {
                    ForEach(Array(TomoLineBreaks.phrases(text).enumerated()), id: \.offset) { _, phrase in
                        TomoOneLine(text: phrase, scale: scale)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(line)
                .accessibilityAddTraits(.isStaticText)
            } else {
                Text(text).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One of a phrase's marked phrases: on one line, shrinking as far as `scale` to fit; wider still, it wraps inside
/// itself rather than being cut.
private struct TomoOneLine: View {
    let text: String
    let scale: CGFloat

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(text).lineLimit(1)
            TomoShrinkable(scale: scale) { Text(text).lineLimit(1).minimumScaleFactor(scale) }
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Its one-line text, offered as `scale` of its width: `ViewThatFits` picks it while the text, shrunk that far
/// (`minimumScaleFactor`), still fits the line, and it shrinks into the width it's given.
struct TomoShrinkable: Layout {
    let scale: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let text = subviews.first else { return .zero }
        guard let width = proposal.width, width.isFinite else {
            let ideal = text.sizeThatFits(.unspecified)
            return CGSize(width: ideal.width * scale, height: ideal.height)
        }
        return text.sizeThatFits(ProposedViewSize(width: width, height: proposal.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

/// A postcard in the row: its sky and hill, the week's picture, and its first day.
private struct TomoPostcardMini: View {
    let card: TomoPostcard
    let current: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = TomoPostcardColors(dark: scheme == .dark)
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [c.skyTop, c.skyBottom], startPoint: .top, endPoint: .bottom)
            Ellipse().fill(c.hill(card.hue)).frame(width: 110, height: 38).position(x: 46, y: 70)
            Group {
                // The week's picture; a quiet week's is sleep (Tomo itself is only ever drawn alive on screen).
                Text(card.picture ?? "\u{1F4A4}").font(.system(size: 24))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 7).padding(.bottom, 4)
            Text(Self.day(card.firstDay))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(c.ink)
                .padding(.leading, 6).padding(.top, 4)
        }
        .frame(width: 92, height: 62)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(current ? Color.primary : Color.clear, lineWidth: 2))
        .compositingGroup()
        .shadow(color: .black.opacity(0.18), radius: 4, y: 3)
    }

    @MainActor static func day(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: TomoLanguages.shared.learner.id)
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f.string(from: d)
    }
}

/// The Today line, with a little sun: on the Together screen and the Tomo screen.
public struct TomoTodayLine: View {
    let parts: [String]
    let separator: String

    /// Its phrases ("22 answers", "5 days in a row", `TomoStats.todayParts`), wrapping between them and never inside
    /// one, as the garden's summary does (`TomoPhrases`).
    public init(parts: [String], separator: String) {
        self.parts = parts
        self.separator = separator
    }

    public var body: some View {
        TomoPhraseLabel(parts: parts, separator: separator) { Image(systemName: "sun.max.fill").foregroundStyle(.orange) }
    }
}

/// Phrases (`TomoPhrases`) with an icon: the Today line's sun, the Tomo screen's flag and clock. At the accessibility
/// sizes, the icon beside a column of phrases. In a list row (the Tomo screen) at these sizes, a label puts its icon
/// in the text's first line and indents only that line, which indented each phrase's first line (#216).
struct TomoPhraseLabel<Icon: View>: View {
    let parts: [String]
    let separator: String
    var scale: CGFloat = 0.75
    @ViewBuilder let icon: Icon
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let phrases = TomoPhrases(parts: parts, separator: separator, scale: scale)
        if typeSize.isAccessibilitySize {
            HStack(alignment: .firstTextBaseline, spacing: 10) { icon; phrases }
        } else {
            Label { phrases } icon: { icon }
        }
    }
}

/// The learner's own log as a file to save (`fileExporter`): Markdown or JSON.
struct TomoLogFile: FileDocument {
    static let markdown = UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText
    static var readableContentTypes: [UTType] { [.json, markdown] }
    let data: Data
    let type: UTType
    let name: String

    init(markdown text: String, name: String) {
        data = Data(text.utf8)
        type = Self.markdown
        self.name = name
    }

    init(json: Data, name: String) {
        data = json
        type = .json
        self.name = name
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        type = configuration.contentType
        name = ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
