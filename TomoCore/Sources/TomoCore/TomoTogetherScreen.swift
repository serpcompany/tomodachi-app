import SwiftUI

// MARK: - Together: what you and Tomo did (#137 item 2), the Mac window's page and the iPhone's tab
//
// Today ("12 answers · 3 new words · Lv 61 → 62") and Tomo's week, as a postcard that comes every Monday morning: the
// newest one, turned over with a tap, shared as a picture (#29), and every earlier one in a row underneath. A brand-new
// Tomo, before its first Monday, gets its first postcard (Tomo says hello and when the first one comes) instead of a
// row of zeros. Everything shown comes from TomoStats, for the Tomo passed in (its progress and look), so a friend could
// have its own; the screen decides nothing. The word garden joins it next (#137). Test runs: TOMO_POSTCARD=<n> shows the
// postcard n weeks before the newest, TOMO_POSTCARD_TURN=<seconds> turns it over that long after it shows.

public struct TomoTogetherScreen: View {
    private let progress: TomoProgress
    private let look: TomoLook
    private let material: TomoMaterial
    private let version: Int
    @ObservedObject private var lang = TomoLanguages.shared

    /// `progress`, `look` and `material`: the Tomo these are about (the learner's own: its progress, its look and
    /// `.own`). `version`: bump it when its progress changes (TomoGame's `progressVersion`), so the numbers are read again.
    public init(progress: TomoProgress, look: TomoLook, material: TomoMaterial, version: Int) {
        self.progress = progress
        self.look = look
        self.material = material
        self.version = version
    }

    private struct Loaded {
        var key = ""
        var today = ""
        var cards: [TomoPostcard] = []
        var first: TomoPostcard?
    }

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
                week
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
        }
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
        let cards = stats.postcards(ui)
        loaded = Loaded(key: key, today: stats.todayLine(ui), cards: cards, first: cards.isEmpty ? stats.firstPostcard(ui) : nil)
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
