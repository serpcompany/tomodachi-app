import ActivityKit
import SwiftUI
import TomoCore
import WidgetKit

// MARK: - Tomo on the Lock Screen and in the Dynamic Island (issue #52)
//
// Ready: Tomo asks over, with what's waiting ("A new word is ready to learn") and its experience bar. Not
// yet: Tomo sleeps, and a countdown and a bar run live to the next words. Tomo moves everywhere here
// (TomoMovingChick); each update also swaps its pose with a short transition. The compact Dynamic Island
// keeps Tomo's call ("あそぼ！"). Tapping opens the app.

struct TomoVisitLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TomoVisitAttributes.self) { context in
            TomoCardView(glance: context.state.glance, ready: isReady(context))
                .padding(14)
                .activityBackgroundTint(Color(red: 0.06, green: 0.09, blue: 0.11))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let g = context.state.glance, ready = isReady(context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    TomoMovingChick(glance: g, ready: ready, size: 64)
                }
                DynamicIslandExpandedRegion(.center) {
                    TomoCardText(glance: g, ready: ready)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !ready { TomoCountdown(glance: g) }
                }
            } compactLeading: {
                TomoMovingChick(glance: g, ready: ready, size: 26)
            } compactTrailing: {
                if ready {
                    Text(g.invite).font(.system(size: 13, weight: .bold, design: .rounded)).lineLimit(1)
                } else if let next = g.nextDue {
                    Text(timerInterval: Date.now...max(next, .now), countsDown: true)
                        .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                        .frame(maxWidth: 56)
                }
            } minimal: {
                TomoMovingChick(glance: g, ready: ready, size: 24)
            }
        }
    }

    /// Something is waiting, or the next words have come due since the last update.
    private func isReady(_ context: ActivityViewContext<TomoVisitAttributes>) -> Bool {
        context.state.glance.waiting || context.isStale
    }
}

struct TomoCardView: View {
    let glance: TomoGlance
    let ready: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            TomoMovingChick(glance: glance, ready: ready, size: 84)
            VStack(alignment: .leading, spacing: 8) {
                TomoCardText(glance: glance, ready: ready)
                if !ready { TomoCountdown(glance: glance) }
            }
        }
        .foregroundStyle(.white)
    }
}

/// What's waiting, then Tomo's age, level and experience bar.
struct TomoCardText: View {
    let glance: TomoGlance
    let ready: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(glance.waiting ? glance.status : ready ? glance.statusLater : glance.status)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(ready ? 1 : 0.75))
                .lineLimit(1).minimumScaleFactor(0.7)
                .contentTransition(.opacity)
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

/// "New words in 1:42:10" and a bar, both running live until the next words come due.
struct TomoCountdown: View {
    let glance: TomoGlance

    var body: some View {
        if let next = glance.nextDue, next > .now {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(glance.nextLabel)
                    Text(timerInterval: Date.now...next, countsDown: true).monospacedDigit()
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.7))
                ProgressView(timerInterval: min(glance.updated, next)...next, countsDown: false) { EmptyView() }
                    currentValueLabel: { EmptyView() }
                    .tint(Color(red: 1, green: 0.85, blue: 0.4))
            }
        }
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
                      nextLabel: ui("glance.next"), updated: .now.addingTimeInterval(-30 * 60))
}

#Preview("Lock Screen", as: .content, using: TomoVisitAttributes()) {
    TomoVisitLiveActivity()
} contentStates: {
    TomoVisitAttributes.ContentState(glance: previewGlance(waiting: true))
    TomoVisitAttributes.ContentState(glance: previewGlance(waiting: false))
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
