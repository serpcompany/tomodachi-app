import CoreTransferable
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Tomo's postcard, drawn (TomoPostcard.swift has what it says)
//
// The front: a sky, a hill in the week's colour, the week's word on a label and its picture bobbing, Tomo alive (happy,
// leaping when it grew that week, asleep on a quiet one), a stamp with Tomo's level and a postmark with the week's last
// day. The back: Tomo's message in its words, what it means, and what you did. It turns over with a spring; under
// Reduce Motion it fades, the picture holds still and Tomo plays its calm version. Landscape on the Mac, portrait on the
// iPhone. `TomoPostcardImage` renders both sides, still and in light colours, as a PNG to share (#29). The look and
// the material of the Tomo it shows are passed in, so a friend's postcard draws that friend.

public struct TomoPostcardView: View {
    let card: TomoPostcard
    let look: TomoLook
    let material: TomoMaterial
    let portrait: Bool
    @Binding var flipped: Bool
    /// Tomo drawn live (the screens), or still (the image to share).
    var live = true
    @ObservedObject private var motion = TomoMotion.shared
    @Environment(\.colorScheme) private var scheme

    /// `look` and `material`: the Tomo on the card (the learner's own: its look and `.own`).
    public init(card: TomoPostcard, look: TomoLook, material: TomoMaterial, portrait: Bool, flipped: Binding<Bool>) {
        self.card = card
        self.look = look
        self.material = material
        self.portrait = portrait
        _flipped = flipped
    }

    init(card: TomoPostcard, look: TomoLook, material: TomoMaterial, portrait: Bool, still: Bool) {
        self.init(card: card, look: look, material: material, portrait: portrait, flipped: .constant(false))
        live = !still
    }

    /// A postcard is 148 × 100; the iPhone stands it up a little shorter, so it fits above the tab bar with its buttons.
    private var ratio: CGFloat { portrait ? 100 / 132 : 148 / 100 }

    public var body: some View {
        ZStack {
            TomoPostcardFront(card: card, look: look, material: material, portrait: portrait, live: live)
                .modifier(TomoFlip(angle: flipped ? 180 : 0, front: true, calm: motion.reduce))
            TomoPostcardBack(card: card, portrait: portrait)
                .modifier(TomoFlip(angle: flipped ? 180 : 0, front: false, calm: motion.reduce))
        }
        .aspectRatio(ratio, contentMode: .fit)
        .animation(motion.reduce ? .easeInOut(duration: 0.3) : .spring(response: 0.7, dampingFraction: 0.72), value: flipped)
        .contentShape(Rectangle())
        .onTapGesture { flipped.toggle() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(TomoLanguages.shared.learner("postcard.a11y.turn"))
        .accessibilityAction { flipped.toggle() }
    }

    private var accessibility: String {
        let ui = TomoLanguages.shared.learner
        let title = card.isFirst ? ui("postcard.a11y.first") : ui("postcard.a11y.week", ["range": card.range])
        return ([title, card.word, card.message, card.gloss] + card.facts.map(\.text)).filter { !$0.isEmpty }
            .joined(separator: ". ")
    }
}

/// One side of the card as it turns over: it narrows to its edge and the other side widens out (a turn drawn in 2D, so
/// it looks the same in every snapshot and render), lifting a little at the middle. Shown while it faces you. Calm
/// (Reduce Motion): no turn, the sides fade into each other.
private struct TomoFlip: ViewModifier, Animatable {
    var angle: Double
    let front: Bool
    let calm: Bool

    nonisolated var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        let shown = front ? angle < 90 : angle >= 90
        let fade = min(max(angle / 180, 0), 1)
        let turn = angle * .pi / 180
        content
            .scaleEffect(x: calm ? 1 : max(abs(cos(turn)), 0.002), y: calm ? 1 : 1 + 0.05 * abs(sin(turn)))
            .opacity(calm ? (front ? 1 - fade : fade) : shown ? 1 : 0)
            .allowsHitTesting(shown)
    }
}

// MARK: Colours: a paper postcard, with a darker version for dark mode

