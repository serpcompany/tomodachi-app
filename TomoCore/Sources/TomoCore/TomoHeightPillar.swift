import SwiftUI

// MARK: - Growing up, as a height pillar (#137 item 2, Stats Take Two's direction 3)
//
// The way a Japanese family marks a child's height on a wooden pillar (柱のきず), Tomo gets a mark for every level it
// grows, with the day, and a big one at each birthday; Tomo stands beside it at its age's form and size. Levels shows
// the current age, from its birthday to the next one, dashed, with Tomo's next form asleep beside it; Every age shows
// the whole way, a mark per birthday, and the ages and what each brings. Slide back in time and Tomo shrinks to how
// big it was that day, and the marks after it fade. Tap a mark for its day and the words of that level. The marks come
// from TomoStats (the growth log) for the Tomo passed in, with its look and material, so a friend has its own pillar.
// Under Reduce Motion Tomo still breathes and blinks; nothing else moves. Test runs: TOMO_PILLAR=levels|ages picks the
// scale, TOMO_PILLAR_BACK=<0…1> slides back that share of the way, TOMO_PILLAR_MARK=<level> selects a mark.

public struct TomoHeightPillar: View {
    private let progress: TomoProgress
    private let look: TomoLook
    private let material: TomoMaterial
    private let version: Int
    @ObservedObject private var lang = TomoLanguages.shared
    @Environment(\.colorScheme) private var scheme

    /// `progress`, `look` and `material`: the Tomo whose pillar it is (the learner's own: its progress, its look and
    /// `.own`). `version`: bump it when the progress changes.
    public init(progress: TomoProgress, look: TomoLook, material: TomoMaterial, version: Int) {
        self.progress = progress
        self.look = look
        self.material = material
        self.version = version
    }

    enum Scale: String { case levels, ages }

    @State private var scale: Scale =
        ProcessInfo.processInfo.environment["TOMO_PILLAR"].flatMap(Scale.init(rawValue:)) ?? .levels
    @State private var selected: Int? = ProcessInfo.processInfo.environment["TOMO_PILLAR_MARK"].flatMap(Int.init)
    @State private var back: Double? = ProcessInfo.processInfo.environment["TOMO_PILLAR_BACK"].flatMap(Double.init)

