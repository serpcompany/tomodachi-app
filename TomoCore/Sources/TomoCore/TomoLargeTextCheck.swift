import CoreText
import SwiftUI

// MARK: - The iPhone's Tomo and Words screens at the largest text (#213, #233)
//
// What a snapshot can't show for every pack: at the largest Dynamic Type size (accessibility XXXL) on the narrowest
// iPhone (an SE, 375 pt), each word in every target pack fits its row, and each phrase the Tomo screen and the Today
// line can say fits its line, so nothing breaks inside a word; and "Play with Tomo" wraps only between its phrases at
// every accessibility size. Measured with SwiftUI's and CoreText's own text layout, at the sizes iOS gives these text
// styles there (body 53 pt, callout 51 pt). Run by `swift test` and TOMO_SELFTEST.

@MainActor
public enum TomoLargeTextCheck {
    /// An iPhone SE's width.
    static let phone: CGFloat = 375
    /// A Form row's text on an SE at the largest text: the inset card (16 pt each side) less the row's own inset
    /// (17 pt each side), as the Tomo screen draws it (x 33 to 343).
    static let formRow: CGFloat = 375 - 2 * 16 - 2 * 17
    /// A Words row's column for the word: the list's side padding (16 pt) and the row's (10 pt), each side, less the
    /// picture's column (30 pt) and its gap (10 pt).
    static let wordColumn: CGFloat = 375 - 2 * 16 - 2 * 10 - 30 - 10
    /// An icon beside a column of phrases (the flag, the clock, the Today line's sun) and its gap, in ems of the text:
    /// measured on an SE, the flag's column starts 70 pt in at 51 pt, the sun's 74 pt in at 53 pt (about 1.4 em).
    static let iconEms: CGFloat = 1.45
    /// The play button: its text's inset from the button's edges (a large prominent button's, about 20 pt), and its
    /// icon and the gap beside it, in ems of the text (measured on an SE at the largest text: 32 pt at 53 pt, and 8).
    static let playInset: CGFloat = 20, playIconEms: CGFloat = 0.6, playGap: CGFloat = 8

    public static func selfTest(_ check: (Bool, String) -> Void) {
        marks(check)
        words(check)
        phrases(check)
        play(check)
    }

    /// The two phrase marks (#233): a space between two Japanese characters, and a zero-width space beside a number.
    /// `wrapping` turns each into the only place the phrase may break, and leaves text with neither as it is.
    static func marks(_ check: (Bool, String) -> Void) {
        let j = TomoLineBreaks.join, z = TomoLineBreaks.phraseBreak, wraps = TomoLineBreaks.wrapping
        let spaced = "今日は まだ", sentence = "今日はまだこれから"   // text-ok: a test input
        let numbered = "9語中\u{200B}0語わかる", english = "9 more words to Lv\u{00A0}15"   // text-ok: a test input
        let phrases = [TomoLineBreaks.phrases(spaced), TomoLineBreaks.phrases(numbered)]
        check(TomoLineBreaks.isMarked(spaced) && TomoLineBreaks.isMarked(numbered)
              && wraps(spaced) == "今\(j)日\(j)は\(z)ま\(j)だ"   // text-ok: a test input
              && wraps(numbered) == "9\(j)語\(j)中\(z)0\(j)語\(j)わ\(j)か\(j)る"   // text-ok: a test input
              && phrases == [["今日は", "まだ"], ["9語中", "0語わかる"]]   // text-ok: a test input
              && TomoLineBreaks.spoken(spaced) + TomoLineBreaks.spoken(numbered) == "今日はまだ9語中0語わかる"   // text-ok: a test input
              && !TomoLineBreaks.isMarked(sentence) && wraps(sentence) == sentence
              && !TomoLineBreaks.isMarked(english) && wraps(english) == english,
              "phrase marks: a space between two Japanese characters, and a zero-width space beside a number, each "
              + "wrap only there and never show; a sentence and English with neither stay as they are")
    }

    /// Every word Tomo says, in every target pack, at the word's largest size, fits an SE's Words row, shrunk no more
    /// than `TomoWordFlow` shrinks it: the word grows with the text, and never past the row (#213).
    static func words(_ check: (Bool, String) -> Void) {
        let size = TomoWordsScreen.sayMax, floor = TomoWordFlow.minScale
        // The widest few by count (a Japanese character is about 1 em, a Latin letter about 0.6), then measured.
        var all: [String] = []
        for level in TomoLanguages.shared.targets.flatMap(\.levels) {
            let says: [String] = (level.rounds ?? []).map(\.say) + (level.starters ?? []).map(\.say)
            for say in says { all += say.split(separator: " ").map(String.init) }
        }
        let widest = Set(all).sorted { ems($0) > ems($1) }.prefix(40)
        var worst = (scale: CGFloat(1), word: "")
        for word in widest {
            let scale = min(1, wordColumn / width(word, size: size, weight: .semibold))
            if scale < worst.scale { worst = (scale, word) }
        }
        check(!all.isEmpty && worst.scale >= floor,
              "words: at its largest (\(Int(size)) pt), the widest word in any pack fits an SE's row "
              + String(format: "(%.0f pt) shrunk to %.2f, no less than %.2f", wordColumn, worst.scale, floor)
              + (worst.word.isEmpty ? "" : ": \"\(worst.word)\""))
    }

