import AppKit
import SwiftUI
import TomoCore

// MARK: - App icon from the character code (debug tool)
//
// TOMO_RENDER_ICON=<dir> renders the Tomodachi mascot with the real character code (TomoBlob) and quits:
//   <dir>/icon-1024.png  the app icon (Tomo on a dark rounded square, Apple's 824-pt icon grid)
//   <dir>/tomo-1024.png  Tomo alone on transparent, for the menu bar template
//   <dir>/icon-ios-1024.png  the iPhone app icon: full-bleed and opaque (iOS draws the rounded mask)
// mac-demo/scripts/make-icons.py turns them into the asset catalog sizes.

@MainActor
enum TomoIconRenderer {
    private static var checkResult: Bool?

    static func renderIfRequested() {
        if ProcessInfo.processInfo.environment["TOMO_SELFTEST"] != nil {   // growth, store, sync, looks, island, first run, sounds
            let growth = TomoProgress.selfTest(), sync = TomoSync.selfTest(), look = TomoLook.selfTest()
            let island = TomoIslandSelfTest.run(), firstRun = TomoOnboarding.selfTest(), sounds = TomoSounds.selfTest()
            exit(growth && sync && look && island && firstRun && sounds ? 0 : 1)
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
        if let dir = ProcessInfo.processInfo.environment["TOMO_RENDER_EVOLUTION"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            write(evolutionSheet, to: URL(fileURLWithPath: dir).appendingPathComponent("tomo-evolution.png"))
            NSApp.terminate(nil)
        }
        if let dir = ProcessInfo.processInfo.environment["TOMO_RENDER_VARIETY"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            write(varietySheet, to: URL(fileURLWithPath: dir).appendingPathComponent("tomo-variety.png"))
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

    /// The Tomo these renders show: TOMO_SEED=<text> for a learner-style Tomo, otherwise the mascot.
    private static var look: TomoLook {
        ProcessInfo.processInfo.environment["TOMO_SEED"].map { TomoLook(seed: $0) } ?? .mascot
    }

    /// The mascot drawn by the same engine as the notch, at rest, looking straight ahead.
    private static func tomo(size: CGFloat, grow: CGFloat) -> some View {
        let blob = TomoBlob(look: .mascot)
        blob.setGrowth(grow)
        return Canvas { ctx, sz in
            blob.draw(ctx, size: sz)
        }
        .frame(width: size, height: size)
    }

    /// TOMO_RENDER_ANIM=<dir>: a scripted 16-second scene, rendered frame by frame on a scripted clock
    /// (frame-0000.png … at 20 fps), for checking motion. Join them into a GIF with any tool.
    private static func renderAnimation(to out: URL) {
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var t = 0.0
        let blob = TomoBlob(look: look)
        blob.clock = { t }
        blob.particleOverhang = 40
        blob.setGrowth(0)
        let script: [(at: Double, run: (TomoBlob) -> Void)] = [
            (0.8, { $0.talk() }), (1.1, { $0.talk() }), (1.4, { $0.talk() }),
            (2.2, { $0.grow(to: 1) }),                                   // 2さい: its first evolution
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
            while next < script.count && script[next].at <= t { script[next].run(blob); next += 1 }
            blob.lookX = CGFloat(sin(t * 0.9)) * 0.9          // a cursor drifting around
            blob.lookY = CGFloat(cos(t * 0.6)) * 0.5
            blob.step()
            let frame = Canvas { ctx, sz in blob.draw(ctx, size: sz) }
                .frame(width: 240, height: 280)
                .background(Color.black)
            write(frame, to: out.appendingPathComponent(String(format: "frame-%04d.png", i)))
        }
    }

    /// TOMO_RENDER_CARD_FRAMES=<dir>: the ten frames of the mascot's loop on the iPhone's Lock Screen card, for
    /// each age and both moods: <dir>/<ready|sleep>-<0|1|2>/frame-0.png … frame-9.png (240 px, transparent).
    /// One frame shows per second (ios-demo/scripts/make-frame-font.py), so each is a distinct pose and
    /// frame 9 leads back into frame 0.
    private static func renderCardFrames(to out: URL) {
        typealias Beat = (lead: Double, run: (TomoBlob) -> Void)
        let look: (CGFloat, CGFloat) -> (TomoBlob) -> Void = { x, y in { $0.lookX = x; $0.lookY = y } }
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
                let blob = TomoBlob(look: .mascot)
                blob.clock = { t }
                blob.setGrowth(CGFloat(growth))
                blob.step()
                blob.setState(mood, force: true)
                // Run a few seconds first so the z's are already drifting, then one frame per second.
                var events = beats.enumerated().flatMap { k, list in list.map { (at: 104 + Double(k) - $0.lead, run: $0.run) } }
                    .sorted { $0.at < $1.at }
                for k in 0..<10 {
                    let shot = 104 + Double(k)
                    while t < shot {
                        t = min(shot, t + 1.0 / 60)
                        while let e = events.first, e.at <= t { e.run(blob); events.removeFirst() }
                        blob.step()
                    }
                    // Tomo a little smaller and lower than the frame, so hops and the "?" stay inside it.
                    let frame = Canvas { ctx, _ in
                        var c = ctx
                        c.translateBy(x: 24, y: 40)
                        blob.draw(c, size: CGSize(width: 192, height: 192))
                    }.frame(width: 240, height: 240)
                    write(frame, to: dir.appendingPathComponent("frame-\(k).png"))
                }
            }
        }
    }

    /// TOMO_RENDER_SHEET=<dir>: one Tomo at every age and with every face, then a crowd of other Tomos, on one
    /// image for reviewing the character. TOMO_SEED picks the Tomo (the mascot otherwise).
    private static var sheet: some View {
        func cell(_ label: String, growth: CGFloat = 1, look l: TomoLook = look, _ setup: (TomoBlob) -> Void = { _ in }) -> some View {
            let blob = TomoBlob(look: l)
            blob.setGrowth(growth)
            setup(blob)
            return VStack(spacing: 4) {
                Canvas { ctx, sz in blob.draw(ctx, size: sz) }.frame(width: 180, height: 180)
                Text(label).font(.system(size: 16, weight: .medium)).foregroundColor(.white.opacity(0.7))
            }
        }
        let ages = ["1さい", "2さい", "3さい", "4さい", "5さい", "6さい"]  // text-ok: debug sheet labels
        let crowd = (0..<24).map { TomoLook(seed: "sheet-\($0)") }
        let rows: [[AnyView]] = [
            (0..<6).map { AnyView(cell(ages[$0], growth: CGFloat($0))) },
            [AnyView(cell("look") { $0.lookX = 0.8; $0.lookY = -0.6; for _ in 0..<40 { $0.step() } }),
             AnyView(cell("right") { $0.setState(.finished) }),
             AnyView(cell("wrong") { $0.setState(.error) }),
             AnyView(cell("huh?") { $0.setState(.question); for _ in 0..<60 { $0.step() } }),
             AnyView(cell("asleep") { $0.setState(.sleeping) }),
             AnyView(cell("talk") { $0.talk(); $0.step() })],
            [AnyView(cell("love") { $0.emote(.love) }),
             AnyView(cell("surprised") { $0.emote(.surprised) }),
             AnyView(cell("yawn", growth: 0) { $0.emote(.yawn) }),
             AnyView(cell("wink", growth: 2) { $0.emote(.wink) }),
             AnyView(cell("annoyed") { $0.emote(.annoyed) }),
             AnyView(cell("dizzy") { $0.setState(.dizzy) })],
        ] + (0..<4).map { r in
            (r * 6..<r * 6 + 6).map { AnyView(cell(crowd[$0].form(3).silhouette.rawValue, growth: 3, look: crowd[$0])) }
        } + [
            (0..<6).map { AnyView(cell(crowd[0].form($0).silhouette.rawValue, growth: CGFloat($0), look: crowd[0])) },
        ]
        return VStack(spacing: 10) {
            ForEach(0..<rows.count, id: \.self) { r in
                HStack(spacing: 10) { ForEach(0..<rows[r].count, id: \.self) { rows[r][$0] } }
            }
        }
        .padding(20)
        .background(Color.black)
    }

    /// TOMO_RENDER_EVOLUTION=<dir>: eight Tomos, one per row, at every age from left to right.
    private static var evolutionSheet: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(0..<8, id: \.self) { i in
                HStack(spacing: 6) {
                    ForEach(0..<TomoLook.ages, id: \.self) { age in
                        let blob = TomoBlob(look: TomoLook(seed: "variety-\(i)"))
                        let _ = blob.setGrowth(CGFloat(age))
                        Canvas { ctx, sz in blob.draw(ctx, size: sz) }.frame(width: 150, height: 150)
                    }
                }
            }
        }
        .padding(20)
        .background(Color.black)
    }

    /// TOMO_RENDER_VARIETY=<dir>: the same eight seeds at several `TomoLook.variety` settings, one row each.
    private static var varietySheet: some View {
        let levels = [0.25, 0.5, 0.75, 1, 1.25, 1.5]
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(levels, id: \.self) { v in
                HStack(spacing: 6) {
                    Text(String(format: "%.2f", v)).font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(v == 1 ? 1 : 0.6)).frame(width: 70)
                    ForEach(0..<8, id: \.self) { i in
                        let blob = TomoBlob(look: TomoLook(seed: "variety-\(i)", variety: v))
                        let _ = blob.setGrowth(3)
                        Canvas { ctx, sz in blob.draw(ctx, size: sz) }.frame(width: 150, height: 150)
                    }
                }
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
