import AppKit
import SwiftUI

// MARK: - App icon from the character code (debug tool)
//
// TOMO_RENDER_ICON=<dir> renders Tomo with the real BotEngine and quits:
//   <dir>/icon-1024.png  the app icon (Tomo on a dark rounded square, Apple's 824-pt icon grid)
//   <dir>/tomo-1024.png  Tomo alone on transparent, for the menu bar template
// mac-demo/scripts/make-icons.py turns them into the asset catalog sizes.

@MainActor
enum TomoIconRenderer {
    static func renderIfRequested() {
        guard let dir = ProcessInfo.processInfo.environment["TOMO_RENDER_ICON"] else { return }
        let out = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        write(icon, to: out.appendingPathComponent("icon-1024.png"))
        write(tomo(size: 1024, grow: 1), to: out.appendingPathComponent("tomo-1024.png"))
        NSApp.terminate(nil)
    }

    /// Tomo drawn by the same engine as the notch, at rest, looking straight ahead.
    private static func tomo(size: CGFloat, grow: CGFloat) -> some View {
        let engine = BotEngine()
        engine.grow = grow
        return Canvas { ctx, sz in
            engine.draw(context: ctx, size: sz)
        }
        .frame(width: size, height: size)
    }

    private static var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: "#2B303B"), Color(hex: "#0E1014")],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    RadialGradient(colors: [Color(hex: "#F6B99A").opacity(0.45), .clear],
                                   center: UnitPoint(x: 0.5, y: 0.58), startRadius: 0, endRadius: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 4)
                )
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.35), radius: 20, y: 12)
            tomo(size: 760, grow: 1)
                .offset(y: 40)
        }
        .frame(width: 1024, height: 1024)
    }

    private static func write(_ view: some View, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let cg = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
            NSLog("Tomo: couldn't render \(url.lastPathComponent)")
            return
        }
        try? png.write(to: url)
    }
}
