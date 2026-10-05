import NaturalLanguage
import SwiftUI

// MARK: - Clickable words in Tomo's line
//
// Click one word → its word card (dictionary). Drag across words → "I don't understand" → the
// Explain panel explains just that part. Today the card's meaning comes from the AI provider as a
// stand-in; the Zenbu dictionary (Language Reference IDs, Sudachi) replaces it (docs/architecture.md).

public struct TomoWordCard: Sendable, Equatable {
    public let word: String          // as Tomo said it
    public let headword: String      // dictionary form
    public let reading: String?      // kana reading / pronunciation guide
    public let meaning: String       // in the learner's language
    public let note: String?
    public let usedAI: Bool
}

public enum TomoWords {
    /// Words of a line for display. Text is split on spaces (Japanese packs write picture-book style
    /// with spaces between words); unspaced Japanese falls back to Apple's word tokenizer.
    public static func tokens(_ line: String, script: String, spacesOnly: Bool = false) -> [String] {
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

    /// The word without surrounding punctuation, for lookups.
    public static func bare(_ token: String) -> String {
        token.trimmingCharacters(in: .punctuationCharacters.union(.symbols).union(.whitespaces))
    }
}

extension TomoBrain {
    public static func define(word: String, line: String, ai: TomoAIConfig?, language l: LanguageContext) async -> TomoWordCard {
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

public struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 2

    public init(spacing: CGFloat = 6, lineSpacing: CGFloat = 2) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? .infinity).size
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
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