    private var phone: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    public var body: some View {
        let stats = TomoStats(progress), marks = stats.marks(), next = stats.nextBirthday
        let fresh = marks.count == 1
        let day = when(marks)
        let dayLevel = day.map { stats.level(at: $0) } ?? progress.level
        VStack(alignment: .leading, spacing: 12) {
            let head = phone ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                             : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
            head {
                Text(lang.learner("pillar.note")).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !phone { Spacer(minLength: 0) }
                Picker(lang.learner("growth.growingUp"), selection: $scale) {
                    Text(lang.learner("pillar.levels")).tag(Scale.levels)
                    Text(lang.learner("pillar.ages")).tag(Scale.ages)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                .onChange(of: scale) { _, _ in selected = nil }
            }
            let layout = phone ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
                               : AnyLayout(HStackLayout(alignment: .top, spacing: 20))
            layout {
                VStack(alignment: .leading, spacing: 10) {
                    pillar(stats: stats, marks: marks, next: next, day: day, dayLevel: dayLevel)
                        .frame(width: phone ? nil : 300, height: phone ? 360 : 400)
                        .frame(maxWidth: phone ? .infinity : nil, alignment: .leading)
                    if scale == .levels, !fresh { slider(marks: marks, day: day, level: dayLevel) }
                }
                detail(stats: stats, marks: marks, next: next, fresh: fresh, current: dayLevel)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 6)
        .id(version)
    }

    // MARK: The pillar

    /// Where the marks go, as a share of the pillar's height from the bottom (0.04 … 0.92), by level.
    /// Levels: this age's marks, from its birthday up, evenly spaced (at most `cap`: its birthday and the newest ones),
    /// with the next birthday a step above. Every age: a band per age, its birthday at the band's foot, and Tomo's level
    /// within its age's band.
    struct Plan {
        var shown: [Int] = []
        var ahead: [Int] = []
        var at: [Int: CGFloat] = [:]
        /// A gap in the marks shown (levels left out between the birthday and the newest), just above this level.
        var gapAbove: Int?
    }

    private func layout(_ marks: [TomoStats.Mark], next: (age: Int, level: Int)?) -> Plan {
        var out = Plan()
        if scale == .ages {
            let spans = progress.ageSpans, k = CGFloat(max(spans.count, 1))
            for (i, span) in spans.enumerated() {
                let foot = 0.04 + 0.88 * CGFloat(i) / k
                if span.from <= progress.level {
                    out.shown.append(span.from)
                    out.at[span.from] = foot
                    if span.from < progress.level, progress.level <= span.to {
                        out.shown.append(progress.level)
                        // Within its age's band, kept clear of the birthdays above and below it.
                        let share = CGFloat(progress.level - span.from) / CGFloat(max(span.to - span.from, 1))
                        out.at[progress.level] = foot + 0.88 / k * (0.35 + 0.3 * share)
                    }
                } else {
                    out.ahead.append(span.from)
                    out.at[span.from] = foot
                }
            }
            return out
        }
        let cap = phone ? 11 : 14
        let ageStart = progress.ageSpans.first { $0.from <= progress.level && progress.level <= $0.to }?.from ?? 1
        var levels = Array(ageStart...max(progress.level, ageStart))
        if levels.count > cap {
            out.gapAbove = levels[0]
            levels = [levels[0]] + levels.suffix(cap - 1)
        }
        out.shown = levels
        let slots = CGFloat(levels.count - 1 + (next == nil ? 0 : 2))
        for (i, level) in levels.enumerated() { out.at[level] = 0.04 + 0.88 * CGFloat(i) / max(slots, 1) }
        if let next {
            out.ahead = [next.level]
            out.at[next.level] = 0.92
        }
        return out
    }

    private func pillar(stats: TomoStats, marks: [TomoStats.Mark], next: (age: Int, level: Int)?, day: Date?,
                        dayLevel: Int) -> some View {
        let dark = scheme == .dark, plan = layout(marks, next: next)
        let woodA = Color(hex: dark ? "#7A5A3C" : "#E2C196"), woodB = Color(hex: dark ? "#654A31" : "#CFA273")
        let grain = Color(hex: dark ? "#523B26" : "#B88B5C"), scratch = Color(hex: dark ? "#F5E1C4" : "#5C3B1E")
        let shown = marks.filter { plan.shown.contains($0.level) }
        let ahead: [(age: Int, level: Int)] = plan.ahead.map { (stats.age(onLevel: $0), $0) }
        return GeometryReader { geo in
            let H = geo.size.height, postX: CGFloat = phone ? 96 : 104, postW: CGFloat = phone ? 60 : 72
            let y: (Int) -> CGFloat = { level in H * (1 - (plan.at[level] ?? 0.04)) }
            ZStack(alignment: .topLeading) {
                // The post: wood with its grain, shaded at the sides.
                Canvas { ctx, size in
                    let rect = CGRect(x: postX, y: 0, width: postW, height: size.height)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 4),
                             with: .linearGradient(Gradient(stops: [.init(color: woodB, location: 0), .init(color: woodA, location: 0.35),
                                                                    .init(color: woodA, location: 0.6), .init(color: woodB, location: 1)]),
                                                   startPoint: CGPoint(x: rect.minX, y: 0), endPoint: CGPoint(x: rect.maxX, y: 0)))
                    var x = rect.minX + 9
                    while x < rect.maxX - 4 {
                        ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(grain.opacity(0.3)))
                        x += 14
                    }
                }
                ForEach(ahead, id: \.level) { a in
                    aheadMark(age: a.age, level: a.level, y: y(a.level), postX: postX, postW: postW)
                }
                if let gap = plan.gapAbove, let next = plan.shown.dropFirst().first {
                    // Levels left out between this age's birthday and the newest marks: a little break in the wood.
                    Image(systemName: "ellipsis").rotationEffect(.degrees(90)).font(.system(size: 13, weight: .bold))
                        .foregroundStyle(scratch.opacity(0.7))
                        .position(x: postX + postW / 2, y: (y(gap) + y(next)) / 2)
                        .accessibilityHidden(true)
                }
                ForEach(shown) { m in
                    mark(m, current: dayLevel, y: y(m.level), postX: postX, postW: postW, scratch: scratch,
                         faded: day.map { t in (m.at ?? .distantPast) > t } ?? false)
                }
                if scale == .levels, let next {
                    TomoPillarTomo(look: look, material: material, growth: CGFloat(min(next.age - 1, TomoLook.ages - 1)),
                                   asleep: true)
                        .frame(width: 54, height: 54)
                        .opacity(0.4)
                        .position(x: postX - 34, y: max(y(next.level) - 18, 28))
                        .accessibilityHidden(true)
                }
                tomo(stats: stats, dayLevel: dayLevel)
                    .position(x: postX / 2 - 2, y: H - tomoSize(dayLevel) / 2 - 2)
            }
        }
    }

    /// Tomo beside the pillar, at its form and size on the day the slider is at.
    private func tomo(stats: TomoStats, dayLevel: Int) -> some View {
        let age = stats.age(onLevel: dayLevel)
        return TomoPillarTomo(look: look, material: material, growth: CGFloat(min(max(age - 1, 0), TomoLook.ages - 1)),
                              asleep: false)
            .frame(width: tomoSize(dayLevel), height: tomoSize(dayLevel))
            .id(age)
            .animation(.easeInOut(duration: 0.3), value: dayLevel)
            .accessibilityHidden(true)
    }

    /// How big Tomo stands: bigger through each age, and it starts small again in a new form at a birthday.
    private func tomoSize(_ level: Int) -> CGFloat {
        let span = progress.ageSpans.first { $0.from <= level && level <= $0.to }
        let share = span.map { CGFloat(level - $0.from) / CGFloat(max($0.to - $0.from, 1)) } ?? 1
        return (phone ? 84 : 96) * (0.62 + 0.38 * share)
    }

    private func mark(_ m: TomoStats.Mark, current: Int, y: CGFloat, postX: CGFloat, postW: CGFloat, scratch: Color, faded: Bool) -> some View {
        let isSelected = (selected ?? current) == m.level
        let big = m.birthday
        let tilt = Double((m.level * 53) % 7 - 3) * 0.8
        return Button {
            selected = m.level
        } label: {
            HStack(spacing: 6) {
                Rectangle().fill(scratch)
                    .frame(width: postW - 10, height: big ? 4 : 2.5)
                    .clipShape(Capsule())
                    .rotationEffect(.degrees(tilt))
                    .padding(.leading, 5)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(markLabel(m)).font(.system(size: big ? 14 : 12.5, weight: .semibold, design: .rounded))
                    if let at = m.at, scale == .levels || m.level == progress.level {
                        Text(m.level == progress.level && scale == .ages ? lang.learner("pillar.now") : numericDay(at))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                    }
                }
                .padding(.horizontal, isSelected ? 6 : 0).padding(.vertical, isSelected ? 2 : 0)
                .foregroundStyle(isSelected ? AnyShapeStyle(.background) : AnyShapeStyle(.primary))
                .background(isSelected ? Color.primary : .clear, in: RoundedRectangle(cornerRadius: 6))
            }
            .frame(height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(faded ? 0.12 : 1)
        .animation(.easeInOut(duration: 0.25), value: faded)
        .fixedSize()
        .offset(x: postX, y: y - 10)
        .accessibilityLabel(markAccessibility(m))
    }

    /// A mark ahead: the next birthday (or, for Every age, every age to come), dashed, not reached yet.
    private func aheadMark(age: Int, level: Int, y: CGFloat, postX: CGFloat, postW: CGFloat) -> some View {
        Button {
            selected = -level
        } label: {
            HStack(spacing: 6) {
                Path { $0.move(to: .zero); $0.addLine(to: CGPoint(x: postW - 10, y: 0)) }
                    .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: postW - 10, height: 2)
                    .padding(.leading, 5)
                Text(lang.target.ageLabel(age)).font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(lang.learner("level", ["n": "\(level)"])).font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(selected == -level ? 1 : 0.75)
        .fixedSize()
        .offset(x: postX, y: y - 10)
        .accessibilityLabel("\(lang.target.ageLabel(age)), \(lang.learner("level", ["n": "\(level)"]))")
    }

    private func markLabel(_ m: TomoStats.Mark) -> String {
        if m.level == 1 { return lang.learner("pillar.hatched") }
        if m.birthday { return "\(lang.target.ageLabel(m.age)) \(lang.learner("level", ["n": "\(m.level)"]))" }
        return lang.learner("level", ["n": "\(m.level)"])
    }

    private func markAccessibility(_ m: TomoStats.Mark) -> String {
        [markLabel(m), m.at.map(longDay) ?? lang.learner("pillar.elsewhere")].joined(separator: ", ")
    }

    // MARK: Sliding back in time

    /// The day the slider is at (nil: now), between the hatch and now.
    private func when(_ marks: [TomoStats.Mark]) -> Date? {
        guard let back, back > 0.001 else { return nil }
        let start = progress.metAt, now = TomoClock.now
        return now.addingTimeInterval(-back * now.timeIntervalSince(start))
    }

    private func slider(marks: [TomoStats.Mark], day: Date?, level: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(lang.learner("pillar.slide", ["date": longDay(day ?? TomoClock.now), "level": lang.learner("level", ["n": "\(level)"])]))
                .font(.caption).foregroundStyle(.secondary)
            // The light wood's edge in light mode, a brighter wood in dark; its knob shows at the track's end (#195).
            TomoSlider(value: Binding(get: { 1 - (back ?? 0) }, set: { back = $0 >= 0.999 ? nil : 1 - $0 }),
                       tint: Color(hex: scheme == .dark ? "#D9B07F" : "#CFA273"))
                .accessibilityLabel(lang.learner("pillar.slideLabel"))
                .accessibilityValue(longDay(day ?? TomoClock.now))
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: phone ? .infinity : 300, alignment: .leading)
    }

    // MARK: What a mark says

    @ViewBuilder
    private func detail(stats: TomoStats, marks: [TomoStats.Mark], next: (age: Int, level: Int)?, fresh: Bool,
                        current: Int) -> some View {
        if scale == .ages {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(progress.ageSpans, id: \.age) { ageRow($0) }
            }
        } else if fresh {
            VStack(alignment: .leading, spacing: 6) {
                Text(lang.learner("pillar.justHatched")).font(.title3.weight(.bold))
                Text(lang.learner("pillar.empty")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        } else if let s = selected, s < 0, let next {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(lang.target.ageLabel(next.age)) · \(lang.learner("level", ["n": "\(next.level)"]))").font(.title3.weight(.bold))
                Text(lang.learner("pillar.ahead", ["age": lang.target.ageLabel(next.age), "n": "\(next.level)"]))
                    .font(.callout).foregroundStyle(.secondary)
                Text(lang.learner("growth.age.\(min(next.age, 6))")).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if let m = marks.first(where: { $0.level == (selected ?? current) }) ?? marks.last {
            markDetail(m)
        }
    }

    private func markDetail(_ m: TomoStats.Mark) -> some View {
        let words = (progress.pack.levels.indices.contains(m.level - 1) ? progress.pack.levels[m.level - 1].itemIDs : [])
            .filter { progress.items[$0] != nil }
        return VStack(alignment: .leading, spacing: 8) {
            Text([markLabel(m), m.at.map(longDay)].compactMap { $0 }.joined(separator: " · ")).font(.title3.weight(.bold))
            Group {
                if m.level == 1 {
                    Text(lang.learner("pillar.hatchedOn"))
                } else if m.at == nil {
                    Text(lang.learner("pillar.elsewhere"))
                } else if m.birthday {
                    Text(lang.learner("pillar.birthday", ["age": lang.target.ageLabel(m.age), "n": "\(m.level)",
                                                          "day": "\(progress.daysTogether(at: m.at!))"]))
                    + Text(" ") + Text(lang.learner("growth.age.\(min(m.age, 6))"))
                } else {
                    Text(lang.learner("pillar.grewTo", ["n": "\(m.level)", "day": "\(progress.daysTogether(at: m.at!))"]))
                }
            }
            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(lang.learner(words.isEmpty ? "pillar.noWords" : "pillar.words", ["n": "\(m.level)"]))
                .font(.caption).foregroundStyle(.secondary)
            TomoChipFlow(spacing: 6) {
                ForEach(words, id: \.self) { id in wordChip(id) }
            }
        }
    }

    private func wordChip(_ id: String) -> some View {
        let w = progress.word(id, learner: lang.learner.id), item = progress.items[id]
        let stage = item?.stage ?? 0, group = TomoPlantDrawing.group(max(stage, 1)), pale = (item?.peak ?? 0) > stage
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if let emoji = w.emoji { TomoPictureView(emoji, size: 13.5) }   // a dark one on a light disc in dark mode
                Text(w.say).font(.system(size: 13.5, weight: .bold, design: .rounded))
            }
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { k in
                    Circle().fill(k <= group ? Color.teal.opacity(pale && k == group ? 0.35 : 1) : Color.secondary.opacity(0.25))
                        .frame(width: 5, height: 5)
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 9).stroke(Color.secondary.opacity(0.3)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(w.say), \(lang.learner("stage.\(TomoSRS.group(stage))"))")
    }

    /// Each age, its levels and what it brings (grown / now / later): Every age's list.
    private func ageRow(_ a: TomoProgress.AgeSpan) -> some View {
        let now = progress.age
        let state = a.age < now ? "grown" : a.age == now ? "now" : "later"
        let levels = a.from == a.to ? lang.learner("level", ["n": "\(a.from)"])
            : lang.learner("growth.levels", ["from": "\(a.from)", "to": "\(a.to)"])
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: state == "grown" ? "checkmark.circle.fill" : state == "now" ? "location.circle.fill" : "lock.circle")
                .font(.system(size: 16))
                .foregroundStyle(state == "grown" ? Color.teal : state == "now" ? Color.orange : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(lang.target.ageLabel(a.age)).font(.headline)
                    Text(levels).font(.caption).foregroundStyle(.secondary)
                }
                Text(lang.learner("growth.age.\(min(a.age, 6))")).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(lang.learner("growth.state.\(state)")).font(.caption).foregroundStyle(.secondary)
        }
        .opacity(state == "later" ? 0.65 : 1)
    }

    // MARK: Days

    private func longDay(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: lang.learner.id)
        f.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return f.string(from: d)
    }

    private func numericDay(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: lang.learner.id)
        f.setLocalizedDateFormatFromTemplate("Md")
        return f.string(from: d)
    }
}

