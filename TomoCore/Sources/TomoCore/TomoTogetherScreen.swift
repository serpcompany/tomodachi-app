import SwiftUI
import UniformTypeIdentifiers

// MARK: - Together: what you and Tomo did (#137 item 2), the Mac window's page and the iPhone's tab
//
// Today ("12 answers · 3 new words · 5 days in a row"), the word garden (TomoGarden.swift: every word met, growing, for
// today, this week or since you met, with a replay, Copy recap, and the learner's own log to export as Markdown or
// JSON), and Tomo's week, as a postcard that comes every Monday morning: the newest one, turned over with a tap, shared
// as a picture (#29), and every earlier one in a row underneath. On the Monday a postcard comes, it's at the top. A
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
        var today = ""
        var cards: [TomoPostcard] = []
        var first: TomoPostcard?
        var postcardToday = false
        var plants: [TomoStats.Plant] = []
        var summaries: [TomoStats.Range: TomoStats.Summary] = [:]
        var lines: [TomoStats.Range: (String, String)] = [:]
        var recaps: [TomoStats.Range: String] = [:]
        var since = Date()
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

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if progress.isScratch {
                    Label(lang.learner("words.testing"), systemImage: "flask").foregroundStyle(.orange)
                }
                today
                if loaded.postcardToday { week; garden } else { garden; week }
            }
            .padding(.horizontal, phone ? 16 : 24)
            .padding(.vertical, phone ? 12 : 16)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
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
        var l = Loaded(key: key, today: stats.todayLine(ui), cards: cards, first: cards.isEmpty ? stats.firstPostcard(ui) : nil,
                       postcardToday: stats.postcardCameToday(ui) != nil, plants: plants)
        l.since = plants.first?.met ?? progress.metAt
        for r in TomoStats.Range.allCases {
            let s = stats.summary(r)
            l.summaries[r] = s
            l.lines[r] = Self.lines(r, s, plants: plants.count, stats: stats, ui)
            l.recaps[r] = stats.recap(s, range: stats.rangeText(r, ui), ui)
        }
        loaded = l
    }

    /// The garden's two lines for a range: what grew ("3 new sprouts · 5 grew"), then the watering, misses and when.
    private static func lines(_ r: TomoStats.Range, _ s: TomoStats.Summary, plants: Int, stats: TomoStats,
                              _ ui: LearnerPack) -> (String, String) {
        guard plants > 0 else { return (ui("garden.empty.title"), ui("garden.empty.note")) }
        if r == .all { return (ui.counted("garden.planted", plants), ui("garden.order")) }
        guard s.played else { return (ui("garden.quiet.\(r.rawValue)"), ui("garden.quiet.note")) }
        let sep = ui("list.separator")
        var top: [String] = [], bottom: [String] = []
        if !s.newWords.isEmpty { top.append(ui.counted("garden.sprouts", s.newWords.count)) }
        if !s.stronger.isEmpty { top.append(ui.counted("garden.grew", s.stronger.count)) }
        var rest: [String] = []
        if s.practice > 0 { rest.append(ui.counted("garden.watered", s.practice)) }
        if s.misses > 0 { rest.append(ui.counted("postcard.misses", s.misses)) }
        if top.isEmpty, let first = rest.first { top.append(first); rest.removeFirst() }
        bottom += rest
        bottom.append(stats.rangeText(r, ui))
        return (top.joined(separator: sep), bottom.joined(separator: sep))
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
                if !phone, !loaded.plants.isEmpty {
                    Spacer(minLength: 0)
                    rangePicker
                }
            }
            if phone, !loaded.plants.isEmpty { rangePicker }
            TimelineView(.animation(minimumInterval: 1 / 20, paused: replayStart == nil)) { tl in
                let at = gardenTime(tl.date)
                VStack(alignment: .leading, spacing: 10) {
                    if phone {
                        // Square on the iPhone, so the summary shows above the tabs; a tapped word shows over the
                        // garden's front, where the thumb is.
                        field(at: at).aspectRatio(1, contentMode: .fit)
                            .overlay(alignment: .bottom) { if let card = plantCard { card.padding(8) } }
                        summary
                        TomoGardenLegend(horizontal: true)
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

    private var rangePicker: some View {
        Picker(lang.learner("garden.title"), selection: $range) {
            ForEach(TomoStats.Range.allCases, id: \.self) { r in Text(lang.learner("garden.range.\(r.rawValue)")).tag(r) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
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
        let lines = loaded.lines[range] ?? ("", "")
        return VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(lines.0).font(.headline).fixedSize(horizontal: false, vertical: true)
                if !lines.1.isEmpty {
                    Text(lines.1).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if !loaded.plants.isEmpty {
                let c = TomoGardenColors(dark: false)
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

    private func replayRow(at now: Date) -> some View {
        let k = replayPosition(now) ?? 1
        let day = gardenTime(now) ?? TomoClock.now
        return HStack(spacing: 10) {
            Button(action: replay) {
                Label(lang.learner(replayStart == nil ? "garden.replay" : "garden.replaying"), systemImage: "play.fill")
            }
            .buttonStyle(.bordered)
            .disabled(replayStart != nil)
            Slider(value: Binding(get: { k }, set: { scrub = $0 >= 0.999 ? nil : $0; replayStart = nil; plantShown = nil }),
                   in: 0...1)
                .tint(TomoGardenColors(dark: false).win)
                .accessibilityLabel(lang.learner("garden.day"))
                .accessibilityValue(TomoStats.shortDay(day, lang.learner))
            Text(TomoStats.shortDay(day, lang.learner)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                .frame(minWidth: 52, alignment: .trailing)
        }
    }

    // MARK: Copy recap, and the learner's own log

    private var gardenActions: some View {
        HStack(spacing: 10) {
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
            .fixedSize()
            Spacer(minLength: 0)
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

    /// "Today" and the line, in one row.
    private var today: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(lang.learner("growth.today")).font(.headline)
            TomoTodayLine(text: loaded.today).font(.body.weight(.medium))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Tomo's week

    /// The title with what to do with the postcard beside it (icons only on the iPhone), so the card fits the window or
    /// the screen above the tabs; then the postcard and every postcard so far.
    private var week: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(lang.learner("postcard.title")).font(.title3.weight(.bold))
                    Text(lang.learner("postcard.note")).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let card = shown {
                    Spacer(minLength: 0)
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
    let text: String

    public init(text: String) { self.text = text }

    public var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "sun.max.fill").foregroundStyle(.orange)
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
