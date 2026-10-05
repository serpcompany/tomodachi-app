import ActivityKit
import Foundation
import TomoCore

// MARK: - Keeps Tomo's Lock Screen card (TomoVisitAttributes) in step with progress
//
// The shell calls `show(_:)` with every new TomoGlance. iOS only lets an app start a Live Activity from the
// foreground, so the card starts while you play and is updated after; its stale date (`nextDue`) flips it
// to "ready" on its own when new words come due.

@MainActor
final class TomoLiveVisit {
    static let shared = TomoLiveVisit()

    private var activity: Activity<TomoVisitAttributes>? = Activity<TomoVisitAttributes>.activities.first

    func show(_ glance: TomoGlance) {
        let content = ActivityContent(state: TomoVisitAttributes.ContentState(glance: glance),
                                      staleDate: glance.waiting ? nil : glance.nextDue)
        if let activity, activity.activityState == .active {
            nonisolated(unsafe) let running = activity   // ActivityKit's Activity isn't marked Sendable
            Task { await running.update(content) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            do { activity = try Activity.request(attributes: TomoVisitAttributes(), content: content) }
            catch { NSLog("Tomo: couldn't start the Lock Screen card: \(error)") }
        }
    }
}
