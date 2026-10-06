import AppKit
import SwiftUI
import TomoCore

// MARK: - App icon from the character code (debug tool)
//
// TOMO_RENDER_ICON=<dir> renders Tomo with the real character code (TomoChick) and quits:
//   <dir>/icon-1024.png  the app icon (Tomo on a dark rounded square, Apple's 824-pt icon grid)
//   <dir>/tomo-1024.png  Tomo alone on transparent, for the menu bar template
//   <dir>/icon-ios-1024.png  the iPhone app icon: full-bleed and opaque (iOS draws the rounded mask)
// mac-demo/scripts/make-icons.py turns them into the asset catalog sizes.

@MainActor
enum TomoIconRenderer {
    private static var checkResult: Bool?

    static func renderIfRequested() {
        if ProcessInfo.processInfo.environment["TOMO_SELFTEST"] != nil {   // TomoProgress rules + store, sync merges
            let growth = TomoProgress.selfTest(), sync = TomoSync.selfTest()
            exit(growth && sync ? 0 : 1)
        }
        if let step = ProcessInfo.processInfo.environment["TOMO_SYNC_CHECK"] {   // TomoSync between data folders
            Task { checkResult = await TomoSync.check(step) }
            while checkResult == nil { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1)) }
            exit(checkResult == true ? 0 : 1)
        }
        if let dir = ProcessInfo.processInfo.environment["TOMO_RENDER_SOUNDS"] {
            TomoSounds.renderFiles(to: URL(fileURLWithPath: dir))
            NSApp.terminate(nil)
        }
        if let dir = ProcessInfo.processInfo.environment["TOMO_RENDER_ANIM"] {
            renderAnimation(to: URL(fileURLWithPath: dir))
            NSApp.terminate(nil)
        }
        if let dir = ProcessInfo.processInfo.environment["TOMO_RENDER_CARD_FRAMES"] {
            renderCardFrames(to: URL(fileURLWithPath: dir))
            NSApp.terminate(nil)
        }
        if let dir = ProcessInfo.processInfo.environment["TOMO_RENDER_SHEET"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            write(sheet, to: URL(fileURLWithPath: dir).appendingPathComponent("tomo-sheet.png"))
            NSApp.terminate(nil)
        }
        guard let dir = ProcessInfo.processInfo.environment["TOMO_RENDER_ICON"] else { return }
        let out = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        write(icon, to: out.appendingPathComponent("icon-1024.png"))
        write(tomo(size: 1024, grow: 1), to: out.appendingPathComponent("tomo-1024.png"))
        write(iosIcon, to: out.appendingPathComponent("icon-ios-1024.png"), opaque: true)
        NSApp.terminate(nil)
    }

    /// Tomo drawn by the same engine as the notch, at rest, looking straight ahead.
    private static func tomo(size: CGFloat, grow: CGFloat) -> some View {
        let chick = TomoChick()
        chick.setGrowth(grow)
        return Canvas { ctx, sz in
            chick.draw(ctx, size: sz)
        }
        .frame(width: size, height: size)
    }

    /// TOMO_RENDER_ANIM=<dir>: a scripted 16-second scene, rendered frame by frame on a scripted clock
    /// (frame-0000.png … at 20 fps), for checking motion. Join them into a GIF with any tool.
    private static func renderAnimation(to out: URL) {
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var t = 0.0
        let chick = TomoChick()
        chick.clock = { t }
        chick.particleOverhang = 40
        chick.setGrowth(0)
        let script: [(at: Double, run: (TomoChick) -> Void)] = [
            (0.8, { $0.talk() }), (1.1, { $0.talk() }), (1.4, { $0.talk() }),
            (2.2, { $0.grow(to: 1) }),                                   // hatches
            (4.2, { $0.setState(.question) }),
            (5.4, { $0.setState(.finished) }), (6.6, { $0.setState(.idle) }),
            (7.2, { $0.setState(.error) }), (8.1, { $0.setState(.idle) }),
            (9.6, { $0.emote(.love) }),
            (11.4, { $0.poke() }),
            (12.2, { $0.nudge() }),
            (13.4, { $0.grow(to: 2) }),                                  // 3さい
            (15.0, { $0.emote(.yawn) }),
        ]
        var next = 0
        let fps = 20.0
        for i in 0..<Int(fps * 16) {
            t = Double(i) / fps
            while next < script.count && script[next].at <= t { script[next].run(chick); next += 1 }
            chick.lookX = CGFloat(sin(t * 0.9)) * 0.9          // a cursor drifting around
            chick.lookY = CGFloat(cos(t * 0.6)) * 0.5
            chick.step()
            let frame = Canvas { ctx, sz in chick.draw(ctx, size: sz) }
                .frame(width: 240, height: 280)
                .background(Color.black)
            write(frame, to: out.appendingPathComponent(String(format: "frame-%04d.png", i)))
        }
    }

    /// TOMO_RENDER_CARD_FRAMES=<dir>: the ten frames of Tomo's loop on the iPhone's Lock Screen card, for each
    /// age and both moods: <dir>/<ready|sleep>-<0|1|2>/frame-0.png … frame-9.png (240 px, transparent).
    /// One frame shows per second (ios-demo/scripts/make-frame-font.py), so each is a distinct pose and
    /// frame 9 leads back into frame 0.
    private static func renderCardFrames(to out: URL) {
        typealias Beat = (lead: Double, run: (TomoChick) -> Void)
        let look: (CGFloat, CGFloat) -> (TomoChick) -> Void = { x, y in { $0.lookX = x; $0.lookY = y } }
        // Per frame: what happens, and how long before the frame is drawn.
        let ready: [[Beat]] = [
            [(0.6, look(0, 0))],
            [(0.6, look(-0.8, 0.2))],
            [(0.09, { $0.blink() })],                                   // eyes shut, still looking left
            [(0.6, look(0, 0)), (0.22, { $0.nudge() })],                // mid-hop
            [(0.5, { $0.emote(.happy) })],
            [(0.6, look(0, 0)), (0.12, { $0.talk() })],                 // a peep
            [(0.6, look(0.8, 0.4))],
            [(0.3, { $0.emote(.wink) })],
            [(0.6, look(0, 0)), (0.45, { $0.setState(.question, force: true) })],
            [(0.09, { $0.blink() })],
        ]
        let sleep: [[Beat]] = Array(repeating: [], count: 10)            // breathing and drifting z's
        for (name, mood, beats) in [("ready", BotState.question, ready), ("sleep", BotState.sleeping, sleep)] {
            for growth in 0...2 {
                let dir = out.appendingPathComponent("\(name)-\(growth)")
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                var t = 100.0
                let chick = TomoChick()
                chick.clock = { t }
                chick.setGrowth(CGFloat(growth))
                chick.step()
                chick.setState(mood, force: true)
                // Run a few seconds first so the z's are already drifting, then one frame per second.
                var events = beats.enumerated().flatMap { k, list in list.map { (at: 104 + Double(k) - $0.lead, run: $0.run) } }
                    .sorted { $0.at < $1.at }
                for k in 0..<10 {
                    let shot = 104 + Double(k)
                    while t < shot {
                        t = min(shot, t + 1.0 / 60)
                        while let e = events.first, e.at <= t { e.run(chick); events.removeFirst() }
                        chick.step()
                    }
                    // Tomo a little smaller and lower than the frame, so hops and the "?" stay inside it.
                    let frame = Canvas { ctx, _ in
                        var c = ctx
                        c.translateBy(x: 24, y: 40)
                        chick.draw(c, size: CGSize(width: 192, height: 192))
                    }.frame(width: 240, height: 240)
                    write(frame, to: dir.appendingPathComponent("frame-\(k).png"))
                }
            }
        }
    }

    /// TOMO_RENDER_SHEET=<dir>: every age and face on one image, for reviewing the character.
    private static var sheet: some View {
        func cell(_ label: String, growth: CGFloat = 1, _ setup: (TomoChick) -> Void = { _ in }) -> some View {
            let chick = TomoChick()
            chick.setGrowth(growth)
            setup(chick)
            return VStack(spacing: 4) {
                Canvas { ctx, sz in chick.draw(ctx, size: sz) }.frame(width: 220, height: 220)
                Text(label).font(.system(size: 18, weight: .medium)).foregroundColor(.white.opacity(0.7))
            }
        }
        let rows: [[AnyView]] = [
            [AnyView(cell("1さい", growth: 0)), AnyView(cell("2さい", growth: 1)), AnyView(cell("3さい", growth: 2)),  // text-ok: debug sheet labels
             AnyView(cell("look", growth: 1) { $0.lookX = 0.8; $0.lookY = -0.6; for _ in 0..<40 { $0.step() } })],
            [AnyView(cell("right", growth: 1) { $0.setState(.finished) }),
             AnyView(cell("wrong", growth: 1) { $0.setState(.error) }),
             AnyView(cell("huh?", growth: 1) { $0.setState(.question); for _ in 0..<60 { $0.step() } }),
             AnyView(cell("asleep", growth: 1) { $0.setState(.sleeping) })],
            [AnyView(cell("love", growth: 1) { $0.emote(.love) }),
             AnyView(cell("surprised", growth: 1) { $0.emote(.surprised) }),
             AnyView(cell("yawn", growth: 0) { $0.emote(.yawn) }),
             AnyView(cell("wink", growth: 2) { $0.emote(.wink) })],
        ]
        return VStack(spacing: 10) {
            ForEach(0..<rows.count, id: \.self) { r in
                HStack(spacing: 10) { ForEach(0..<rows[r].count, id: \.self) { rows[r][$0] } }
            }
        }
        .padding(20)
        .background(Color.black)
    }

    private static var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: "#2B303B"), Color(hex: "#0E1014")],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    RadialGradient(colors: [Color(hex: "#FFC53A").opacity(0.35), .clear],
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

    /// The iPhone icon: Tomo on a sky-blue gradient, edge to edge (iOS masks it and rejects transparency).
    /// TOMO_ICON_BG="#top,#bottom" tries other backgrounds.
    private static var iosIcon: some View {
        let bg = (ProcessInfo.processInfo.environment["TOMO_ICON_BG"] ?? "#8FD3FF,#3E9BEA").split(separator: ",").map(String.init)
        return ZStack {
            LinearGradient(colors: bg.map { Color(hex: $0) }, startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color.white.opacity(0.35), .clear],
                           center: UnitPoint(x: 0.5, y: 0.5), startRadius: 0, endRadius: 520)
            tomo(size: 900, grow: 1).offset(y: 48)
        }
        .frame(width: 1024, height: 1024)
    }

    private static func write(_ view: some View, to url: URL, opaque: Bool = false) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.isOpaque = opaque
        guard let cg = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
            NSLog("Tomo: couldn't render \(url.lastPathComponent)")
            return
        }
        try? png.write(to: url)
    }
}
