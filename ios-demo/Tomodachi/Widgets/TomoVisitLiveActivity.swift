import ActivityKit
import AppIntents
import SwiftUI
import TomoCore
import WidgetKit

// MARK: - Tomo on the Lock Screen and in the Dynamic Island (issue #52)
//
// Two rows beside Tomo. Ready: what's waiting ("A new word is ready to learn") over its age, level and
// experience bar, and a round Play button at the edge. Play opens one round right on the card: Tomo's word
// and its choices (TomoVisitActivity.swift); Tomo reacts, and a few seconds after a right answer the card
// invites again. Not yet: Tomo sleeps, and the first row says when the next words come ("New words at 10:12";
// a ticking countdown loses its seconds on the Lock Screen, which shows "9:--"). Tomo moves
// everywhere here (TomoMovingMascot); each update also swaps its pose with a short transition. The compact
// Dynamic Island keeps Tomo's call ("あそぼ！"). Tapping anywhere else opens the app.

struct TomoVisitLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TomoVisitAttributes.self) { context in
            Group {
                if let round = shownRound(context) {
                    TomoRoundCard(glance: context.state.glance, round: round)
                } else {
                    TomoCardView(glance: context.state.glance, ready: isReady(context))
                }
            }
            .padding(14)
            .activityBackgroundTint(Color(red: 0.06, green: 0.09, blue: 0.11))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let g = context.state.glance, ready = isReady(context), round = shownRound(context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if let round { TomoRoundMascot(glance: g, round: round, size: 64) }
                    else { TomoMovingMascot(glance: g, ready: ready, size: 64) }
                }
                DynamicIslandExpandedRegion(.center) {
                    if let round { TomoRoundLine(round: round) } else { TomoCardText(glance: g, ready: ready) }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if round == nil && ready { TomoPlayButton(glance: g, size: 44) }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let round { TomoRoundChoices(round: round) }
                }
            } compactLeading: {
                TomoMovingMascot(glance: g, ready: ready, size: 26)
            } compactTrailing: {
                if ready {
                    Text(g.invite).font(.system(size: 13, weight: .bold, design: .rounded)).lineLimit(1)
                } else if let next = g.nextDue {
                    Text(timerInterval: Date.now...max(next, .now), countsDown: true)
                        .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                        .frame(maxWidth: 56)
                }
            } minimal: {
                TomoMovingMascot(glance: g, ready: ready, size: 24)
            }
        }
    }

    /// The round on the card, until its stale date: a few seconds after a right answer, or an abandoned round.
    private func shownRound(_ context: ActivityViewContext<TomoVisitAttributes>) -> TomoVisitAttributes.CardRound? {
        context.isStale ? nil : context.state.round
    }

    /// Something is waiting, or the next words have come due since the last update.
    private func isReady(_ context: ActivityViewContext<TomoVisitAttributes>) -> Bool {
        let g = context.state.glance
        return g.waiting || (context.isStale && context.state.round == nil) || (g.nextDue.map { $0 <= .now } ?? false)
    }
}

struct TomoCardView: View {
    let glance: TomoGlance
    let ready: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            TomoMovingMascot(glance: glance, ready: ready, size: 84)
            TomoCardText(glance: glance, ready: ready)
            if ready { TomoPlayButton(glance: glance, size: 52) }
        }
        .foregroundStyle(.white)
    }
}

/// Opens one round on the card (TomoPlayIntent, run by the app): a round play button at the card's edge.
struct TomoPlayButton: View {
    let glance: TomoGlance
    let size: CGFloat

    var body: some View {
        Button(intent: TomoPlayIntent()) {
            Image(systemName: "play.fill")
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(Color(red: 0.12, green: 0.09, blue: 0.02))
                .offset(x: size * 0.04)                      // the triangle looks centered a little right
                .frame(width: size, height: size)
                .background(Color(red: 1, green: 0.8, blue: 0.3), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(glance.play)
    }
}

/// A round on the card: Tomo, what it says, and the choices (or, after a right answer, what it meant).
struct TomoRoundCard: View {
    let glance: TomoGlance
    let round: TomoVisitAttributes.CardRound

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            TomoRoundMascot(glance: glance, round: round, size: 72)
            VStack(alignment: .leading, spacing: 8) {
                TomoRoundLine(round: round)
                TomoRoundChoices(round: round)
            }
        }
        .foregroundStyle(.white)
    }
}

/// Tomo asking (moving), or reacting to the answer: a hop for a right one, a shake-off for a miss.
struct TomoRoundMascot: View {
    let glance: TomoGlance
    let round: TomoVisitAttributes.CardRound
    let size: CGFloat

    var body: some View {
        Group {
            if let right = round.right {
                TomoBlobStill(state: right ? .finished : .error, emote: right ? .happy : nil,
                              growth: CGFloat(TomoMovingMascot.fontAge(glance)))
                    .frame(width: size, height: size)
            } else {
                TomoMovingMascot(glance: glance, ready: true, size: size)
            }
        }
        .id(round.right)
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
}

/// What Tomo says, and the result once answered ("Win +1", "Miss").
struct TomoRoundLine: View {
    let round: TomoVisitAttributes.CardRound

