import SwiftUI

// MARK: - A slider whose knob shows in light and dark (#195)
//
// The Mac's slider knob is white, and at the end of its track on a light page it all but vanished (the garden's Replay,
// the pillar's slide back in time). On the Mac this one draws its knob with a ring and a shadow, over a track filled in
// the tint, so it reads anywhere on the track in both modes; to VoiceOver and keyboard navigation it is the system
// slider. The iPhone keeps the system slider: its knob has a shadow, the app is dark, and it lets a page scroll past it.

public struct TomoSlider: View {
    @Binding private var value: Double   // 0…1
    private let tint: Color
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    @State private var dragging = false

    private static let knob: CGFloat = 20
    private static let track: CGFloat = 5

    public init(value: Binding<Double>, tint: Color) {
        _value = value
        self.tint = tint
    }

    public var body: some View {
        #if os(iOS)
        Slider(value: $value, in: 0...1).tint(tint)
        #else
        drawn
        #endif
    }

    #if os(macOS)
    private var drawn: some View {
        GeometryReader { geo in
            let k = Self.knob, span = max(1, geo.size.width - k)
            let x = CGFloat(min(1, max(0, value))) * span
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(scheme == .dark ? 0.22 : 0.14)).frame(height: Self.track)
                Capsule().fill(tint).frame(width: x + k / 2, height: Self.track)
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(Color.black.opacity(scheme == .dark ? 0.35 : 0.22), lineWidth: 1))
                    .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.25), radius: 2, y: 1)
                    .frame(width: k, height: k)
                    .scaleEffect(dragging ? 1.12 : 1)
                    .offset(x: x)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    dragging = true
                    value = Double(min(1, max(0, (g.location.x - k / 2) / span)))
                }
                .onEnded { _ in dragging = false })
        }
        .frame(height: 24)
        .opacity(enabled ? 1 : 0.5)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: dragging)
        .accessibilityRepresentation { Slider(value: $value, in: 0...1) }
        .focusable(interactions: .activate)
        .onMoveCommand { direction in
            switch direction {
            case .left:  value = max(0, value - 0.05)
            case .right: value = min(1, value + 0.05)
            default:     break
            }
        }
    }
    #endif
}