struct TomoPostcardColors {
    let skyTop, skyBottom, ground, paper, ink, postmark, stamp: Color

    init(dark: Bool) {
        skyTop = Color(hex: dark ? "#1F2D4D" : "#CFE2FF")
        skyBottom = Color(hex: dark ? "#3A2744" : "#FFE9F2")
        ground = Color(hex: dark ? "#233424" : "#CFE2C1")
        paper = Color(hex: dark ? "#262932" : "#FFFFFF")
        ink = Color(hex: dark ? "#E9EBF2" : "#2B2F3D")
        postmark = Color(hex: dark ? "#9AA0B3" : "#7B8194")
        stamp = Color(hex: dark ? "#3A352B" : "#F7F1E3")
    }

    /// The hills' six soft colours, one per week.
    static let hues = ["#F5B85B", "#F2D35C", "#7FB5F0", "#8FD3A0", "#E9A0C8", "#B8A6F0"]
    func hill(_ hue: Int) -> Color { Color(hex: Self.hues[hue % Self.hues.count]).mix(with: ground, by: 0.45) }
    /// The card's own result colours: Win green, Practice blue, Miss red.
    static func color(_ dot: TomoPostcard.Fact.Dot) -> Color {
        switch dot {
        case .win: Color(hex: "#34D399")
        case .practice: Color(hex: "#8FB8DE")
        case .miss: Color(hex: "#F4505E")
        }
    }
}

// MARK: The front

struct TomoPostcardFront: View {
    let card: TomoPostcard
    let look: TomoLook
    let material: TomoMaterial
    let portrait: Bool
    let live: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height, c = TomoPostcardColors(dark: scheme == .dark)
            let unit = min(w, h)
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [c.skyTop, c.skyBottom], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.75))
                Ellipse().fill(c.hill(card.hue))
                    .frame(width: w * 1.2, height: h * (portrait ? 0.36 : 0.58))
                    .position(x: w / 2, y: h * (portrait ? 0.98 : 1.01))
                if let picture = card.picture {
                    TomoBobbing(live: live) {
                        Text(picture).font(.system(size: unit * (portrait ? 0.24 : 0.26)))
                            .shadow(color: .black.opacity(0.12), radius: 3, y: 4)
                    }
                    .position(x: w * (portrait ? 0.72 : 0.78), y: h * (portrait ? 0.58 : 0.64))
                }
                tomo
                    .frame(width: w * (portrait ? 0.6 : 0.44), height: h * (portrait ? 0.46 : 0.72))
                    .position(x: w * (portrait ? 0.36 : 0.28), y: h * (portrait ? 0.7 : 0.6))
                // The word's label stays clear of the postmark: a longer line wraps between its words.
                TomoWordFlow(text: card.word, spacing: unit * 0.02, lineSpacing: 0)
                    .font(.system(size: unit * (portrait ? 0.085 : 0.105), weight: .semibold, design: .rounded))
                    .foregroundStyle(c.ink)
                    .padding(.horizontal, unit * 0.035).padding(.vertical, unit * 0.012)
                    .background(c.paper.opacity(0.72), in: RoundedRectangle(cornerRadius: unit * 0.03))
                    .frame(maxWidth: w * (portrait ? 0.48 : 0.58), alignment: .leading)
                    .padding(.leading, w * 0.06).padding(.top, h * 0.07)
                TomoStamp(level: card.level, share: card.ageShare, color: look.body, paper: c.stamp, ink: c.ink)
                    .frame(width: w * (portrait ? 0.2 : 0.15), height: w * (portrait ? 0.25 : 0.1875))
                    .position(x: w * (portrait ? 0.85 : 0.875), y: h * 0.07 + w * (portrait ? 0.125 : 0.094))
                TomoPostmark(day: card.lastDay, color: c.postmark)
                    .frame(width: w * (portrait ? 0.22 : 0.16), height: w * (portrait ? 0.22 : 0.16))
                    .rotationEffect(.degrees(-14))
                    .position(x: w * (portrait ? 0.62 : 0.76), y: h * (portrait ? 0.12 : 0.23))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .compositingGroup()
        .shadow(color: .black.opacity(0.22), radius: 14, y: 10)
    }

    @ViewBuilder private var tomo: some View {
        let growth = CGFloat(min(max(card.age - 1, 0), TomoLook.ages - 1))
        if live {
            TomoPostcardTomo(look: look, material: material, growth: growth, card: card).id(card.id)
        } else {
            TomoBlobStill(state: card.asleep ? .sleeping : .idle, emote: card.asleep ? nil : card.grew ? .proud : .happy,
                          growth: growth, look: look, material: material)
        }
    }
}