    var body: some View {
        HStack(spacing: 8) {
            Text(round.say)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            if let result = round.result {
                Text(result)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background((round.right == true ? Color.green : Color.red).opacity(0.35), in: Capsule())
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }
}

/// The choices as buttons (TomoAnswerIntent); after a right answer, the reading and meaning instead.
struct TomoRoundChoices: View {
    let round: TomoVisitAttributes.CardRound

    var body: some View {
        if round.right == true, let note = round.note {
            Text(note)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.8))
                .lineLimit(2).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        } else {
            HStack(spacing: 8) {
                ForEach(round.choices, id: \.id) { choice in
                    Button(intent: TomoAnswerIntent(choice: choice.id)) {
                        Group {
                            if let emoji = choice.emoji {
                                Text(emoji).font(.system(size: 26))
                            } else {
                                Text(choice.label ?? "")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .lineLimit(2).minimumScaleFactor(0.6)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(choice.id == round.picked ? Color.red.opacity(0.35) : Color.white.opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Two rows: what's waiting (or, until the next words, "New words at 10:12"), then Tomo's age, level and
/// experience bar.
struct TomoCardText: View {
    let glance: TomoGlance
    let ready: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if !ready, let next = glance.nextDue, next > .now {
                    let parts = glance.nextLabel.components(separatedBy: "{time}")
                    (Text(parts[0]) + Text(next, style: .time) + Text(parts.count > 1 ? parts[1] : ""))
                        .foregroundStyle(Color.white.opacity(0.8))
                } else {
                    Text(glance.waiting ? glance.status : glance.statusLater)
                        .contentTransition(.opacity)
                }
            }
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .lineLimit(1).minimumScaleFactor(0.7)
            HStack(spacing: 8) {
                Text(glance.age)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 1, green: 0.85, blue: 0.66))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color(red: 0.29, green: 0.2, blue: 0.14), in: Capsule())
                Text(glance.level)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.7))
                ProgressView(value: min(max(glance.progress, 0), 1))
                    .tint(Color(red: 0.55, green: 0.85, blue: 0.45))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Xcode canvas previews: the Lock Screen card and each Dynamic Island shape, ready and waiting

#if DEBUG
@MainActor
private func previewGlance(waiting: Bool) -> TomoGlance {
    let ui = TomoLanguages.shared.learner, target = TomoLanguages.shared.target
    return TomoGlance(growth: 1, age: target.ageLabel(3), level: ui("level", ["n": "12"]), progress: 0.4,
                      waiting: waiting, status: waiting ? ui("glance.due", ["n": "3"]) : ui("glance.done"),
                      nextDue: waiting ? nil : .now.addingTimeInterval(95 * 60), statusLater: ui("glance.waiting"),
                      about: ui("glance.about"), invite: target.lines.invite ?? target.lines.practice,
                      nextLabel: ui("glance.next"), play: ui("glance.play"), updated: .now.addingTimeInterval(-30 * 60))
}

/// The first picture round in the pack.
@MainActor
private var previewRound: TomoVisitAttributes.CardRound? {
    let rounds = TomoLanguages.shared.target.levels.flatMap { $0.rounds ?? [] }
    guard let r = rounds.first(where: { $0.choices != nil }), let choices = r.choices else { return nil }
    return .init(say: r.say, choices: choices.map { .init(id: $0, emoji: $0, label: nil) })
}

#Preview("Lock Screen", as: .content, using: TomoVisitAttributes()) {
    TomoVisitLiveActivity()
} contentStates: {
    TomoVisitAttributes.ContentState(glance: previewGlance(waiting: true))
    TomoVisitAttributes.ContentState(glance: previewGlance(waiting: false))
    TomoVisitAttributes.ContentState(glance: previewGlance(waiting: true), round: previewRound)
}

#Preview("Island, expanded", as: .dynamicIsland(.expanded), using: TomoVisitAttributes()) {
    TomoVisitLiveActivity()
} contentStates: {
    TomoVisitAttributes.ContentState(glance: previewGlance(waiting: true))
    TomoVisitAttributes.ContentState(glance: previewGlance(waiting: false))
}

#Preview("Island, compact", as: .dynamicIsland(.compact), using: TomoVisitAttributes()) {
    TomoVisitLiveActivity()
} contentStates: {
    TomoVisitAttributes.ContentState(glance: previewGlance(waiting: true))
    TomoVisitAttributes.ContentState(glance: previewGlance(waiting: false))
}

#Preview("Island, minimal", as: .dynamicIsland(.minimal), using: TomoVisitAttributes()) {
    TomoVisitLiveActivity()
} contentStates: {
    TomoVisitAttributes.ContentState(glance: previewGlance(waiting: true))
}
#endif