    /// Each phrase the Tomo screen can say (its lines, the Today line, Growing up's day), in every ui pack, fits its
    /// line on an SE at the largest text: a whole part on one line, shrunk no further than its view lets it (the
    /// hero's lines 0.7, the others 0.75), or else each phrase it marks (`TomoLineBreaks`), or each word of one with no
    /// Japanese in it, as a line breaker would wrap it (#233). Parts joined by the list separator are measured as
    /// `TomoPhrases` draws them, each but the last with the separator on its last word.
    static func phrases(_ check: (Bool, String) -> Void) {
        let callout: CGFloat = 51, body: CGFloat = 53, hero = TomoGrowthScreen.lineScale
        var tooWide: [String] = []
        var count = 0
        func fits(_ parts: [String], size: CGFloat, weight: Font.Weight, icon: Bool, floor: CGFloat = hero) {
            let line = formRow - (icon ? iconEms * size : 0)
            for part in parts {
                count += 1
                let one = TomoLineBreaks.spoken(part)
                if width(one, size: size, weight: weight) * floor <= line { continue }
                // Too wide for a line: a marked part's phrases each take a line, shrinking as a part does; a spaced
                // one wraps at its spaces at full size; Japanese with no marks would break inside a word.
                let marked = TomoLineBreaks.isMarked(part), spaced = !one.contains(where: TomoLineBreaks.isWide)
                let pieces = marked ? TomoLineBreaks.phrases(part) : spaced ? one.split(separator: " ").map(String.init) : [one]
                for piece in pieces {
                    let w = width(piece, size: size, weight: weight)
                    if w * (spaced ? 1 : floor) > line {
                        tooWide.append("\"\(piece)\" (" + String(format: "%.0f pt at %.0f pt in %.0f", w, size, line) + ")")
                    }
                }
            }
        }
        let packs = TomoLanguages.shared.targets
        let separator = { (ui: LearnerPack) in ui("list.separator") }
        let top = packs.map(\.levels.count).max() ?? 1
        let most = packs.flatMap { $0.levels.map { TomoProgress.needed(of: $0.itemIDs.count) } }.max() ?? 10
        let times: [Date?] = [nil, TomoGame.wallDate(hour: 22, minute: 58), TomoGame.wallDate(hour: 22, minute: 58, days: 1)]
        for ui in TomoLanguages.shared.learners {
            for hourCycle in [Locale.HourCycle.oneToTwelve, .zeroToTwentyThree] {
                for n in [0, 1, most] {
                    for (level, last) in [(top - 1, false), (top, true)] {
                        for at in times {
                            let left = TomoProgress.Left(words: n, nextAt: at)
                            fits(TomoPhrases.drawn(TomoGame.whatsLeftParts(left, level: level, last: last, ui,
                                                                           hourCycle: hourCycle), separator: separator(ui)),
                                 size: callout, weight: .medium, icon: true)
                        }
                    }
                }
                for at in times {
                    fits([timeText("rest.back", until: at, ui, hourCycle: hourCycle, marked: true)],
                         size: callout, weight: .regular, icon: true)
                }
            }
            let sep = separator(ui)
            for known in [ui("words.toNext", ["known": "\(most)", "needed": "\(most)", "next": "\(top)"]),
                          ui("words.lastLevel", ["known": "\(most)", "needed": "\(most)"])] {
                fits(TomoPhrases.drawn(known.components(separatedBy: sep), separator: sep),
                     size: callout, weight: .regular, icon: false)
            }
            // Days together, four digits (27 years) on one line or two between its phrases.
            fits([ui("growth.days", ["n": "9999"])], size: callout, weight: .regular, icon: false)
            // Today, in its order: each part but the last ("grew") may have the separator after it.
            fits(TomoPhrases.drawn([ui("today.nothing"), ui.counted("today.answers", 999), ui.counted("today.newWords", 99),
                                    ui("today.streak", ["n": "365"]), ui("today.grew", ["from": "\(top - 1)", "to": "\(top)"])],
                                   separator: sep),
                 size: body, weight: .medium, icon: true, floor: 0.75)
            // Growing up: a mark's level and day (title 3, 55 pt), and sliding back in time (caption, 43 pt), on a
            // long day.
            let long = Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 30)) ?? Date()
            let level = ui("level", ["n": "\(top)"])
            fits(TomoPhrases.drawn([level, TomoHeightPillar.longDay(long, learner: ui.id)], separator: sep),
                 size: 55, weight: .bold, icon: false, floor: 0.75)
            let day = TomoHeightPillar.wholeDay(long, learner: ui.id)
            fits(TomoPhrases.drawn(ui("pillar.slide", ["date": day, "level": level]).components(separatedBy: sep),
                                   separator: sep),
                 size: 43, weight: .regular, icon: false, floor: 0.75)
        }
        check(count > 0 && tooWide.isEmpty,
              "the Tomo screen's \(count) phrases in every ui pack fit their line on an SE at the largest text, so none "
              + "breaks inside a word: \(tooWide.count) too wide"
              + (tooWide.isEmpty ? "" : ": " + Set(tooWide).sorted().prefix(8).joined(separator: ", ")))
    }

    /// "Play with Tomo" (`tomo.play`) in every ui pack, as its button draws it (`TomoGrowthScreen.playTitle`) beside
    /// its icon at each accessibility size (body 28 to 53 pt), on an SE and a 17 Pro: no mark shows, and it takes no
    /// more than its lines, shrunk no further than its button lets it, breaking only where the pack marks a phrase or
    /// has a space. So 「Tomoと / あそぶ」 never reads "Tom / oと" or 「Tomoとあ / そぶ」 (#233).
    static func play(_ check: (Bool, String) -> Void) {
        var wrong: [String] = [], count = 0
        let scales = Array(stride(from: 1, through: TomoGrowthScreen.playScale, by: -0.02))
        for ui in TomoLanguages.shared.learners {
            let text = ui("tomo.play"), drawn = TomoGrowthScreen.playTitle(text)
            let shown = String(drawn.filter { $0 != TomoLineBreaks.join && $0 != TomoLineBreaks.phraseBreak })
            if shown != TomoLineBreaks.spoken(text) { wrong.append("\(ui.id) shows \"\(shown)\"") }
            for phone: CGFloat in [375, 402] {
                for size: CGFloat in [28, 33, 40, 47, 53] {
                    count += 1
                    let width = row(phone) - 2 * playInset - playIconEms * size - playGap
                    let laid = scales.lazy.map { lines(drawn, size: size * $0, weight: 0.3, width: width) }
                    let at = "at \(Int(size)) pt on a \(Int(phone)) pt phone"
                    guard let fit = laid.first(where: { $0.count <= TomoGrowthScreen.playLines }) else {
                        wrong.append("\(ui.id) cut \(at)")
                        continue
                    }
                    let broken = fit.dropLast().filter { $0.last != TomoLineBreaks.phraseBreak && $0.last?.isWhitespace != true }
                    if !broken.isEmpty {
                        wrong.append("\(ui.id) " + fit.map { $0.filter { $0 != TomoLineBreaks.join } }.joined(separator: " / ") + " " + at)
                    }
                }
            }
        }
        check(count > 0 && wrong.isEmpty,
              "Play with Tomo fits its button in every ui pack at every accessibility size (\(count)), breaking only "
              + "between its phrases: " + (wrong.isEmpty ? "none breaks inside one" : wrong.prefix(6).joined(separator: ", ")))
    }

    /// A Form row's text on a phone `phone` pt wide (`formRow` on an SE).
    static func row(_ phone: CGFloat) -> CGFloat { formRow + phone - Self.phone }

    /// The lines `s` takes at `size` pt (`weight`, CoreText's: 0.3 is semibold) in `width`, as CoreText's line breaker
    /// (which SwiftUI's Text uses) wraps it, each with its trailing space or mark.
    static func lines(_ s: String, size: CGFloat, weight: CGFloat, width: CGFloat) -> [String] {
        let base = CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let traits = [kCTFontTraitsAttribute: [kCTFontWeightTrait: weight]] as CFDictionary
        let font = CTFontCreateWithFontDescriptor(CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(base),
                                                                                          traits), size, nil)
        let text = NSAttributedString(string: s, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let typesetter = CTTypesetterCreateWithAttributedString(text)
        let all = s as NSString
        var out: [String] = [], start = 0
        while start < all.length {
            let n = max(1, CTTypesetterSuggestLineBreak(typesetter, start, Double(width)))
            out.append(all.substring(with: NSRange(location: start, length: min(n, all.length - start))))
            start += n
        }
        return out
    }

    /// About how many ems wide `s` is: a Japanese character 1, anything else 0.6.
    static func ems(_ s: String) -> Double { s.reduce(0) { $0 + (TomoLineBreaks.isWide($1) ? 1 : 0.6) } }

    /// How wide `s` is on one line at `size` pt, measured by SwiftUI's own text layout.
    static func width(_ s: String, size: CGFloat, weight: Font.Weight) -> CGFloat {
        let r = ImageRenderer(content: Text(s).font(.system(size: size, weight: weight)).lineLimit(1).fixedSize())
        r.scale = 1
        return r.cgImage.map { CGFloat($0.width) } ?? .infinity
    }
}