/// Tomo on the postcard, alive: it settles in, then reacts to its week (a leap if it grew, a happy wiggle, a hello for
/// a first postcard), or sleeps through a quiet one.
private struct TomoPostcardTomo: View {
    let card: TomoPostcard
    @StateObject private var blob: TomoBlob
    private let growth: CGFloat

    init(look: TomoLook, material: TomoMaterial, growth: CGFloat, card: TomoPostcard) {
        self.card = card
        self.growth = growth
        _blob = StateObject(wrappedValue: TomoBlob(look: look, material: material, motion: .shared))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            Canvas { ctx, size in
                blob.frameDate = timeline.date
                blob.step()
                blob.draw(ctx, size: size)
            }
        }
        .onAppear {
            blob.setGrowth(growth)
            blob.setState(card.asleep ? .sleeping : .idle, force: true)
            guard !card.asleep else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if card.isFirst { blob.greet() } else if card.grew { blob.levelUp() } else { blob.emote(.happy) }
            }
        }
    }
}

/// The week's picture, bobbing gently (still under Reduce Motion, and in the image to share).
private struct TomoBobbing<Content: View>: View {
    let live: Bool
    @ViewBuilder let content: Content
    @ObservedObject private var motion = TomoMotion.shared

    var body: some View {
        if live && !motion.reduce {
            TimelineView(.animation(minimumInterval: 1 / 30)) { t in
                let s = sin(t.date.timeIntervalSinceReferenceDate * 2 * .pi / 3.4)
                content.offset(y: -4 * (s + 1)).rotationEffect(.degrees(2 * (s + 1)))
            }
        } else {
            content
        }
    }
}

/// A postage stamp: perforated edges, Tomo's level, and a ring in Tomo's colour for how far through its age it is.
private struct TomoStamp: View {
    let level: Int
    let share: Double
    let color: Color
    let paper: Color
    let ink: Color

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            ZStack {
                TomoPerforated(bite: w * 0.05).fill(paper, style: FillStyle(eoFill: true))
                    .shadow(color: .black.opacity(0.15), radius: 1.5, y: 1.5)
                VStack(spacing: w * 0.06) {
                    Text(TomoLanguages.shared.learner("level", ["n": "\(level)"]))
                        .font(.system(size: w * 0.2, weight: .heavy, design: .rounded)).foregroundStyle(ink)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    ZStack {
                        Circle().stroke(ink.opacity(0.15), lineWidth: w * 0.09)
                        Circle().trim(from: 0, to: max(0.04, share)).stroke(color, style: StrokeStyle(lineWidth: w * 0.09, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: w * 0.42, height: w * 0.42)
                }
                .padding(w * 0.1)
            }
        }
    }
}

/// A rectangle with round bites out of its edges, like a stamp's perforations.
private struct TomoPerforated: Shape {
    let bite: CGFloat

    func path(in r: CGRect) -> Path {
        var p = Path(r)
        let step = bite * 2.7
        for x in stride(from: r.minX + step / 2, through: r.maxX - bite, by: step) {
            p.addEllipse(in: CGRect(x: x - bite, y: r.minY - bite, width: bite * 2, height: bite * 2))
            p.addEllipse(in: CGRect(x: x - bite, y: r.maxY - bite, width: bite * 2, height: bite * 2))
        }
        for y in stride(from: r.minY + step / 2, through: r.maxY - bite, by: step) {
            p.addEllipse(in: CGRect(x: r.minX - bite, y: y - bite, width: bite * 2, height: bite * 2))
            p.addEllipse(in: CGRect(x: r.maxX - bite, y: y - bite, width: bite * 2, height: bite * 2))
        }
        return p
    }
}

