import SwiftUI

// MARK: - Tomo's diary, drawn (TomoDiary.swift has what it says)
//
// A book: on the Mac, the list of pages on the left and the page on the right; on the iPhone, the page with arrows to
// the days before and after, and the list under it. A page is ruled paper with the date and "Day 17 together", Tomo
// alive in a circle at that day's form (leaping on a day it grew, sulking first after days apart), its words and what
// they mean, the day's new words as stickers (tap one for its card), and what you did. In the list, days apart show as
// a dashed line between pages. A brand-new Tomo's diary is a first page with ばあ！ and what the diary will be. It takes
// the Tomo's progress, look and material, so a friend could keep its own. Test runs: TOMO_DIARY=<n> opens the page n
// days played before the newest; TOMO_DIARY_WORD=first shows its first sticker's card.

struct TomoDiarySection: View {
    let progress: TomoProgress
    let look: TomoLook
    let material: TomoMaterial
    let pages: [TomoDiaryPage]
    let copy: ((String) -> Void)?
    @ObservedObject private var lang = TomoLanguages.shared
    @State private var selected: Date?
    @State private var word: String?
    @State private var showAll = false
    @State private var copied = false
    @State private var opened = false

    private var phone: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    private var shown: TomoDiaryPage? { pages.first { $0.day == selected } ?? pages.last }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(lang.learner("diary.title")).font(.title3.weight(.bold))
                    Text(lang.learner("diary.note")).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let copy, let page = shown {
                    Spacer(minLength: 0)
                    Button {
                        copy(TomoStats(progress).diaryText(page, lang.learner))
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                    } label: {
                        Label(lang.learner(copied ? "garden.copied" : "diary.copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .labelStyle(AdaptiveLabel(iconOnly: phone))
                    .controlSize(phone ? .large : .regular)
                }
            }
            if pages.isEmpty {
                TomoDiaryFirstPage(progress: progress, look: look, material: material)
            } else if phone {
                if let page = shown {
                    nav(page)
                    TomoDiaryPageView(page: page, progress: progress, look: look, material: material, word: $word)
                }
                list(limit: showAll ? nil : 6)
            } else if let page = shown {
                // A book open on the table: the list of pages on the left, the page on the right, the same height.
                HStack(alignment: .top, spacing: 0) {
                    ScrollView { list(limit: nil).padding(12) }
                        .frame(width: 250)
                        .background(TomoPaper(margin: false))
                    Rectangle().fill(.black.opacity(0.12)).frame(width: 1)
                    ScrollView {
                        TomoDiaryPageView(page: page, progress: progress, look: look, material: material, word: $word)
                    }
                    .background(TomoPaper(margin: false))
                    .frame(maxWidth: .infinity)
                }
                .frame(height: 420)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.1)))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            }
        }
        .task(id: pages.count) {
            // Test runs: open a page, once the pages are read.
            let env = ProcessInfo.processInfo.environment
            guard !opened, let back = env["TOMO_DIARY"].flatMap(Int.init), pages.count > back else { return }
            opened = true
            selected = pages[pages.count - 1 - back].day
            if env["TOMO_DIARY_WORD"] == "first" { word = shown?.stickers.first }
        }
    }

    /// The iPhone's arrows: the day played before, the date, the day after.
    private func nav(_ page: TomoDiaryPage) -> some View {
        let i = pages.firstIndex(of: page) ?? pages.count - 1
        return HStack {
            Button { select(pages[max(i - 1, 0)]) } label: { Image(systemName: "chevron.left") }
                .disabled(i == 0)
                .accessibilityLabel(lang.learner("diary.earlier"))
            Spacer()
            Text(TomoStats.longDay(page.day, lang.learner)).font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button { select(pages[min(i + 1, pages.count - 1)]) } label: { Image(systemName: "chevron.right") }
                .disabled(i == pages.count - 1)
                .accessibilityLabel(lang.learner("diary.later"))
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
    }

    private func select(_ page: TomoDiaryPage) {
        selected = page.day
        word = nil
    }

    /// Every page, newest first, with the days apart between them.
    private func list(limit: Int?) -> some View {
        let newest = Array(pages.reversed()), rows = limit.map { Array(newest.prefix($0)) } ?? newest
        return VStack(alignment: .leading, spacing: 2) {
            Text(lang.learner("diary.pages").uppercased())
                .font(.system(size: 10.5, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                .padding(.bottom, 4)
            ForEach(rows) { page in
                Button { select(page) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(shortDay(page.day)).font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary).frame(width: 58, alignment: .leading)
                        Text(page.headline).font(.system(size: 14.5, weight: .semibold, design: .rounded)).lineLimit(1)
                        if page.summary.grew {
                            Text(page.birthday ? lang.target.ageLabel(page.age) : lang.learner("level", ["n": "\(page.summary.levelTo)"]))
                                .font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .background(page.day == shown?.day ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(TomoStats.longDay(page.day, lang.learner)), \(page.headline)")
                if page.apart > 0 {
                    HStack(spacing: 6) {
                        Rectangle().fill(.clear).frame(width: 58, height: 1)
                        Text(lang.learner.counted("diary.apart", page.apart)).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .overlay(alignment: .leading) {
                        Line().stroke(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .frame(width: 40, height: 1).padding(.leading, 10)
                    }
                }
            }
            if phone, limit != nil, pages.count > (limit ?? 0) {
                Button(lang.learner("diary.showAll")) { showAll = true }.font(.callout).padding(.top, 4)
            }
        }
    }

    private func shortDay(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: lang.learner.id)
        f.setLocalizedDateFormatFromTemplate("EEEd")
        return f.string(from: d)
    }

    private struct Line: Shape {
        func path(in r: CGRect) -> Path { Path { $0.move(to: CGPoint(x: r.minX, y: r.midY)); $0.addLine(to: CGPoint(x: r.maxX, y: r.midY)) } }
    }

    private struct AdaptiveLabel: LabelStyle {
        let iconOnly: Bool
        func makeBody(configuration: Configuration) -> some View {
            if iconOnly { configuration.icon } else { HStack(spacing: 6) { configuration.icon; configuration.title } }
        }
    }
}

/// Ruled paper, with a margin line: the diary's pages.
struct TomoPaper: View {
    var margin = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: dark ? "#22252E" : "#FCFCFE")))
            var y: CGFloat = 34
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                         with: .color(Color(hex: dark ? "#2F3749" : "#DCE4F3").opacity(0.6)))
                y += 28
            }
            if margin {
                ctx.fill(Path(CGRect(x: 30, y: 0, width: 1, height: size.height)), with: .color(Color(hex: dark ? "#3A4766" : "#C8D6F0")))
            }
        }
    }
}

