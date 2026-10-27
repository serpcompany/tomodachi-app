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
// Every render here draws a TomoBlob of its own, which never follows this Mac's Reduce Motion, so the renders are the
// same on any Mac. TOMO_REDUCE_MOTION=1 turns it on for TOMO_RENDER_ANIM and the sheet (`TomoMotion.forced`), never
// for TOMO_RENDER_CARD_FRAMES: widgets and the Live Activity play their frames regardless.
// The icons and the card frames ship as files, so they're the classic material whatever happens to the learner's Tomo;
// the renders that check Tomo's look and motion use the learner's own (`TomoMaterial.forRenders`, TOMO_MATERIAL).

@MainActor
enum TomoIconRenderer {
    private static var checkResult: Bool?

    static func renderIfRequested() {
        if ProcessInfo.processInfo.environment["TOMO_SELFTEST"] != nil {   // growth, store, sync, looks, island, window, first run, reminders, sounds, pairs
            let growth = TomoProgress.selfTest(), sync = TomoSync.selfTest(), look = TomoLook.selfTest()
            let island = TomoIslandSelfTest.run(), window = TomoCheck.run(TomoAppWindow.selfTest)
            let firstRun = TomoOnboarding.selfTest(), reminders = TomoReminders.selfTest(), sounds = TomoSounds.selfTest()
            let pairs = TomoLanguages.selfTest()
            exit(growth && sync && look && island && window && firstRun && reminders && sounds && pairs ? 0 : 1)
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
        if let dir = ProcessInfo.processInfo.environment["TOMO_RENDER_EVOLUTION"] {   // and the birthday's morph (#259)
            let folder = URL(fileURLWithPath: dir)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            write(evolutionSheet, to: folder.appendingPathComponent("tomo-evolution.png"))
            write(morphSheet(calm: false), to: folder.appendingPathComponent("tomo-morphs.png"))
            write(morphSheet(calm: true), to: folder.appendingPathComponent("tomo-morphs-calm.png"))
            for seed in TomoFormMorph.seeds {
                write(pairSheet(seed), to: folder.appendingPathComponent("tomo-morph-pairs-\(seed).png"))
            }
            let survey = TomoFormMorph.surveyReport()
            print(TomoCheck.line(survey.passed, survey.words))
            exit(survey.passed ? 0 : 1)
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
        if let dir = ProcessInfo.processInfo.environment["TOMO_RENDER_FEELINGS"] {
            renderFeelings(to: URL(fileURLWithPath: dir))
            NSApp.terminate(nil)
        }
        if let dir = ProcessInfo.processInfo.environment["TOMO_RENDER_MOSS_EGG"] {   // mossy, the egg and the hatch (#258)
            renderMossAndEgg(to: URL(fileURLWithPath: dir))
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

    /// The mascot drawn by the same engine as the notch, at rest, looking straight ahead, in the classic material.
    private static func tomo(size: CGFloat, grow: CGFloat) -> some View {
        let blob = TomoBlob(look: .mascot, material: .classic)
        blob.setGrowth(grow)
        return Canvas { ctx, sz in
            blob.draw(ctx, size: sz)
        }
        .frame(width: size, height: size)
    }

    /// TOMO_RENDER_ANIM=<dir>: a scripted 44-second scene, rendered frame by frame on a scripted clock
    /// (frame-0000.png … at 20 fps), for checking motion. Join them into a GIF with any tool. Its big moments: a drip in
    /// at 0 s (0.75 s long, from a notch at the frame's top), birthdays at 2.2 s (2.6 s long) and 13.4 s, a level-up at
    /// 17.6 s (2.1 s long), the call glow from 20 s to 23 s, a pull up at 23.5 s (0.45 s long), a drip in at 24.2 s,
    /// the hello at 25.2 s (1.8 s long), and small Tomo's badges from 27.6 s: "…" while it checks an answer, then a Zz as
    /// it dozes off (from about 30.6 s), with Tomo drawn as the resting island draws it, 3 times as big; then the
    /// season's weather, as in the card: snow from 32 s, petals from 34 s; then dancing to music: Tomo's own bounce from
    /// 36 s, the 盆踊り from 40 s. The level-up bursts sparkle dust, and the birthdays toss confetti. TOMO_MATERIAL picks the material (the learner's own otherwise).
    private static func renderAnimation(to out: URL) {
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var t = 0.0
        let blob = TomoBlob(look: look, material: .forRenders)
        blob.reduceMotion = TomoMotion.forced
        blob.clock = { t }
        blob.particleOverhang = 40
        blob.strandAnchor = CGPoint(x: 120, y: 0)
        blob.setGrowth(0)
        let script: [(at: Double, run: (TomoBlob) -> Void)] = [
            (0, { $0.dripIn() }),
            (0.8, { $0.talk() }), (1.1, { $0.talk() }), (1.4, { $0.talk() }),
            (2.2, { $0.grow(to: 1) }),                                   // 2さい: its first evolution
            (5.0, { $0.setState(.question) }),
            (6.0, { $0.setState(.finished) }), (7.0, { $0.setState(.idle) }),
            (7.4, { $0.setState(.error) }), (8.2, { $0.setState(.idle) }),
            (9.6, { $0.emote(.love) }),
            (11.4, { $0.poke() }),
            (12.2, { $0.nudge() }),
            (13.4, { $0.grow(to: 2) }),                                  // 3さい
            (16.2, { $0.emote(.yawn) }),
            (17.6, { $0.setState(.finished); $0.emote(.proud); $0.levelUp() }),   // a level-up (TomoGame.celebrate)
            (19.8, { $0.setState(.idle) }),
            (20.0, { $0.callGlow = 1 }), (23.0, { $0.callGlow = 0 }),        // something counts, then it doesn't
            (23.5, { $0.pullUp() }),
            (24.2, { $0.dripIn() }),
            (25.2, { $0.hello() }),                                      // the app starting, or the Mac waking
            (27.6, { $0.showsBadges = true; $0.setState(.thinking) }),   // badges, as small Tomo wears them
            (29.6, { $0.setState(.idle); $0.dozeAfter = 1 }),
            (32.0, { $0.showsBadges = false; $0.dozeAfter = 45; $0.weather = .snow; $0.emote(.happy) }),   // the card
            (34.0, { $0.weather = .petals }),
            (36.0, { $0.weather = nil; $0.dance = .bounce }),                 // music playing
            (40.0, { $0.dance = .bonOdori }),                                 // during お盆
        ]
        var next = 0
        let fps = 20.0
        for i in 0..<Int(fps * 44) {
            t = Double(i) / fps
            while next < script.count && script[next].at <= t { script[next].run(blob); next += 1 }
            if t < 29.6 {                                      // a cursor drifting around, then still, so Tomo dozes
                blob.lookX = CGFloat(sin(t * 0.9)) * 0.9
                blob.lookY = CGFloat(cos(t * 0.6)) * 0.5
            }
            let small = t >= 27.6 && t < 32                    // the resting island's Tomo (BotPlacement), magnified
            blob.particleOverhang = small ? 72 : 40
            blob.step()
            let frame = Canvas { ctx, sz in
                guard small else { blob.draw(ctx, size: sz); return }
                var c = ctx
                c.translateBy(x: 50, y: -109)
                c.scaleBy(x: 3, y: 3)
                blob.draw(c, size: CGSize(width: 20 / 0.6, height: 20 / 0.6 + 72))
            }
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
                // Reduce Motion off, even with the flag, and classic: these are the shipped frames.
                let blob = TomoBlob(look: .mascot, material: .classic)
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
    /// image for reviewing the character. TOMO_SEED picks the Tomo (the mascot otherwise), TOMO_MATERIAL its material (the
    /// learner's own otherwise). A big moment's cell is that many seconds into its script.
    private static var sheet: some View {
        func moment(_ seconds: Double, _ start: @escaping (TomoBlob) -> Void) -> (TomoBlob) -> Void {
            { blob in
                var t = 100.0
                blob.clock = { t }
                blob.step()
                start(blob)
                while t < 100 + seconds { t = min(100 + seconds, t + 1.0 / 60); blob.step() }
            }
        }
        func cell(_ label: String, growth: CGFloat = 1, look l: TomoLook = look, _ setup: (TomoBlob) -> Void = { _ in }) -> some View {
            let blob = TomoBlob(look: l, material: .forRenders)
            blob.reduceMotion = TomoMotion.forced
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
             AnyView(cell("dizzy") { $0.setState(.dizzy) }),
             AnyView(cell("level up", moment(1.0) { $0.levelUp() })),     // landing, star-eyed
             AnyView(cell("birthday", moment(0.8) { $0.grow(to: 2) }))],
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

    /// TOMO_RENDER_EVOLUTION=<dir>: eight Tomos, one per row, at every age from left to right (tomo-evolution.png). The
    /// same run renders their birthdays' morphs (`morphSheet`, `pairSheet`) and prints the morph survey for all eight
    /// (`TomoFormMorph.surveyReport`), exiting 1 if a morph tangles, flips or spins.
    private static var evolutionSheet: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(0..<8, id: \.self) { i in
                HStack(spacing: 6) {
                    ForEach(0..<TomoLook.ages, id: \.self) { age in
                        let blob = TomoBlob(look: TomoLook(seed: "variety-\(i)"), material: .forRenders)
                        let _ = blob.setGrowth(CGFloat(age))
                        Canvas { ctx, sz in blob.draw(ctx, size: sz) }.frame(width: 150, height: 150)
                    }
                }
            }
        }
        .padding(20)
        .background(Color.black)
    }

    /// TOMO_RENDER_EVOLUTION's birthdays (tomo-morphs.png; `calm`, Reduce Motion's crossfade: tomo-morphs-calm.png): the
    /// same eight Tomos, one per row, each a year older (1さい into 2さい on the first row, on to 6さい, and round again),
    /// at moments through the birthday from left to right, on a scripted clock.
    private static func morphSheet(calm: Bool) -> some View {
        let moments = calm ? [0, 0.1, 0.2, 0.3, 0.45, 0.6, 0.75, 0.9, 1.4] : [0, 0.05, 0.1, 0.2, 0.3, 0.4, 0.6, 0.9, 1.4]
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Color.clear.frame(width: 50, height: 20)
                ForEach(moments, id: \.self) { e in label(String(format: "%.2f s", e)).frame(width: 150) }
            }
            ForEach(0..<TomoFormMorph.seeds.count, id: \.self) { i in
                let age = 1 + i % (TomoLook.ages - 1)
                HStack(spacing: 6) {
                    label("\(age)→\(age + 1)").frame(width: 50)
                    ForEach(moments, id: \.self) { e in
                        let blob = birthday(TomoFormMorph.seeds[i], into: age, at: e, calm: calm)
                        Canvas { ctx, sz in blob.draw(ctx, size: sz) }.frame(width: 150, height: 150)
                    }
                }
            }
        }
        .padding(20)
        .background(Color.black)
    }

    /// `seed`'s Tomo `e` seconds into its birthday into `age` (0 is 1さい), 60 frames a second on a scripted clock.
    private static func birthday(_ seed: String, into age: Int, at e: Double, calm: Bool) -> TomoBlob {
        let blob = TomoBlob(look: TomoLook(seed: seed), material: .forRenders)
        blob.reduceMotion = calm
        var t = 100.0
        blob.clock = { t }
        blob.step()
        blob.setGrowth(CGFloat(age - 1))
        blob.grow(to: CGFloat(age))
        while t < 100 + e { t = min(100 + e, t + 1.0 / 60); blob.step() }
        return blob
    }

    /// TOMO_RENDER_EVOLUTION's outlines (tomo-morph-pairs-<seed>.png): `seed`'s every silhouette (rows) morphing into
    /// every silhouette (columns). Each cell has the old outline (grey), the new one (white), the outline half way
    /// (filled), and at the spring's most overshoot (gold), with every eighth point's path from old to new (spokes that
    /// cross, or swing far round, would show a twist) and the first point on each (red, green). A cell framed red isn't
    /// sound (`TomoMorph.Health`).
    private static func pairSheet(_ seed: String) -> some View {
        let shapes = TomoFormMorph.silhouettes.map { $0.0 }, side: CGFloat = 112
        return VStack(alignment: .leading, spacing: 4) {
            label(seed)
            HStack(spacing: 4) {
                Color.clear.frame(width: 70, height: 20)
                ForEach(shapes, id: \.self) { b in label(b.rawValue).frame(width: side) }
            }
            ForEach(shapes, id: \.self) { a in
                HStack(spacing: 4) {
                    label(a.rawValue).frame(width: 70)
                    ForEach(shapes, id: \.self) { b in
                        let morph = TomoFormMorph.pair(seed, a, b), sound = morph.health().sound
                        Canvas { ctx, sz in drawPair(ctx, morph, size: sz) }
                            .frame(width: side, height: side)
                            .border(sound ? Color.white.opacity(0.12) : Color.red, width: sound ? 1 : 3)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.black)
    }

    private static func drawPair(_ ctx: GraphicsContext, _ m: TomoFormMorph, size: CGSize) {
        let R = size.width * 0.28, o = m.outline
        let peak = (0...120).map { TomoFormMorph.flubber(1.2 * Double($0) / 120, length: 1.2).u }.max() ?? 1
        var c = ctx
        c.translateBy(x: size.width / 2, y: size.height / 2 + R * 0.12)
        func path(_ points: [CGPoint]) -> Path { TomoMorph.path(points.map { CGPoint(x: $0.x * R, y: $0.y * R) }) }
        c.fill(path(o.points(at: 0.5)), with: .color(.white.opacity(0.14)))
        c.stroke(path(o.from), with: .color(.white.opacity(0.45)), lineWidth: 1)
        c.stroke(path(o.points(at: peak)), with: .color(Color(hex: "#FFC53A").opacity(0.8)),
                 style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        c.stroke(path(o.to), with: .color(.white), lineWidth: 1.5)
        var spokes = Path()
        for i in stride(from: 0, to: o.from.count, by: 8) {
            spokes.move(to: CGPoint(x: o.from[i].x * R, y: o.from[i].y * R))
            spokes.addLine(to: CGPoint(x: o.to[i].x * R, y: o.to[i].y * R))
        }
        c.stroke(spokes, with: .color(Color(hex: "#7FD3FF").opacity(0.7)), lineWidth: 0.75)
        for (p, color) in [(o.from[0], Color.red), (o.to[0], Color.green)] {
            c.fill(Path(ellipseIn: CGRect(x: p.x * R - 2.5, y: p.y * R - 2.5, width: 5, height: 5)), with: .color(color))
        }
    }

    private static func label(_ text: String) -> some View {
        Text(text).font(.system(size: 13, weight: .medium)).foregroundColor(.white.opacity(0.7))
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
                        let blob = TomoBlob(look: TomoLook(seed: "variety-\(i)", variety: v), material: .forRenders)
                        let _ = blob.setGrowth(3)
                        Canvas { ctx, sz in blob.draw(ctx, size: sz) }.frame(width: 150, height: 150)
                    }
                }
            }
        }
        .padding(20)
        .background(Color.black)
    }

    /// TOMO_RENDER_FEELINGS=<dir> (#257, #258): Tomo well, droopy, sickly and mossy (`TomoBlob.feeling`).
    ///   <dir>/tomo-feelings.png  one row each for well, droopy, sickly and mossy: a Tomo of each of the 10 silhouettes,
    ///                            then one with ears at every age, then one with each topper
    ///   <dir>/frames/frame-0000.png …  a 40-second scene at 10 fps on a scripted clock: well, droopy from 1 s, sickly
    ///                            from 22 s, well again from 34 s (its happy hop), a Tomo with ears (TOMO_SEED picks
    ///                            another) at 3さい
    /// TOMO_REDUCE_MOTION=1 draws both under Reduce Motion.
    private static func renderFeelings(to out: URL) {
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        write(feelingSheet, to: out.appendingPathComponent("tomo-feelings.png"))
        let frames = out.appendingPathComponent("frames")
        try? FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        var t = 0.0
        let blob = TomoBlob(look: ProcessInfo.processInfo.environment["TOMO_SEED"].map { TomoLook(seed: $0) }
                                ?? feelingLook({ $0.topper == .bunny }), material: .forRenders)
        blob.reduceMotion = TomoMotion.forced
        blob.clock = { t }
        blob.particleOverhang = 40
        blob.setGrowth(2)
        let script: [(at: Double, feeling: TomoFeeling?)] = [(1, .droopy), (22, .sickly), (34, nil)]
        var next = 0
        let fps = 10.0
        for i in 0..<Int(fps * 40) {
            let shot = Double(i) / fps
            repeat {                                            // stepped at 60 Hz between frames, as the notch is
                t = min(shot, t + 1.0 / 60)
                while next < script.count && script[next].at <= t { blob.feeling = script[next].feeling; next += 1 }
                blob.step()
            } while t < shot
            let frame = Canvas { ctx, sz in blob.draw(ctx, size: sz) }
                .frame(width: 240, height: 280)
                .background(Color.black)
            write(frame, to: frames.appendingPathComponent(String(format: "frame-%04d.png", i)))
        }
    }

    /// The first of the feeling renders' seeds whose Tomo matches.
    private static func feelingLook(_ matches: (TomoLook) -> Bool) -> TomoLook {
        (0..<4000).lazy.map { TomoLook(seed: "feelings-\($0)") }.first(where: matches) ?? .mascot
    }

    private static var feelingSheet: some View {
        func cell(_ l: TomoLook, age: Int, _ feeling: TomoFeeling?, _ label: String) -> some View {
            var t = 100.0
            let blob = TomoBlob(look: l, material: .forRenders)
            blob.reduceMotion = TomoMotion.forced
            blob.clock = { t }
            blob.feeling = feeling                              // shown from its first frame
            blob.setGrowth(CGFloat(age))
            blob.step()
            while t < 101.2 { t += 1.0 / 60; blob.step() }      // its gaze settled, before its first blink or fidget
            return VStack(spacing: 2) {
                Canvas { ctx, sz in blob.draw(ctx, size: sz) }.frame(width: 140, height: 140)
                Text(label).font(.system(size: 13, weight: .medium)).foregroundColor(.white.opacity(0.6))
            }
        }
        let shapes: [TomoForm.Silhouette] = [.round, .organic, .boxy, .capsule, .nub, .cloud, .droplet, .hexagon, .sun, .triangle]
        let toppers: [(TomoLook.Topper, String)] = [(.cat, "cat"), (.bunny, "bunny"), (.bear, "bear"), (.horns, "horns"),
                                                    (.antenna, "antenna"), (.sprout, "sprout")]
        let bySilhouette = shapes.map { s in feelingLook { $0.form(3).silhouette == s } }
        let eared = feelingLook { $0.topper == .bunny }
        let byTopper = toppers.map { tp in feelingLook { $0.topper == tp.0 } }
        let ages = ["1さい", "2さい", "3さい", "4さい", "5さい", "6さい"]  // text-ok: debug sheet labels
        func block(_ feeling: TomoFeeling?) -> some View {
            HStack(alignment: .top, spacing: 6) {
                Text(feeling?.rawValue ?? "well").font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.white).frame(width: 90, height: 140)
                ForEach(0..<shapes.count, id: \.self) { cell(bySilhouette[$0], age: 3, feeling, shapes[$0].rawValue) }
                Color.clear.frame(width: 20, height: 1)
                ForEach(0..<TomoLook.ages, id: \.self) { cell(eared, age: $0, feeling, ages[$0]) }
                Color.clear.frame(width: 20, height: 1)
                ForEach(0..<toppers.count, id: \.self) { cell(byTopper[$0], age: 3, feeling, toppers[$0].1) }
            }
        }
        return VStack(alignment: .leading, spacing: 12) {
            block(nil)
            block(.droopy)
            block(.sickly)
            block(.mossy)
        }
        .padding(20)
        .background(Color.black)
    }

    /// TOMO_RENDER_MOSS_EGG=<dir> (#258): mossy, back into its egg and the hatch, on a scripted clock.
    ///   <dir>/tomo-moss-egg.png  the eight render seeds at 3さい, one per row: well, mossy (grown over), brushing the moss
    ///                            off, going into its egg, resting in it, peeking out, cracking, hatching, and out again
    ///   <dir>/tomo-moss-egg-calm.png  the same under Reduce Motion
    ///   <dir>/frames/frame-0000.png …  a 30-second scene at 10 fps: mossy from 1 s, well again from 9 s (the brush-off),
    ///                            sickly from 13 s, into its egg at 15 s, a poke at 19 s, the hatch at 23 s (sickly still),
    ///                            well from 27 s; a Tomo with ears (TOMO_SEED picks another) at 3さい, TOMO_REDUCE_MOTION=1
    ///                            for Reduce Motion
    /// Tomo says the target pack's hello as it hatches.
    private static func renderMossAndEgg(to out: URL) {
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        write(mossEggSheet(calm: false), to: out.appendingPathComponent("tomo-moss-egg.png"))
        write(mossEggSheet(calm: true), to: out.appendingPathComponent("tomo-moss-egg-calm.png"))
        let frames = out.appendingPathComponent("frames")
        try? FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        var t = 0.0
        let blob = TomoBlob(look: ProcessInfo.processInfo.environment["TOMO_SEED"].map { TomoLook(seed: $0) }
                                ?? feelingLook({ $0.topper == .bunny }), material: .forRenders)
        blob.reduceMotion = TomoMotion.forced
        blob.clock = { t }
        blob.particleOverhang = 40
        blob.dozeAfter = 1e9
        blob.hatchWord = TomoLanguages.shared.target.lines.hello?.say
        blob.setGrowth(2)
        let script: [(at: Double, run: (TomoBlob) -> Void)] = [
            (1, { $0.feeling = .mossy }), (9, { $0.feeling = nil }), (13, { $0.feeling = .sickly }),
            (15, { $0.inEgg = true }), (19, { $0.poke() }), (23, { $0.inEgg = false }), (27, { $0.feeling = nil }),
        ]
        var next = 0
        let fps = 10.0
        for i in 0..<Int(fps * 30) {
            let shot = Double(i) / fps
            repeat {                                            // stepped at 60 Hz between frames, as the notch is
                t = min(shot, t + 1.0 / 60)
                while next < script.count && script[next].at <= t { script[next].run(blob); next += 1 }
                blob.step()
            } while t < shot
            let frame = Canvas { ctx, sz in blob.draw(ctx, size: sz) }
                .frame(width: 240, height: 280)
                .background(Color.black)
            write(frame, to: frames.appendingPathComponent(String(format: "frame-%04d.png", i)))
        }
    }

    /// `look`'s Tomo at 3さい after `script` (seconds from its first frame) has played for `until` seconds, stepped at
    /// 60 Hz on a scripted clock, never dozing off.
    private static func scene(_ look: TomoLook, calm: Bool, _ script: [(at: Double, run: (TomoBlob) -> Void)],
                              until: Double) -> TomoBlob {
        let blob = TomoBlob(look: look, material: .forRenders)
        blob.reduceMotion = calm
        var t = 100.0
        blob.clock = { t }
        blob.dozeAfter = 1e9
        blob.hatchWord = TomoLanguages.shared.target.lines.hello?.say
        blob.setGrowth(2)
        blob.step()
        var next = 0
        while t < 100 + until {
            t = min(100 + until, t + 1.0 / 60)
            while next < script.count && 100 + script[next].at <= t { script[next].run(blob); next += 1 }
            blob.step()
        }
        return blob
    }

    private static func mossEggSheet(calm: Bool) -> some View {
        let mossy: (at: Double, run: (TomoBlob) -> Void) = (0.1, { $0.feeling = .mossy })
        let into: (at: Double, run: (TomoBlob) -> Void) = (0.1, { $0.inEgg = true })
        let hatch: (at: Double, run: (TomoBlob) -> Void) = (4, { $0.inEgg = false })
        let closed = calm ? 0.9 : 2.4                           // the script into its egg, before its first peek
        let columns: [(String, [(at: Double, run: (TomoBlob) -> Void)], Double)] = [
            ("well", [], 1.2),
            ("mossy", [mossy], 9),
            ("brushing", [mossy, (9, { $0.feeling = nil })], 9.3),
            ("into its egg", [into], calm ? 0.55 : 1.3),
            ("in its egg", [into], 0.1 + closed + 1),
            ("peeking", [into, (3.5, { $0.poke() })], 3.5 + 0.12 + 0.85),
            (calm ? "hatching" : "cracking", [into, hatch], calm ? 4.25 : 4.6),
            (calm ? "saying hello" : "hatching", [into, hatch], calm ? 4.7 : 5.25),
            ("out again", [into, hatch], 8),
        ]
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Color.clear.frame(width: 90, height: 20)
                ForEach(0..<columns.count, id: \.self) { label(columns[$0].0).frame(width: 150) }
            }
            ForEach(0..<8, id: \.self) { i in
                HStack(spacing: 6) {
                    label("variety-\(i)").frame(width: 90)
                    ForEach(0..<columns.count, id: \.self) { c in
                        let blob = scene(TomoLook(seed: "variety-\(i)"), calm: calm, columns[c].1, until: columns[c].2)
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
