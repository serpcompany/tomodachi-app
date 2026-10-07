import SwiftUI
import TomoCore

// MARK: - The first run on the iPhone (issue #88): TomoOnboardingView, full screen, over Tomo's screen
//
// TomodachiApp decides at launch who sees it (TomoOnboarding.checkAtLaunch, before anything opens the store: the
// data folder decides, as on the Mac), and TomoPhoneShell holds the flow while it's on screen: Tomo's game waits
// (it isn't "open", and its visit clock is held), the Lock Screen card doesn't start, and no reminder is scheduled.
// The flow's steps and choices are TomoOnboarding's (Shell.phone). When it ends, the choices are saved, the screen
// slides away to Tomo, and Tomo asks its next word (TomoPhoneShell.endFirstRun).
// TOMO_ONBOARDING=<step> opens it at a step, TOMO_AUTOPLAY=1 plays it through (docs/verification.md).

extension View {
    /// Covers the whole app (the tabs) with the first run while there is one.
    func tomoFirstRun(_ shell: TomoPhoneShell) -> some View { modifier(TomoPhoneFirstRun(shell: shell)) }
}

private struct TomoPhoneFirstRun: ViewModifier {
    @ObservedObject var shell: TomoPhoneShell

    /// The first run gets the screen's size, whatever size Tomo's screen under it would take: an overlay (or a ZStack)
    /// would size it like that screen.
    func body(content: Content) -> some View {
        GeometryReader { geo in
            ZStack {
                content
                    .frame(width: geo.size.width, height: geo.size.height)
                    .accessibilityHidden(shell.firstRun != nil)
                if let model = shell.firstRun {
                    TomoOnboardingView(model: model)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .transition(.move(edge: .bottom))
                }
            }
        }
    }
}
