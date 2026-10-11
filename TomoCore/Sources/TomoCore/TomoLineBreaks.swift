import Foundation

/// Where a heading may wrap (#225). Japanese is written without spaces, so a line breaker may split it between any two
/// characters, even inside a word ("生ま / れます"). A heading in the packs marks its phrases with a space between two
/// Japanese characters ("ことばのほうから 来てもらおう"): drawn through `phrased`, it wraps only there and the space
/// isn't drawn, so a heading too long for its lines shrinks (its `minimumScaleFactor`) instead of breaking a word.
/// English and other spaced text wraps at its spaces, as before.
enum TomoLineBreaks {
    /// Lets nothing break on either side of it (Unicode's word joiner).
    static let join: Character = "\u{2060}"
    /// Where a marked phrase may wrap: a break with no width.
    static let phraseBreak: Character = "\u{200B}"
    /// A space that never breaks: one beside a single Japanese character, as in "Tomo が", stays with its word.
    static let keep: Character = "\u{00A0}"

    /// `s` with breaks only at its spaces. A space between two Japanese characters becomes a break with no width, a space
    /// beside one Japanese character never breaks, and every other pair with a Japanese character in it is joined.
    static func phrased(_ s: String) -> String {
        let c = Array(s)
        var out = ""
        for i in c.indices {
            let before = i > 0 ? c[i - 1] : nil, after = i + 1 < c.count ? c[i + 1] : nil
            if c[i] == " ", let before, let after, isWide(before) || isWide(after) {
                out.append(isWide(before) && isWide(after) ? phraseBreak : keep)
                continue
            }
            out.append(c[i])
            if let after, !c[i].isWhitespace, !after.isWhitespace, isWide(c[i]) || isWide(after) { out.append(join) }
        }
        return out
    }

    /// `s` as it reads, for VoiceOver: the phrase marks and the joins taken out.
    static func spoken(_ s: String) -> String {
        String(phrased(s).filter { $0 != join && $0 != phraseBreak }.map { $0 == keep ? " " : $0 })
    }

    /// The pieces `phrased` may wrap between, as they read.
    static func phrases(_ s: String) -> [String] {
        phrased(s).split(whereSeparator: { $0 == phraseBreak || $0 == " " })
            .map { String($0.filter { $0 != join }.map { $0 == keep ? " " : $0 }) }
    }

    /// A character a line breaker may break beside without a space: kana, kanji, their punctuation and full-width forms.
    static func isWide(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        return (0x3001...0x30FF).contains(v) || (0x31F0...0x31FF).contains(v) || (0x3400...0x4DBF).contains(v)
            || (0x4E00...0x9FFF).contains(v) || (0xF900...0xFAFF).contains(v) || (0xFF01...0xFFEF).contains(v)
            || (0x20000...0x3FFFF).contains(v)
    }
}
