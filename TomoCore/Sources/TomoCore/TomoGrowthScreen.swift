import SwiftUI

// MARK: - Tomo: how Tomo is growing (the Mac window's first page, the iPhone's Tomo tab)
//
// A live Tomo with its age and level, the experience bar (its goal fills only when the level is done) and what's left;
// days together; the Today line ("12 answers · 3 new words", TomoStats), with, on a Monday, Tomo's week come as a
// postcard; and each age with its levels and what it brings (grown / now / later). Everything shown comes from
// TomoGame, TomoProgress and TomoStats, which decide it.

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
        Form {
            Section {
                hero.padding(.vertical, 4)
                if game.isScratch {
                    Label(lang.learner("words.testing"), systemImage: "flask").foregroundStyle(.orange)
                }
                if let play {
                    Button(action: play) {
                        Label(lang.learner("tomo.play"), systemImage: "play.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                    .controlSize(.large)
                }
            }

            Section(lang.learner("growth.today")) {
                let stats = TomoStats(progress)
                TomoTodayLine(text: stats.todayLine(lang.learner))
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
                ForEach(progress.ageSpans, id: \.age) { ageRow($0) }
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
            TomoLiveAvatar(size: 76, material: .own)
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

    // MARK: Growing up: each age, its levels and what it brings

    private func ageRow(_ a: TomoProgress.AgeSpan) -> some View {
        let state = a.age < game.stage ? "grown" : a.age == game.stage ? "now" : "later"
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
        .padding(.vertical, 2)
        .opacity(state == "later" ? 0.65 : 1)
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