/// Tomo by the pillar: alive, at a form; asleep for the next form, waiting at the next birthday.
private struct TomoPillarTomo: View {
    @StateObject private var blob: TomoBlob
    private let growth: CGFloat
    private let asleep: Bool

    init(look: TomoLook, material: TomoMaterial, growth: CGFloat, asleep: Bool) {
        self.growth = growth
        self.asleep = asleep
        _blob = StateObject(wrappedValue: TomoBlob(look: look, material: material, motion: .shared))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
            Canvas { ctx, size in
                blob.frameDate = tl.date
                blob.step()
                blob.draw(ctx, size: size)
            }
        }
        .onAppear {
            blob.setGrowth(growth)
            blob.setState(asleep ? .sleeping : .idle, force: true)
        }
    }
}

/// Chips that wrap onto the next line, whole.
struct TomoChipFlow: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal.width ?? .infinity, subviews)
        return CGSize(width: rows.map { $0.width }.max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(bounds.width, subviews) {
            for (i, x) in row.items { subviews[i].place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + row.y), proposal: .unspecified) }
        }
    }

    private struct Row { var y: CGFloat; var width: CGFloat = 0; var height: CGFloat = 0; var items: [(Int, CGFloat)] = [] }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows = [Row(y: 0)]
        for (i, v) in subviews.enumerated() {
            let size = v.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].items.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            let x = row.items.isEmpty ? 0 : row.width + spacing
            row.items.append((i, x))
            row.width = x + size.width
            row.height = max(row.height, size.height)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
