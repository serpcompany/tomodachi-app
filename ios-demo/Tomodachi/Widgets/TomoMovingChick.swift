import SwiftUI
import TomoCore

// MARK: - Tomo moving where iOS only shows still pictures (Lock Screen, Dynamic Island, Home Screen)
//
// iOS draws a widget or Live Activity once and only keeps its timers ticking. So Tomo is a timer counting
// seconds, set in a font whose digits 0–9 are ten frames of Tomo's own drawing (TOMO_RENDER_CARD_FRAMES on
// the Mac app, packed by ios-demo/scripts/make-frame-font.py into Fonts/Tomo<Ready|Sleep><age>.ttf). Only
// the timer's last digit shows, so Tomo changes pose once a second and loops every ten seconds.
// decisions.md, 2026-10-06.

struct TomoMovingChick: View {
    let glance: TomoGlance
    /// Something is waiting: Tomo asks over. Otherwise it sleeps until the next words.
    let ready: Bool
    let size: CGFloat

    private var font: String {
        "Tomo\(ready ? "Ready" : "Sleep")\(min(max(Int(glance.growth.rounded()), 0), 2))"
    }

    var body: some View {
        Text(timerInterval: glance.updated...Date.distantFuture, countsDown: false)
            .font(.custom(font, size: size))
            .contentTransition(.identity)
            .multilineTextAlignment(.trailing)
            .lineLimit(1)
            // Wide enough for "12:00:00" (the colon takes no room), then clipped to the last digit.
            .frame(width: size * 8, alignment: .trailing)
            .frame(width: size, height: size, alignment: .trailing)
            .clipped()
            .id(ready)
            .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
}
