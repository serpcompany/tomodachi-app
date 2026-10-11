import SwiftUI

// MARK: - The iPhone's Tomo and Words screens at the largest text (#213, #233)
//
// What a snapshot can't show for every pack: at the largest Dynamic Type size (accessibility XXXL) on the narrowest
// iPhone (an SE, 375 pt), each word in every target pack fits its row, and each phrase the Tomo screen and the Today
// line can say fits its line, so nothing breaks inside a word. Measured with SwiftUI's own text layout, at the sizes
// iOS gives these text styles there (body 53 pt, callout 51 pt). Run by `swift test` and TOMO_SELFTEST.

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

    public static func selfTest(_ check: (Bool, String) -> Void) {
        words(check)
        phrases(check)
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
    /// Japanese in it, as a line breaker would wrap it (#233).
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
        let top = packs.map(\.levels.count).max() ?? 1
        let most = packs.flatMap { $0.levels.map { TomoProgress.needed(of: $0.itemIDs.count) } }.max() ?? 10
        let times: [Date?] = [nil, TomoGame.wallDate(hour: 22, minute: 58), TomoGame.wallDate(hour: 22, minute: 58, days: 1)]
        for ui in TomoLanguages.shared.learners {
            for hourCycle in [Locale.HourCycle.oneToTwelve, .zeroToTwentyThree] {
                for n in [0, 1, most] {
                    for (level, last) in [(top - 1, false), (top, true)] {
                        for at in times {
                            let left = TomoProgress.Left(words: n, nextAt: at)
                            fits(TomoGame.whatsLeftParts(left, level: level, last: last, ui, hourCycle: hourCycle),
                                 size: callout, weight: .medium, icon: true)
                        }
                    }
                }
                for at in times {
                    fits([timeText("rest.back", until: at, ui, hourCycle: hourCycle, marked: true)],
                         size: callout, weight: .regular, icon: true)
                }
            }
            let sep = ui("list.separator")
            for known in [ui("words.toNext", ["known": "\(most)", "needed": "\(most)", "next": "\(top)"]),
                          ui("words.lastLevel", ["known": "\(most)", "needed": "\(most)"])] {
                fits(known.components(separatedBy: sep), size: callout, weight: .regular, icon: false)
            }
            fits([ui.counted("today.answers", 999), ui.counted("today.newWords", 99), ui("today.streak", ["n": "365"]),
                  ui("today.grew", ["from": "\(top - 1)", "to": "\(top)"]), ui("today.nothing")],
                 size: body, weight: .medium, icon: true, floor: 0.75)
            // Growing up: a mark's level and day (title 3, 55 pt), and sliding back in time (caption, 43 pt), on a
            // long day.
            let long = Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 30)) ?? Date()
            let level = ui("level", ["n": "\(top)"])
            fits([level, TomoHeightPillar.longDay(long, learner: ui.id)], size: 55, weight: .bold, icon: false, floor: 0.75)
            let day = TomoHeightPillar.wholeDay(long, learner: ui.id)
            fits(ui("pillar.slide", ["date": day, "level": level]).components(separatedBy: sep),
                 size: 43, weight: .regular, icon: false, floor: 0.75)
        }
        check(count > 0 && tooWide.isEmpty,
              "the Tomo screen's \(count) phrases in every ui pack fit their line on an SE at the largest text, so none "
              + "breaks inside a word: \(tooWide.count) too wide"
              + (tooWide.isEmpty ? "" : ": " + Set(tooWide).sorted().prefix(8).joined(separator: ", ")))
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
