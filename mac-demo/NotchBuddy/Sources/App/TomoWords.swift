import CoreServices
import NaturalLanguage
import SwiftUI

// MARK: - Clickable words in Tomo's line
//
// Click one word → its word card (dictionary). Drag across words → "I don't understand" → the
// Explain panel explains just that part. Today the card's meaning comes from the AI provider as a
// stand-in; the Zenbu dictionary (Language Reference IDs, Sudachi) replaces it (docs/architecture.md).

struct TomoWordCard: Sendable, Equatable {
    let word: String          // as Tomo said it
    let headword: String      // dictionary form
    let reading: String?      // kana reading / pronunciation guide
    let meaning: String       // in the learner's language
    let note: String?
    let usedAI: Bool
}

enum TomoWords {
    /// Words of a line for display. Text is split on spaces (Japanese packs write picture-book style
    /// with spaces between words); unspaced Japanese falls back to Apple's word tokenizer.
    static func tokens(_ line: String, script: String, spacesOnly: Bool = false) -> [String] {
        let spaced = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        // Pack text is already spaced; only long unspaced AI lines need the (imperfect) word tokenizer,
        // which splits baby words like ワンワン.
        guard !spacesOnly, script == "Jpan", spaced.count <= 1, line.count > 10 else { return spaced }
        let t = NLTokenizer(unit: .word)
        t.setLanguage(.japanese)
        t.string = line
        var out: [String] = [], last = line.startIndex
        t.enumerateTokens(in: line.startIndex..<line.endIndex) { r, _ in
            if r.lowerBound > last, var prev = out.popLast() { prev += line[last..<r.lowerBound]; out.append(prev) }
            out.append(String(line[r])); last = r.upperBound
            return true
        }
        if last < line.endIndex, var prev = out.popLast() { prev += line[last...]; out.append(prev) }
        return out.isEmpty ? [line] : out
    }

    /// The Mac's built-in dictionaries (Dictionary.app), offline. The system picks the first active
    /// dictionary with an entry; usually a monolingual one (Oxford English, 大辞林).
    static func macDictionary(_ word: String) -> String? {
        guard !word.isEmpty else { return nil }
        let cf = word as CFString
        let def = DCSCopyTextDefinition(nil, cf, CFRangeMake(0, CFStringGetLength(cf)))?.takeRetainedValue() as String?
        return def.map { String($0.prefix(260)) }
    }

    /// Opens Dictionary.app on the word (all installed dictionaries, including bilingual ones).
    static func openMacDictionary(_ word: String) {
        let q = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? word
        if let url = URL(string: "dict://\(q)") { NSWorkspace.shared.open(url) }
    }

    // Word layout constants shared by measuring and drawing, so the fit is exact.
    static let wordPadding: CGFloat = 2              // each side of a clickable word
    static let lineSpacing: CGFloat = 2
    static func wordSpacing(script: String, size: CGFloat) -> CGFloat { script == "Jpan" ? 2 : size * 0.2 }

    static func lineFont(_ size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: .bold)
        return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    }

    /// The largest font size (24 → 15 pt) at which the words, laid out exactly like `TomoLineView`
    /// (per-word padding, gaps, wrapping), fit in `box`.
    static func fittingSize(_ words: [String], script: String, in box: CGSize, maxSize: CGFloat = 24) -> CGFloat {
        for size: CGFloat in [28, 26, 24, 22, 20, 18, 17, 16, 15] where size <= maxSize {
            let font = lineFont(size)
            let gap = wordSpacing(script: script, size: size)
            var lines = 1, x: CGFloat = 0
            for w in words {
                let width = ceil((w as NSString).size(withAttributes: [.font: font]).width) + wordPadding * 2
                if width > box.width { lines = .max / 2; break }      // one word wider than the box: smaller size
                if x > 0 && x + width > box.width { lines += 1; x = 0 }
                x += width + gap
            }
            let lineHeight = ceil(font.ascender - font.descender + font.leading)
            if CGFloat(lines) * lineHeight + CGFloat(lines - 1) * lineSpacing <= box.height { return size }
        }
        return 15
    }

    /// The word without surrounding punctuation, for lookups.
    static func bare(_ token: String) -> String {
        token.trimmingCharacters(in: .punctuationCharacters.union(.symbols).union(.whitespaces))
    }
}

