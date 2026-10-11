import Foundation

/// Where a heading may wrap (#225). Japanese is written without spaces, so a line breaker may split it between any two
/// characters, even inside a word ("生ま / れます"). A heading in the packs marks its phrases with a space between two
/// Japanese characters ("ことばのほうから 来てもらおう"): drawn through `phrased`, it wraps only there and the space
/// isn't drawn, so a heading too long for its lines shrinks (its `minimumScaleFactor`) instead of breaking a word.
/// English and other spaced text wraps at its spaces, as before. The Tomo screen's lines and the Today line mark theirs
/// the same way (#233). Where a phrase starts or ends with a number or a time ("{known}", "{time}"), a space there
/// wouldn't be between two Japanese characters, so the pack marks it with a zero-width space ("\u200b"), which never
/// shows; and a number stays with its word through a no-break space ("Lv\u00a0{next}").
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
            if let after, !c[i].isWhitespace, !after.isWhitespace, c[i] != phraseBreak, after != phraseBreak,
               isWide(c[i]) || isWide(after) { out.append(join) }
        }
        return out
    }

    /// `s` as it reads, for VoiceOver: the phrase marks and the joins taken out. Text that's always one line (the card,
    /// the iPhone header, the Lock Screen) shows a marked line this way too (`timeText`, `TomoGame.whatsLeft`).
    static func spoken(_ s: String) -> String {
        String(phrased(s).filter { $0 != join && $0 != phraseBreak }.map { $0 == keep ? " " : $0 })
    }

    /// Whether `s` marks its phrases: a space between two Japanese characters, or a zero-width space.
    static func isMarked(_ s: String) -> Bool {
        let c = Array(s)
        return c.contains(phraseBreak)
            || c.indices.dropFirst().dropLast().contains { c[$0] == " " && isWide(c[$0 - 1]) && isWide(c[$0 + 1]) }
    }

    /// A phrase as a view that wraps draws it (#233): `phrased` when it marks its phrases, so 「次の1語は 明日から」
    /// wraps only between them; as it is when it doesn't, so a sentence wraps as a sentence does.
    static func wrapping(_ s: String) -> String { isMarked(s) ? phrased(s) : s }

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
