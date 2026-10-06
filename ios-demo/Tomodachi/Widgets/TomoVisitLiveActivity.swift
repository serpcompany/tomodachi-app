import ActivityKit
import SwiftUI
import TomoCore
import WidgetKit

// MARK: - Tomo on the Lock Screen and in the Dynamic Island (issue #52)
//
// Ready: Tomo asks over with its line in a bubble ("あそぼ！") and what's waiting. Not yet: Tomo sleeps, and a
// countdown and a bar run live to the next words. Those timers are the motion iOS keeps running here; each
// update also swaps Tomo's pose with a short transition (decisions.md, 2026-10-06). Tapping opens the app.

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
                    TomoCardChick(glance: g, ready: ready).frame(width: 64, height: 64)
                }
                DynamicIslandExpandedRegion(.center) {
                    TomoCardText(glance: g, ready: ready)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !ready { TomoCountdown(glance: g) }
                }
            } compactLeading: {
                TomoCardChick(glance: g, ready: ready).frame(width: 26, height: 26)
            } compactTrailing: {
                if ready {
                    Text(g.invite).font(.system(size: 13, weight: .bold, design: .rounded)).lineLimit(1)
                } else if let next = g.nextDue {
                    Text(timerInterval: Date.now...max(next, .now), countsDown: true)
                        .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                        .frame(maxWidth: 56)
                }
            } minimal: {
                TomoCardChick(glance: g, ready: ready).frame(width: 24, height: 24)
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
            TomoCardChick(glance: glance, ready: ready).frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: 8) {
                TomoCardText(glance: glance, ready: ready)
                if !ready { TomoCountdown(glance: glance) }
            }
        }
        .foregroundStyle(.white)
    }
}

/// Tomo held in the pose of the moment: asking when something's ready, asleep while it waits.
struct TomoCardChick: View {
    let glance: TomoGlance
    let ready: Bool

    var body: some View {
        TomoChickStill(state: ready ? .question : .sleeping, growth: glance.growth)
            .id(ready)
            .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
}

/// Tomo's call in a speech bubble, and what's waiting.
struct TomoCardText: View {
    let glance: TomoGlance
    let ready: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                if ready {
                    Text(glance.invite)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Color.white.opacity(0.14), in: Capsule())
                        .transition(.push(from: .bottom))
                }
                Text(glance.age)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 1, green: 0.85, blue: 0.66))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color(red: 0.29, green: 0.2, blue: 0.14), in: Capsule())
            }
            Text(glance.waiting ? glance.status : ready ? glance.statusLater : glance.status)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(ready ? 1 : 0.75))
                .lineLimit(1).minimumScaleFactor(0.7)
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
