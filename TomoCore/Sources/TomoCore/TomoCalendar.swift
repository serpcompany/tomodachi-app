import Foundation

// MARK: - The target language's calendar
//
// Days of the year that bring something, as data in the target language's pack (`calendar`), so a Japanese speaker
// learning English gets that language's year: the season's weather in Tomo's card (桜 petals in spring, snow in
// winter; #137), and the day's dance when music plays (盆踊り during お盆; #130). Each entry is a yearly range of days, which may run across New Year (`from` later than `until`), or,
// for a day that moves (節分 follows 立春), a table of that year's days (`years`). Holiday outfits (#130) can add their
// entries here and read them the same way (`entries(on:)`).

/// Light weather drawn around Tomo in its card: a few falling flakes or petals.
public enum TomoWeather: String, Codable, Sendable, CaseIterable {
    case snow, petals
}

/// How Tomo dances while music plays (#130): its own bounce and sway, or, on the days the calendar says, the 盆踊り
/// side-step.
public enum TomoDance: String, Codable, Sendable, CaseIterable {
    case bounce, bonOdori
}

public struct TomoCalendar: Codable, Sendable {
    /// A day of the year, "MM-DD" in the pack.
    public struct Day: Codable, Sendable, Comparable {
        public let month: Int, day: Int

        public init(month: Int, day: Int) { self.month = month; self.day = day }

        public init(from decoder: Decoder) throws {
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let d = Day(text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not MM-DD: \(text)"))
            }
            self = d
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            try c.encode(String(format: "%02d-%02d", month, day))
        }

        init?(_ text: String) {
            let parts = text.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 2, (1...12).contains(parts[0]), (1...31).contains(parts[1]) else { return nil }
            month = parts[0]; day = parts[1]
        }

        public static func < (a: Day, b: Day) -> Bool { (a.month, a.day) < (b.month, b.day) }
    }

    /// Days from `from` to `until`, both included. `until` before `from`: the range runs across New Year.
    public struct Span: Codable, Sendable {
        public let from: Day
        public let until: Day

        public init(from: Day, until: Day) { self.from = from; self.until = until }

        public func contains(_ d: Day) -> Bool {
            from <= until ? (from <= d && d <= until) : (d >= from || d <= until)
        }
    }

    public struct Entry: Codable, Sendable {
        /// What it is: "sakura", "snow" (later "setsubun", "tanabata"…).
        public let id: String
        /// Every year, these days…
        public let from: Day?
        public let until: Day?
        /// …or, for a day that moves, that year's days, by year ("2026": {"from": "02-03", "until": "02-03"}). A year in
        /// the table wins over `from` and `until`; a year not in it uses them, or has none.
        public let years: [String: Span]?
        /// The weather it brings to Tomo's card.
        public let weather: TomoWeather?
        /// How Tomo dances to music on its days.
        public let dance: TomoDance?

        public init(id: String, from: Day? = nil, until: Day? = nil, years: [String: Span]? = nil,
                    weather: TomoWeather? = nil, dance: TomoDance? = nil) {
            self.id = id; self.from = from; self.until = until; self.years = years; self.weather = weather
            self.dance = dance
        }

        /// Whether `day` of `year` is one of its days.
        public func contains(_ day: Day, year: Int) -> Bool {
            if let span = years?[String(year)] { return span.contains(day) }
            guard let from, let until else { return false }
            return Span(from: from, until: until).contains(day)
        }
    }

    public let entries: [Entry]

    public init(_ entries: [Entry]) { self.entries = entries }

    public init(from decoder: Decoder) throws { entries = try decoder.singleValueContainer().decode([Entry].self) }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(entries)
    }

    /// The entries `date` falls in, in the pack's order, on the learner's own calendar.
    public func entries(on date: Date, calendar: Calendar = .current) -> [Entry] {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = c.year, let month = c.month, let d = c.day else { return [] }
        let day = Day(month: month, day: d)
        return entries.filter { $0.contains(day, year: year) }
    }

    /// The weather on `date`: the first entry that day that brings some.
    public func weather(on date: Date, calendar: Calendar = .current) -> TomoWeather? {
        entries(on: date, calendar: calendar).lazy.compactMap(\.weather).first
    }

    /// The dance on `date`: the first entry that day that has one (none: Tomo's own bounce).
    public func dance(on date: Date, calendar: Calendar = .current) -> TomoDance? {
        entries(on: date, calendar: calendar).lazy.compactMap(\.dance).first
    }

    /// The day the calendar reads: TOMO_DATE=YYYY-MM-DD (noon that day, for snapshots), else today on Tomo's clock.
    @MainActor public static var today: Date {
        if let text = ProcessInfo.processInfo.environment["TOMO_DATE"] {
            let parts = text.split(separator: "-").compactMap { Int($0) }
            if parts.count == 3,
               let d = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) {
                return d
            }
        }
        return TomoClock.now
    }

    /// Today's weather in the current target language's year (none if its pack has no calendar).
    @MainActor public static var weatherToday: TomoWeather? {
        TomoLanguages.shared.target.calendar?.weather(on: today)
    }

    /// How Tomo dances to music today in the current target language's year: the day's dance, else its own bounce.
    @MainActor public static var danceToday: TomoDance {
        TomoLanguages.shared.target.calendar?.dance(on: today) ?? .bounce
    }
}