/// The postmark: a ring with the week's last day and year, in the learner's language.
private struct TomoPostmark: View {
    let day: Date
    let color: Color

    private func text(_ template: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: TomoLanguages.shared.learner.id)
        f.setLocalizedDateFormatFromTemplate(template)
        return f.string(from: day).uppercased(with: f.locale)
    }

    var body: some View {
        GeometryReader { g in
            ZStack {
                Circle().stroke(color, lineWidth: 1.5)
                VStack(spacing: 0) {
                    Text(text("MMMd"))
                    Text(text("y"))
                }
                .font(.system(size: g.size.width * 0.16, weight: .medium, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.5)
                .padding(g.size.width * 0.1)
            }
            .opacity(0.85)
        }
    }
}

// MARK: The back

struct TomoPostcardBack: View {
    let card: TomoPostcard
    let portrait: Bool
    @ObservedObject private var lang = TomoLanguages.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height, c = TomoPostcardColors(dark: scheme == .dark)
            let unit = min(w, h) * (portrait ? 0.95 : 1)
            let layout = portrait ? AnyLayout(VStackLayout(alignment: .leading, spacing: unit * 0.07))
                                  : AnyLayout(HStackLayout(alignment: .top, spacing: w * 0.05))
            layout {
                VStack(alignment: .leading, spacing: unit * 0.025) {
                    TomoWordFlow(text: card.message, spacing: unit * 0.03, lineSpacing: unit * 0.025)
                        .font(.system(size: unit * 0.066, weight: .semibold, design: .rounded))
                        .foregroundStyle(c.ink)
                    if !card.gloss.isEmpty {
                        TomoWordFlow(text: card.gloss, spacing: unit * 0.012, lineSpacing: unit * 0.006)
                            .font(.system(size: unit * 0.044)).foregroundStyle(c.postmark)
                    }
                    Text(lang.learner("postcard.signed")).font(.system(size: unit * 0.044)).foregroundStyle(c.postmark)
                }
                .frame(maxWidth: portrait ? .infinity : w * 0.48, alignment: .leading)
                Rectangle().fill(c.ink.opacity(0.18))
                    .frame(width: portrait ? nil : 1, height: portrait ? 1 : h * 0.76)
                VStack(alignment: .leading, spacing: unit * 0.022) {
                    Text(card.isFirst ? lang.learner("postcard.title") : card.range.uppercased())
                        .font(.system(size: unit * 0.038, weight: .medium, design: .monospaced))
                        .tracking(1).foregroundStyle(c.postmark).lineLimit(1).minimumScaleFactor(0.6)
                    // Standing up (the iPhone), the facts take two columns, so all of them fit at a readable size. A
                    // plain grid, not a lazy one: the picture to share draws every row.
                    let columns = portrait && !card.isFirst ? 2 : 1
                    let rows = stride(from: 0, to: card.facts.count, by: columns).map {
                        Array(card.facts[$0..<min($0 + columns, card.facts.count)])
                    }
                    Grid(alignment: .leading, horizontalSpacing: unit * 0.05, verticalSpacing: unit * 0.022) {
                        ForEach(rows, id: \.first?.id) { row in
                            GridRow {
                                ForEach(row) { fact in factView(fact, unit: unit, colors: c) }
                                if row.count < columns { Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, w * (portrait ? 0.08 : 0.05))
            .padding(.vertical, h * (portrait ? 0.06 : 0.07))
            .frame(width: w, height: h, alignment: .topLeading)
            .background(c.paper)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .compositingGroup()
        .shadow(color: .black.opacity(0.22), radius: 14, y: 10)
    }

    private func factView(_ fact: TomoPostcard.Fact, unit: CGFloat, colors c: TomoPostcardColors) -> some View {
        VStack(alignment: .leading, spacing: unit * 0.012) {
            HStack(spacing: unit * 0.02) {
                if let dot = fact.dot {
                    Circle().fill(TomoPostcardColors.color(dot))
                        .frame(width: unit * 0.025, height: unit * 0.025)
                }
                Text(fact.text).font(.system(size: unit * (card.isFirst ? 0.045 : 0.048)))
                    .foregroundStyle(c.ink).lineLimit(card.isFirst ? 5 : 1).minimumScaleFactor(0.6)
                    .fixedSize(horizontal: false, vertical: card.isFirst)
            }
            if !card.isFirst {
                Line().stroke(c.ink.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(height: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct Line: Shape {
        func path(in r: CGRect) -> Path { Path { $0.move(to: CGPoint(x: r.minX, y: r.midY)); $0.addLine(to: CGPoint(x: r.maxX, y: r.midY)) } }
    }
}

/// Words that wrap only between words, never inside one: Japanese would otherwise break anywhere (やっ|たー).
private struct TomoWordFlow: View {
    let text: String
    let spacing: CGFloat
    let lineSpacing: CGFloat

    var body: some View {
        TomoFlowLayout(spacing: spacing, lineSpacing: lineSpacing) {
            ForEach(Array(text.split(separator: " ").enumerated()), id: \.offset) { _, word in
                Text(word).lineLimit(1).minimumScaleFactor(0.5)
            }
        }
    }
}

private struct TomoFlowLayout: Layout {
    let spacing: CGFloat
    let lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews) {
            for (i, x, size) in row.items {
                subviews[i].place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + row.y),
                                  proposal: ProposedViewSize(size))
            }
        }
    }

    private struct Row { var y: CGFloat; var width: CGFloat = 0; var height: CGFloat = 0; var items: [(Int, CGFloat, CGSize)] = [] }

    private func arrange(width: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows = [Row(y: 0)]
        for (i, v) in subviews.enumerated() {
            var size = v.sizeThatFits(.unspecified)
            if size.width > width { size = v.sizeThatFits(ProposedViewSize(width: width, height: nil)) }
            if !rows[rows.count - 1].items.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + lineSpacing))
            }
            var row = rows[rows.count - 1]
            let x = row.items.isEmpty ? 0 : row.width + spacing
            row.items.append((i, x, size))
            row.width = x + size.width
            row.height = max(row.height, size.height)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

// MARK: Sharing: both sides as one picture

/// A postcard's picture, ready to share: a PNG, named for its week.
public struct TomoPostcardFile: Transferable, Sendable {
    public let png: Data
    public let name: String

    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.png }
            .suggestedFileName { $0.name }
    }
}

@MainActor
public enum TomoPostcardImage {
    /// Both sides of the card, front over back, still and in light colours, at 2× (1440 pt wide): a PNG to share, and
    /// its picture for the share preview. TOMO_SNAPSHOT_DIR keeps a copy (`postcard-share-<day>.png`) for checks.
    public static func render(_ card: TomoPostcard, look: TomoLook, material: TomoMaterial) -> (file: TomoPostcardFile, preview: Image)? {
        let sheet = VStack(spacing: 24) {
            TomoPostcardView(card: card, look: look, material: material, portrait: false, still: true)
            TomoPostcardBack(card: card, portrait: false).aspectRatio(148 / 100, contentMode: .fit)
        }
        .padding(32)
        .frame(width: 720)
        .background(LinearGradient(colors: [Color(hex: "#EEF3FB"), Color(hex: "#FBF1F5")], startPoint: .top, endPoint: .bottom))
        .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        guard let cg = renderer.cgImage, let png = pngData(cg) else { return nil }
        let title = TomoLanguages.shared.learner("postcard.shareTitle", ["range": card.range])
        let name = title.replacingOccurrences(of: "/", with: "-") + ".png"
        if let dir = ProcessInfo.processInfo.environment["TOMO_SNAPSHOT_DIR"] {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("postcard-share-\(f.string(from: card.firstDay)).png"))
        }
        return (TomoPostcardFile(png: png, name: name), Image(decorative: cg, scale: 2))
    }

    private static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }
}