/// One page of the diary.
struct TomoDiaryPageView: View {
    let page: TomoDiaryPage
    let progress: TomoProgress
    let look: TomoLook
    let material: TomoMaterial
    @Binding var word: String?
    @ObservedObject private var lang = TomoLanguages.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let ink = Color(hex: scheme == .dark ? "#E2E5EE" : "#363B4E")
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(TomoStats.longDay(page.day, lang.learner)).font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                Text(lang.learner("words.days", ["n": "\(page.dayNumber)"]))
                    .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
            }
            HStack(alignment: .center, spacing: 12) {
                TomoDiaryTomo(look: look, material: material, age: page.age,
                              mood: page.summary.grew ? .grew : page.apart > 0 ? .sulk : .happy)
                    .id(page.day)
                    .frame(width: 84, height: 84)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    TomoWordFlow(text: page.message, spacing: 8, lineSpacing: 4)
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                        .foregroundStyle(ink)
                    Text(page.gloss).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if !page.stickers.isEmpty {
                TomoChipFlow(spacing: 6) {
                    ForEach(page.stickers.prefix(12), id: \.self) { id in sticker(id) }
                    if page.stickers.count > 12 {
                        Text(lang.learner("diary.more", ["n": "\(page.stickers.count - 12)"])).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let word, page.stickers.contains(word) { wordCard(word) }
            if !page.facts.isEmpty {
                Divider().overlay(Color.secondary.opacity(0.3))
                TomoChipFlow(spacing: 12) {
                    ForEach(page.facts) { fact in
                        HStack(spacing: 5) {
                            if let dot = fact.dot { Circle().fill(TomoPostcardColors.color(dot)).frame(width: 7, height: 7) }
                            Text(fact.text).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(TomoPaper(margin: false))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func sticker(_ id: String) -> some View {
        let w = progress.word(id, learner: lang.learner.id)
        let tilt = Double(Int(TomoGardenLayout.jitter(id) * 7) - 3) * 0.8
        return Button { word = word == id ? nil : id } label: {
            HStack(spacing: 4) {
                if let emoji = w.emoji { TomoPictureView(emoji, size: 16) }
                Text(w.say).font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(.background, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.secondary.opacity(word == id ? 0.9 : 0.3)))
            .shadow(color: .black.opacity(0.08), radius: 0, y: 1)
            .rotationEffect(.degrees(tilt))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(w.say), \(w.meaning)")
    }

    private func wordCard(_ id: String) -> some View {
        let w = progress.word(id, learner: lang.learner.id), stage = progress.items[id]?.stage ?? 0
        return HStack(alignment: .top, spacing: 10) {
            if let emoji = w.emoji { TomoPictureView(emoji, size: 28) }
            VStack(alignment: .leading, spacing: 2) {
                Text(w.say).font(.system(size: 18, weight: .bold, design: .rounded))
                Text([w.reading, w.meaning].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.callout).foregroundStyle(.secondary)
                Text(lang.learner("stage.\(TomoSRS.group(stage))")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button { word = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                .buttonStyle(.plain).accessibilityLabel(lang.learner("garden.close"))
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// A brand-new Tomo's diary: the first page, with ばあ！ and what the diary will be.
struct TomoDiaryFirstPage: View {
    let progress: TomoProgress
    let look: TomoLook
    let material: TomoMaterial
    @ObservedObject private var lang = TomoLanguages.shared

    var body: some View {
        let hello = progress.pack.lines.hello
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(TomoStats.longDay(TomoStats.dayStart(of: TomoClock.now), lang.learner)).font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                Text(lang.learner("words.days", ["n": "\(progress.daysTogether)"]))
                    .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
            }
            HStack(alignment: .center, spacing: 12) {
                TomoDiaryTomo(look: look, material: material, age: progress.age, mood: .hello)
                    .frame(width: 84, height: 84)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(hello?.say ?? progress.pack.lines.practice).font(.system(size: 22, weight: .semibold, design: .rounded))
                    if let hello { Text(TomoStats.plain(hello.translation(lang.learner.id))).font(.callout).foregroundStyle(.secondary) }
                }
            }
            Text(lang.learner("diary.empty")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(TomoPaper(margin: false))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.1)))
    }
}

/// Tomo on a page, alive, at that day's form: it waves hello, leaps on a day it grew, sulks and then cheers up after
/// days apart, or wiggles happily.
private struct TomoDiaryTomo: View {
    enum Mood { case hello, grew, sulk, happy }
    @StateObject private var blob: TomoBlob
    private let growth: CGFloat
    private let mood: Mood

    init(look: TomoLook, material: TomoMaterial, age: Int, mood: Mood) {
        growth = CGFloat(min(max(age - 1, 0), TomoLook.ages - 1))
        self.mood = mood
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                switch mood {
                case .hello: blob.greet()
                case .grew: blob.levelUp()
                case .happy: blob.emote(.happy)
                case .sulk:
                    blob.emote(.annoyed)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { blob.emote(.happy) }
                }
            }
        }
    }
}