extension TomoBrain {
    static func define(word: String, line: String, ai: TomoAIConfig?, language l: LanguageContext) async -> TomoWordCard {
        let offline = TomoWordCard(word: word, headword: word, reading: nil, meaning: "", note: nil, usedAI: false)
        guard let ai, ai.isUsable else { return offline }
        let target = l.target.name("en"), learner = l.learner.name
        let system = """
        You are a pocket \(target)–\(learner) dictionary for a learner who speaks \(learner). \
        Define the word as it is used in the sentence. Write meaning and note in \(learner), briefly.
        Answer with JSON only: {"headword": "dictionary form in \(target)", \
        "reading": "\(l.target.script == "Jpan" ? "reading in hiragana" : "pronunciation hint, or empty")", \
        "meaning": "...", "note": "one short usage note, or empty"}
        """
        guard let text = try? await TomoAI.complete(system: system,
                                                     user: "Sentence: \(line)\nWord: \(word)", config: ai),
              let s = text.firstIndex(of: "{"), let e = text.lastIndex(of: "}"),
              let obj = try? JSONSerialization.jsonObject(with: Data(text[s...e].utf8)) as? [String: Any],
              let meaning = obj["meaning"] as? String
        else { return offline }
        func opt(_ k: String) -> String? { (obj[k] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        return TomoWordCard(word: word, headword: opt("headword") ?? word, reading: opt("reading"),
                            meaning: meaning, note: opt("note"), usedAI: true)
    }
}

// MARK: - Flow layout (words wrap like text)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, p) in arrange(subviews, width: bounds.width).points.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (points: [CGPoint], size: CGSize) {
        var points: [CGPoint] = [], x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxW: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { x = 0; y += rowH + lineSpacing; rowH = 0 }
            points.append(CGPoint(x: x, y: y))
            x += s.width + spacing
            rowH = max(rowH, s.height)
            maxW = max(maxW, x - spacing)
        }
        return (points, CGSize(width: maxW, height: y + rowH))
    }
}

// MARK: - Tomo's line as clickable words

struct TomoLineView: View {
    @ObservedObject var game: TomoGame
    @ObservedObject var lang = TomoLanguages.shared
    /// Highlighted words (drag across them); the card shows "I don't understand" for these.
    @Binding var selection: ClosedRange<Int>?
    /// The fixed box the line must fit in (TomoGrid.lineRow / wordRow).
    let size: CGSize
    /// What Tomo said (the talking line, or a picture round's word).
    let text: String
    var maxSize: CGFloat = 24
    /// Drag-to-highlight for "I don't understand" (talking stage only).
    var selectable = true
    /// Split only on spaces (pack text such as picture-round words).
    var spacesOnly = false
    @State private var frames: [Int: CGRect] = [:]
    @State private var dragStart: Int?
    @State private var hovered: Int?

    private var words: [String] { TomoWords.tokens(text, script: lang.target.script, spacesOnly: spacesOnly) }
    /// The largest size at which the line fits the box, measured the way it's drawn.
    private var fontSize: CGFloat { TomoWords.fittingSize(words, script: lang.target.script, in: size, maxSize: maxSize) }

    var body: some View {
        FlowLayout(spacing: TomoWords.wordSpacing(script: lang.target.script, size: fontSize),
                   lineSpacing: TomoWords.lineSpacing) {
            ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                Text(w)
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                    .fixedSize()
                    .padding(.horizontal, TomoWords.wordPadding)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(selection?.contains(i) == true ? Color(hex: "#6366F1").opacity(0.45)
                                  : hovered == i ? Color.white.opacity(0.1) : .clear)
                    )
                    .overlay(alignment: .bottom) {
                        if hovered == i { Rectangle().fill(Color.white.opacity(0.5)).frame(height: 1.5).offset(y: 1) }
                    }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("tomoLine")) } action: { frames[i] = $0 }
                    .onHover { hovered = $0 ? i : (hovered == i ? nil : hovered) }
            }
        }
        .coordinateSpace(name: "tomoLine")
        .onChange(of: game.cardRequest) { _, i in
            guard let i, words.indices.contains(i) else { return }
            game.openWord(TomoWords.bare(words[i]))
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("tomoLine"))
                .onChanged { g in
                    guard let here = index(at: g.location) else { return }
                    if dragStart == nil { dragStart = index(at: g.startLocation) ?? here }
                    if selectable, hypot(g.translation.width, g.translation.height) > 4, let s = dragStart {
                        selection = min(s, here)...max(s, here)
                    }
                }
                .onEnded { g in
                    defer { dragStart = nil }
                    let moved = hypot(g.translation.width, g.translation.height) > 4
                    if !moved, let i = index(at: g.location) {        // click one word → word card
                        selection = nil
                        game.openWord(TomoWords.bare(words[i]))
                    }
                }
        )
        .id(text)
    }

    private func index(at p: CGPoint) -> Int? {
        frames.first { $0.value.insetBy(dx: -3, dy: -3).contains(p) }?.key
    }
}