// MARK: - Checks (TOMO_SELFTEST)

extension TomoCalendar {
    /// The calendar's rules: a range within the year, a range across New Year (both ends, either side of it, and the
    /// days just outside), a moving day from its year table (and a year missing from it), the first entry's weather, and
    /// the packs' own calendars (each decodes, and the Japanese one has snow at New Year and petals in early April).
    @MainActor static func selfTest(_ check: (Bool, String) -> Void) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        func on(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }
        func day(_ s: String) -> Day { Day(s)! }
        let test = TomoCalendar([
            Entry(id: "spring", from: day("03-20"), until: day("04-15"), weather: .petals),
            Entry(id: "winter", from: day("12-15"), until: day("02-28"), weather: .snow),
            Entry(id: "moving", years: ["2025": Span(from: day("02-02"), until: day("02-02")),
                                        "2026": Span(from: day("02-03"), until: day("02-03"))]),
        ])
        let ids = { (d: Date) in test.entries(on: d, calendar: cal).map(\.id) }
        check(ids(on(2026, 3, 20)) == ["spring"] && ids(on(2026, 4, 15)) == ["spring"] && ids(on(2026, 3, 19)).isEmpty
              && ids(on(2026, 4, 16)).isEmpty && test.weather(on: on(2026, 4, 1), calendar: cal) == .petals,
              "a calendar range within the year includes both its ends and nothing outside them")
        check(ids(on(2026, 12, 15)) == ["winter"] && ids(on(2026, 12, 31)) == ["winter"] && ids(on(2027, 1, 1)) == ["winter"]
              && ids(on(2027, 2, 28)) == ["winter"] && ids(on(2026, 12, 14)).isEmpty && ids(on(2027, 3, 1)).isEmpty
              && ids(on(2028, 2, 29)).isEmpty && test.weather(on: on(2027, 1, 1), calendar: cal) == .snow,
              "a range across New Year wraps the year: Dec 15 to Feb 28, both years, and not Dec 14, Feb 29 or Mar 1")
        check(ids(on(2025, 2, 2)) == ["winter", "moving"] && ids(on(2026, 2, 3)) == ["winter", "moving"]
              && !ids(on(2026, 2, 2)).contains("moving") && !ids(on(2027, 2, 3)).contains("moving")
              && test.weather(on: on(2026, 2, 3), calendar: cal) == .snow,
              "a day that moves comes from its year table (Feb 2 in 2025, Feb 3 in 2026, none for a year not in it)")
        let packs = TomoLanguages.shared.targets
        let ja = packs.first { $0.id == "ja" }?.calendar
        check(packs.allSatisfy { ($0.calendar?.entries ?? []).allSatisfy { $0.from != nil && $0.until != nil || $0.years != nil } }
              && ja?.weather(on: on(2027, 1, 1), calendar: cal) == .snow && ja?.weather(on: on(2026, 4, 2), calendar: cal) == .petals
              && ja?.weather(on: on(2026, 7, 7), calendar: cal) == nil,
              "the packs' calendars decode; Japanese: snow at New Year, petals in early April, nothing in July")
        let en = packs.first { $0.id == "en" }?.calendar
        check(ja?.dance(on: on(2026, 8, 13), calendar: cal) == .bonOdori && ja?.dance(on: on(2026, 8, 16), calendar: cal) == .bonOdori
              && ja?.dance(on: on(2026, 8, 12), calendar: cal) == nil && ja?.dance(on: on(2026, 8, 17), calendar: cal) == nil
              && en?.dance(on: on(2026, 8, 14), calendar: cal) == nil,
              "Japanese: the bon odori during Obon (Aug 13 to 16, not the days either side); English has no Obon")
    }
}
