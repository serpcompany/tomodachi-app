import SwiftUI

// MARK: - Tomo: how Tomo is growing (the Mac window's first page, the iPhone's Tomo tab)
//
// A live Tomo with its age and level, the experience bar (its goal fills only when the level is done) and what's left;
// days together; the Today line ("12 answers · 3 new words", TomoStats), with, on a Monday, Tomo's week come as a
// postcard; and growing up, as marks on a height pillar with each age and what it brings (TomoHeightPillar.swift).
// Everything shown comes from TomoGame, TomoProgress and TomoStats, which decide it.

public struct TomoGrowthScreen: View {
    @ObservedObject var game = TomoGame.shared
    @ObservedObject var lang = TomoLanguages.shared
    private let play: (() -> Void)?
    private let together: (() -> Void)?

    /// `play`: what "Play with Tomo" does (the Mac opens the island; the iPhone goes to the play tab). Nil hides it.
    /// `together`: opens the Together screen, where Tomo's week is (on a Monday, Today says it came).
    public init(play: (() -> Void)? = nil, together: (() -> Void)? = nil) {
        self.play = play
        self.together = together
    }

    private var progress: TomoProgress { game.progress }

    public var body: some View {
        #if os(iOS)
        // Test runs that look at the pillar (TOMO_PILLAR) on the iPhone scroll to it; the Mac's use a taller window.
        ScrollViewReader { proxy in
            form.task {
                guard ProcessInfo.processInfo.environment["TOMO_PILLAR"] != nil else { return }
                try? await Task.sleep(for: .seconds(1.5))
                proxy.scrollTo("pillar", anchor: .top)
            }
        }
        #else
        form
        #endif
    }

    private var form: some View {
        Form {
            Section {
                hero.padding(.vertical, 4)
                if game.isScratch {
                    Label(lang.learner("words.testing"), systemImage: "flask").foregroundStyle(.orange)
                }
                if let play {
                    // On the Mac the style picks the label's colour: white on teal, and a readable one on grey while the
                    // window is behind another (a fixed white vanished there in light mode, #195). The iPhone's is
                    // always teal, and its Form would tint the icon green.
                    Button(action: play) {
                        Label(lang.learner("tomo.play"), systemImage: "play.fill")
                            .font(.body.weight(.semibold))
                            #if os(iOS)
                            .foregroundStyle(.white)
                            #endif
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                    .controlSize(.large)
                }
            }

            Section(lang.learner("growth.today")) {
                let stats = TomoStats(progress)
                TomoTodayLine(parts: stats.todayParts(lang.learner), separator: lang.learner("list.separator"))
                // Monday morning: Tomo's week has come, as a postcard (the Together screen).
                if let together, let week = stats.postcardCameToday(lang.learner) {
                    Button(action: together) {
                        HStack(spacing: 10) {
                            Image(systemName: "envelope.fill").foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(lang.learner("postcard.arrived")).font(.callout.weight(.semibold))
                                Text(week).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .id(game.progressVersion)

            Section(lang.learner("growth.growingUp")) {
                // Growing up, as marks on a height pillar, for the learner's own Tomo (TomoHeightPillar.swift).
                TomoHeightPillar(progress: progress, look: TomoLook.current, material: .own, version: game.progressVersion)
                    .id("pillar")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Tomo, its age and level, the bar and what's left

    @ViewBuilder private var hero: some View {
        #if os(iOS)
        // The iPhone's Tomo tab: Tomo big, over its numbers.
        VStack(spacing: 10) {
            TomoLiveAvatar(size: 132, material: .own)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(game.age).font(.system(size: 28, weight: .bold, design: .rounded))
                Text(lang.learner("level", ["n": "\(game.level)"])).font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(lang.learner("words.days", ["n": "\(progress.daysTogether)"])).font(.callout).foregroundStyle(.secondary)
            stats.padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        #else
        HStack(spacing: 16) {
            TomoLiveAvatar(size: 76, material: .own, weather: TomoCalendar.weatherToday)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(game.age).font(.system(size: 22, weight: .bold))
                    Text(lang.learner("level", ["n": "\(game.level)"])).font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(lang.learner("words.days", ["n": "\(progress.daysTogether)"])).font(.callout)
                        .foregroundStyle(.secondary)
                }
                stats
            }
        }
        #endif
    }

    /// The bar (the card's bar: the goal at its end fills only when the level is done), the words known, what's left
    /// and when the next word is ready; when Tomo rests, when it's back.
    private var stats: some View {
        VStack(alignment: .leading, spacing: 6) {
            TomoGrowthBar(progress: game.levelProgress, standing: game.levelStanding,
                          colors: [.teal.opacity(0.7), .teal], empty: Color.secondary.opacity(0.18),
                          outline: Color.secondary.opacity(0.4))
                .frame(height: 6)
                .padding(.vertical, 2)
            Text(progress.isLastLevel
                 ? lang.learner("words.lastLevel", ["known": "\(game.levelKnown)", "needed": "\(game.levelNeeded)"])
                 : lang.learner("words.toNext", ["known": "\(game.levelKnown)", "needed": "\(game.levelNeeded)",
                                                 "next": "\(game.level + 1)"]))
                .font(.callout).foregroundStyle(.secondary)
            Label { Text(game.phase == .resting ? game.restLines.left : game.whatsLeft()) } icon: {
                Image(systemName: "flag.fill").foregroundStyle(.teal)
            }
            .font(.callout.weight(.medium))
            if game.phase == .resting {
                Label(game.restLines.back, systemImage: "clock").font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension TomoProgress {
    /// An age in the pack, with its first and last level.
    public struct AgeSpan: Sendable { public let age: Int; public var from: Int; public var to: Int }

    /// Every age in the pack, with its levels: what the Tomo screen's "Growing up" lists.
    public var ageSpans: [AgeSpan] {
        var out: [AgeSpan] = []
        for (i, l) in pack.levels.enumerated() {
            if let last = out.last, last.age == l.age { out[out.count - 1].to = i + 1 }
            else { out.append(AgeSpan(age: l.age, from: i + 1, to: i + 1)) }
        }
        return out
    }

    /// Days since Tomo hatched, counting today as day 1.
    public var daysTogether: Int { daysTogether(at: TomoClock.now) }

    /// Days since Tomo hatched at a time, counting that day as day 1 (a postcard's last day).
    public func daysTogether(at t: Date) -> Int {
        max(1, (Calendar.current.dateComponents([.day], from: metAt, to: t).day ?? 0) + 1)
    }
}
