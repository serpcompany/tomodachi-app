import SwiftUI

// MARK: - The first run's screens (TomoOnboarding.swift has the flow and who sees it)
//
// A portrait page like the reference app's (#83): Tomo at the top, a short title and text, the action at the
// bottom. One Tomo stays on screen the whole way and moves between steps (it never re-appears from nothing);
// the egg it hatches from is drawn and animated live too (TomoEggView). Shared by every shell: the Mac shows it in
// a window, and the iPhone full screen, with its own steps (TomoOnboardingPhone.swift), sized down on short screens
// (`fit`). All text comes from ui.<id>.json and the target pack.

public struct TomoOnboardingView: View {
    @ObservedObject var model: TomoOnboarding
    @ObservedObject var game = TomoGame.shared
    @ObservedObject var lang = TomoLanguages.shared
    var gaze: (() -> CGPoint)?
    /// iPhone: how much of the full size fits the screen's height (1 on the Mac's fixed window).
    @State var fit: CGFloat = 1

    /// `gaze`: where the pointer is relative to Tomo, −1…1 (positive y = above), for shells that know.
    public init(model: TomoOnboarding, gaze: (() -> CGPoint)? = nil) {
        self.model = model
        self.gaze = gaze
    }

    /// How long a step's page takes to fade out, and the next one to fade in, which starts only then.
    /// TOMO_SLOW_MOTION=<n> (snapshots) makes both n times longer.
    static let pageOut: Double = 0.15 * slowMotion
    static let pageIn: Double = 0.25 * slowMotion
    private static let slowMotion = max(1, ProcessInfo.processInfo.environment["TOMO_SLOW_MOTION"].flatMap(Double.init) ?? 1)

    var step: TomoOnboarding.Step { model.step }
    var isPhone: Bool { model.shell == .phone }

    public var body: some View {
        // Sized from the space offered, never from what the steps hold (GeometryReader: no layout loop).
        GeometryReader { geo in
            VStack(spacing: 0) {
                dots.frame(height: 22)
                hero
                    .frame(height: heroHeight * fit)
                    .padding(.top, 10)
                // One step's text at a time: the old page fades out before the new one fades in, so the two never
                // show at once. Tomo, in the hero, moves on its own meanwhile.
                ZStack(alignment: .top) {
                    page.id(step).transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 12))
                            .animation(.easeOut(duration: Self.pageIn).delay(Self.pageOut)),
                        removal: .opacity.animation(.easeIn(duration: Self.pageOut))))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 14)
                buttons
            }
            .padding(.horizontal, isPhone ? Self.phonePadding : 28)
            .padding(.top, 10)
            .padding(.bottom, isPhone ? 12 : 22)
            .frame(width: geo.size.width, height: geo.size.height)
            .onChange(of: geo.size.height, initial: true) { _, h in
                // Tomo and the sketches fill the height there is: about 1.2 on an iPhone 17 (780 pt inside the safe
                // area), 0.87 on an SE (647 pt).
                fit = isPhone ? 0.7 + 0.5 * min(max((h - 580) / 200, 0), 1) : 1
            }
        }
        .foregroundStyle(Paint.text)
        .background(background.ignoresSafeArea())
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: step)
        .animation(.easeInOut(duration: 0.3), value: model.phase)
        .onAppear { model.begin() }
    }

    // MARK: Tomo, the egg, the notch

    private var heroHeight: CGFloat {
        switch step {
        case .hatch, .welcomeBack: 236
        case .round, .result: 150
        case .visits: isPhone ? PhoneSketches.notificationHero : 132
        case .rhythm: isPhone ? 64 : 96
        case .quiet, .notify, .login: 120
        case .widget: PhoneSketches.phoneHero
        case .lockScreen: PhoneSketches.cardHero
        case .ready: 116
        }
    }

    private var tomoSize: CGFloat {
        switch step {
        case .hatch, .welcomeBack: 220
        case .round, .result: 150
        case .visits: isPhone ? PhoneSketches.notificationTomo : 58
        case .rhythm: isPhone ? 64 : 96
        case .quiet: 104
        case .notify, .login: 100
        case .widget: 76
        case .lockScreen: PhoneSketches.cardTomo
        case .ready: 116
        }
    }

    /// Where Tomo sits in the hero, from its centre: by the notch (Mac), or in a sketch of the iPhone's screens.
    private func tomoOffset(in size: CGSize) -> CGSize {
        switch step {
        case .visits where !isPhone:
            CGSize(width: NotchSketch.notch.width / 2 + 30, height: -size.height / 2 + NotchSketch.notch.height / 2 + 2)
        case .visits: PhoneSketches.notificationSlot(width: size.width, fit: fit)
        case .widget: PhoneSketches.besidePhone(fit: fit)
        case .lockScreen: PhoneSketches.cardSlot(width: size.width, fit: fit)
        default: .zero
        }
    }

    private var hero: some View {
        GeometryReader { geo in
            ZStack {
                if step == .visits && !isPhone {
                    NotchSketch(invite: lang.target.lines.invite ?? "").transition(.opacity)
                }
                if isPhone || step == .quiet || step == .login { phoneSketch(in: geo.size).transition(.opacity) }
                // The egg stays until its halves have flown off (it draws nothing after); not when opened past it.
                if step == .hatch && model.hatchStarted != .distantPast {
                    TomoEggView(look: TomoLook.current, crackedAt: model.hatchStarted)
                        .frame(width: 220 * fit, height: 236 * fit)
                        .contentShape(Rectangle())
                        .onTapGesture { model.hatch() }
                        .transition(.identity)
                }
                TomoBlobView(state: model.botState, growth: game.growthStep, material: .own, gaze: gaze)
                    .frame(width: tomoSize * fit, height: tomoSize * fit)
                    .scaleEffect(model.hatched ? 1 : 0.2)
                    .opacity(model.hatched ? 1 : 0)
                    .offset(tomoOffset(in: geo.size))
                    .animation(.spring(response: 0.45, dampingFraction: 0.55), value: model.hatched)
                    .onTapGesture { NotificationCenter.default.post(name: .triggerSlap, object: nil) }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: Pages

    @ViewBuilder private var page: some View {
        switch step {
        case .hatch: hatchPage
        case .round: roundPage
        case .result: resultPage
        case .visits: if isPhone { phoneVisitsPage } else { visitsPage }
        case .rhythm: if isPhone { phoneRhythmPage } else { rhythmPage }
        case .quiet: quietPage
        case .notify: notifyPage
        case .login: loginPage
        case .widget: widgetPage
        case .lockScreen: lockScreenPage
        case .ready: readyPage
        case .welcomeBack: welcomeBackPage
        }
    }

    @ViewBuilder private var hatchPage: some View {
        if model.hatched {
            VStack(alignment: .leading, spacing: 12) {
                if let line = lang.target.lines.hello { spoken(line) }
                title("onboarding.hello.title")
                bodyText(ui("onboarding.hello.body", ["age": game.age]))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                eyebrow(ui("onboarding.hatch.eyebrow"))
                title("onboarding.hatch.title")
                bodyText(ui("onboarding.hatch.body", ["language": lang.targetName]))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var roundPage: some View {
        if let r = model.round {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    Text(r.say)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Button { model.replay() } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.1), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(lang.target.labels.again)
                }
                .frame(height: 44)
                ZStack {
                    if model.phase == .right {
                        answerLine(r).transition(.opacity)
                    } else {
                        coach(r).transition(.opacity)
                    }
                }
                .frame(height: 96)
                choices(r)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var resultPage: some View {
        VStack(spacing: 12) {
            if let r = model.round { answerLine(r) }
            title("onboarding.result.title", ["language": lang.targetName])
                .multilineTextAlignment(.center)
            Text(ui("onboarding.result.sub"))
                .font(.system(size: 14)).foregroundStyle(Paint.soft)
            panel(icon: "arrow.triangle.2.circlepath", title: ui("onboarding.result.stick.title"), text: stickText)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    private var stickText: String {
        guard let r = model.round else { return ui("onboarding.result.stick.later") }
        let word = TomoWords.bare(r.say)
        guard let back = model.comesBack else { return ui("onboarding.result.stick.later", ["word": word]) }
        let f = DateFormatter()
        f.locale = tomoClockLocale(lang.learner.id)
        f.timeStyle = .short
        return ui("onboarding.result.stick.body", ["word": word, "time": f.string(from: back)])
    }

    private var visitsPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            title("onboarding.visits.title")
            bodyText(ui("onboarding.visits.body"))
            VStack(alignment: .leading, spacing: 10) {
                row(icon: "keyboard", ui("onboarding.visits.typing"))
                row(icon: "cursorarrow.click.2", ui("onboarding.visits.click"))
                row(icon: "moon.zzz.fill", ui("onboarding.visits.ignore"))
                row(icon: "dock.rectangle", ui("onboarding.visits.dock"))
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rhythmPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            title("onboarding.rhythm.title")
            bodyText(ui("onboarding.rhythm.body"))
            VStack(spacing: 7) {
                ForEach(DropIn.choices.indices, id: \.self) { i in
                    let c = DropIn.choices[i]
                    RhythmRow(title: ui(c.key), tag: ui("onboarding.rhythm." + (c.key.split(separator: ".").last.map(String.init) ?? "")),
                              selected: model.visitEvery == c.seconds) { model.visitEvery = c.seconds }
                }
            }
            .padding(.top, 2)
            Text(ui("onboarding.rhythm.note", ["n": "\(TomoProgress.newPerDay)"]))
                .font(.system(size: 12)).foregroundStyle(Paint.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var readyPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            eyebrow(ui("onboarding.ready.eyebrow", ["age": game.age]))
            title("onboarding.ready.title")
            VStack(alignment: .leading, spacing: 9) {
                ForEach(1...3, id: \.self) { n in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(lang.target.ageLabel(n))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: "#FFD9A8"))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color(hex: "#4A3424"), in: Capsule())
                            .frame(width: 58, alignment: .leading)
                        Text(ui("growth.age.\(n)"))
                            .font(.system(size: 13.5)).foregroundStyle(Paint.soft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            let first = (lang.target.levels.first?.rounds ?? []).prefix(3)
            if !first.isEmpty {
                Text(ui("onboarding.ready.firstWords")).font(.system(size: 11, weight: .bold)).foregroundStyle(Paint.faint)
                    .padding(.top, 4)
                HStack(spacing: 8) {
                    ForEach(Array(first), id: \.id) { r in
                        VStack(spacing: 1) {
                            Text(r.say).font(.system(size: 15, weight: .bold, design: .rounded))
                            Text(r.meaning(lang.learner.id)).font(.system(size: 11)).foregroundStyle(Paint.faint)
                        }
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var welcomeBackPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let line = lang.target.lines.welcomeBack { spoken(line) }
            title("onboarding.back.title")
            bodyText(ui(isPhone ? "onboarding.back.body.phone" : "onboarding.back.body",
                        ["age": game.age, "level": "\(game.level)"]))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: The guided round's parts

    /// The reference's coach mark: what to do, and "Try it now". After a miss: try another.
    private func coach(_ r: TomoRound) -> some View {
        let kind: String = switch r.kind { case .picture: "picture"; case .need: "need"; default: "meaning" }
        let missed = model.outcome == .loss
        return VStack(alignment: .leading, spacing: 5) {
            Text(ui(missed ? "onboarding.round.again.title" : "onboarding.round.coach.\(kind)"))
                .font(.system(size: 15, weight: .bold))
            Text(ui(missed ? "onboarding.round.again.body" : "onboarding.round.coach.body", ["language": lang.targetName]))
                .font(.system(size: 13)).foregroundStyle(Paint.soft)
                .fixedSize(horizontal: false, vertical: true)
            Label(ui("onboarding.round.coach.try"), systemImage: "hand.point.down.fill")
                .font(.system(size: 12, weight: .bold)).foregroundStyle(Paint.accent)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Paint.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(missed ? Paint.red.opacity(0.5) : Color.white.opacity(0.08)))
    }

    /// The word's reading and meaning, with what the answer earned.
    private func answerLine(_ r: TomoRound) -> some View {
        HStack(spacing: 8) {
            if let o = model.outcome { OnboardingBadge(outcome: o) }
            Text([r.romanization, r.meaning].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 15, weight: .medium)).foregroundStyle(Paint.soft)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    @ViewBuilder private func choices(_ r: TomoRound) -> some View {
        if r.kind == .meaning || r.kind == .reply {
            VStack(spacing: 8) {
                ForEach(r.choices) { c in
                    OnboardingChoice(choice: c, phase: model.phase, isAnswer: c.id == r.answer, pill: true) { model.pick(c) }
                }
            }
        } else {
            HStack(spacing: 12) {
                ForEach(r.choices) { c in
                    OnboardingChoice(choice: c, phase: model.phase, isAnswer: c.id == r.answer, pill: false) { model.pick(c) }
                }
            }
        }
    }

    // MARK: Buttons

    private var buttons: some View {
        VStack(spacing: 8) {
            switch step {
            case .hatch:
                PrimaryButton(title: ui(model.hatched ? "onboarding.hello.button" : "onboarding.hatch.button"),
                              enabled: model.hatchStarted == nil || model.hatched) { model.next() }
            case .round:
                PrimaryButton(title: ui("onboarding.continue"), enabled: model.phase == .right) { model.next() }
            case .result:
                PrimaryButton(title: ui("onboarding.result.button")) { model.next() }
            case .visits, .rhythm, .quiet, .login:
                PrimaryButton(title: ui("onboarding.continue")) { model.next() }
            case .notify:
                PrimaryButton(title: ui("onboarding.notify.button"), enabled: !model.askingPermission) {
                    model.turnOnNotifications()
                }
                SecondaryButton(title: ui("onboarding.notify.later")) { model.notificationsLater() }
            case .widget:
                PrimaryButton(title: ui("onboarding.widget.done")) { model.next() }
                SecondaryButton(title: ui("onboarding.widget.later")) { model.next() }
            case .lockScreen:
                PrimaryButton(title: ui("onboarding.lock.yes")) { model.chooseLockScreen(true) }
                SecondaryButton(title: ui("onboarding.lock.no")) { model.chooseLockScreen(false) }
            case .welcomeBack where model.steps.count > 1:
                PrimaryButton(title: ui("onboarding.continue")) { model.next() }
            case .ready, .welcomeBack:
                PrimaryButton(title: ui("onboarding.ready.go")) { model.next() }
                Text(ui(isPhone ? "onboarding.ready.note.phone" : "onboarding.ready.note"))
                    .font(.system(size: 12)).foregroundStyle(Paint.faint)
            }
        }
        .frame(height: twoButtons ? 98 : 74, alignment: .top)
    }

    private var twoButtons: Bool { step == .notify || step == .widget || step == .lockScreen }

    // MARK: Pieces

    private var dots: some View {
        HStack(spacing: 6) {
            if model.steps.count > 1 {
                ForEach(Array(model.steps.enumerated()), id: \.offset) { i, _ in
                    Capsule()
                        .fill(i == model.index ? Paint.accent : Color.white.opacity(i < model.index ? 0.35 : 0.12))
                        .frame(width: i == model.index ? 18 : 6, height: 6)
                }
            }
        }
    }

    private var background: some View {
        ZStack {
            Paint.page
            RadialGradient(colors: [wash.opacity(0.32), .clear], center: .init(x: 0.5, y: 0.22),
                           startRadius: 0, endRadius: 380)
                .animation(.easeInOut(duration: 0.5), value: step)
        }
    }

    private var wash: Color {
        switch step {
        case .hatch, .welcomeBack: model.hatched ? TomoLook.current.body : Color(hex: "#F5A524")
        case .round:
            switch model.phase {
            case .right: Paint.green
            case .wrong: Paint.red
            default: Color(hex: "#22D3EE")
            }
        case .result: Paint.green
        case .visits, .quiet: Color(hex: "#6366F1")
        case .rhythm, .ready, .widget: Color(hex: "#22D3EE")
        case .notify, .login: Color(hex: "#F5A524")
        case .lockScreen: Color(hex: "#A78BFA")
        }
    }

    func ui(_ key: String, _ args: [String: String] = [:]) -> String { lang.learner(key, args) }

    func eyebrow(_ s: String) -> some View {
        Text(s.uppercased()).font(.system(size: 11, weight: .heavy)).kerning(1.2).foregroundStyle(Color(hex: "#22D3EE"))
    }

    /// The size a step's heading is drawn at: 28 pt, the result's (under the word just answered) 25. A step's heading
    /// is its `onboarding.<step>.title`, so the self-test finds every one in the packs and checks it at this size.
    /// The first run's side padding on the iPhone; its heading check measures an iPhone SE's line with it.
    static let phonePadding: CGFloat = 24

    static func headingSize(_ key: String) -> CGFloat { key == "onboarding.result.title" ? 25 : 28 }

    /// A step's heading, `key` in the learner's pack: two lines at most, wrapping only between its phrases
    /// (`TomoLineBreaks`), else shrinking. Every step's heading is drawn here, so the self-test's size is the real one.
    func title(_ key: String, _ args: [String: String] = [:]) -> some View {
        let s = ui(key, args)
        return Text(TomoLineBreaks.phrased(s)).font(.system(size: Self.headingSize(key), weight: .heavy, design: .rounded))
            .lineLimit(2).minimumScaleFactor(0.7)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(TomoLineBreaks.spoken(s))
    }

    func bodyText(_ s: String) -> some View {
        Text(s).font(.system(size: 15)).foregroundStyle(Paint.soft)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Something Tomo says, in the target language, with its reading and translation.
    func spoken(_ line: TargetPack.SpokenLine) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(line.say).font(.system(size: 26, weight: .bold, design: .rounded))
            Text([line.romanization, line.translation(lang.learner.id)].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 13)).foregroundStyle(Paint.faint)
        }
    }

    func row(icon: String, _ s: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(Paint.accent)
                .frame(width: 22)
            Text(s).font(.system(size: 14)).foregroundStyle(Paint.soft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    func panel(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 15, weight: .bold)).foregroundStyle(Paint.green)
                .frame(width: 22).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 15, weight: .bold))
                Text(text).font(.system(size: 13)).foregroundStyle(Paint.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Paint.card, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Colours (the card's own: dark page, soft text, green right, red wrong)

enum Paint {
    static let page = Color(hex: "#0E1014")
    static let card = Color(hex: "#1A1D23")
    static let text = Color(hex: "#F5F6F8")
    static let soft = Color(hex: "#C9CDD4")
    static let faint = Color(hex: "#9398A1")
    static let accent = Color(hex: "#FFD45C")      // the mascot's yellow
    static let green = Color(hex: "#34D399")
    static let red = Color(hex: "#F4505E")
}

// MARK: - Controls

/// The quiet choice under the primary one ("Not now").
struct SecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Paint.soft)
                .frame(maxWidth: .infinity).frame(height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct PrimaryButton: View {
    let title: String
    var enabled = true
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(enabled ? Color(hex: "#211A05") : Paint.faint)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(enabled ? Paint.accent.opacity(hovered ? 1 : 0.92) : Color.white.opacity(0.07), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .keyboardShortcut(.defaultAction)
        .onHover { hovered = $0 }
    }
}

private struct OnboardingChoice: View {
    let choice: TomoChoice
    let phase: TomoPhase
    let isAnswer: Bool
    let pill: Bool
    let action: () -> Void
    @State private var hovered = false
    @State private var shake: CGFloat = 0

    private var border: Color {
        switch phase {
        case .right where isAnswer: Paint.green
        case .wrong(let e) where e == choice.id: Paint.red
        default: Color.white.opacity(hovered ? 0.24 : 0.07)
        }
    }

    var body: some View {
        Button(action: action) {
            Group {
                if pill {
                    Text(choice.label ?? "")
                        .font(.system(size: 15, weight: .medium))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity).frame(height: 40)
                } else {
                    VStack(spacing: 3) {
                        Text(choice.emoji ?? "").font(.system(size: 44))
                        if let label = choice.label {
                            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(Paint.faint)
                        }
                    }
                    .frame(maxWidth: .infinity).frame(height: 96)
                }
            }
            .background(Color.white.opacity(hovered ? 0.1 : 0.05))
            .overlay(RoundedRectangle(cornerRadius: pill ? 20 : 18).stroke(border, lineWidth: 2))
            .clipShape(RoundedRectangle(cornerRadius: pill ? 20 : 18))
            .scaleEffect(hovered && phase == .asking ? 1.04 : 1)
            .offset(x: shake)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovered)
        .onChange(of: phase) { _, p in
            guard case .wrong(let e) = p, e == choice.id else { return }
            withAnimation(.spring(response: 0.08, dampingFraction: 0.2)) { shake = 7 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.4)) { shake = 0 }
            }
        }
    }
}

/// Win +1 / Miss, like the card's badge.
private struct OnboardingBadge: View {
    let outcome: TomoOutcome
    @ObservedObject var lang = TomoLanguages.shared

    var body: some View {
        let (icon, key, color): (String, String, Color) = switch outcome {
        case .win(true): ("checkmark.circle.fill", "outcome.win", Paint.green)
        case .win(false): ("checkmark.circle.fill", "outcome.practice", Color(hex: "#8FB8DE"))
        case .loss: ("xmark.circle.fill", "outcome.loss", Paint.red)
        case .neutral: ("minus.circle.fill", "outcome.neutral", Paint.faint)
        }
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold))
            Text(lang.learner(key)).font(.system(size: 12, weight: .bold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.16), in: Capsule())
        .fixedSize()
    }
}

struct RhythmRow: View {
    let title: String
    let tag: String
    let selected: Bool
    var height: CGFloat = 44
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(selected ? Paint.accent : Paint.faint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(tag).font(.system(size: 12)).foregroundStyle(Paint.faint)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).frame(height: height)
            .background(Color.white.opacity(hovered ? 0.09 : 0.05), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Paint.accent.opacity(0.8) : Color.white.opacity(0.06),
                                                                lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - The notch, sketched: where Tomo lives on the Mac

private struct NotchSketch: View {
    static let notch = CGSize(width: 132, height: 30)
    var invite: String           // what Tomo calls out ("あそぼ！")
    @State private var pulse = false

    var body: some View {
        ZStack(alignment: .top) {
            // The top of a screen: a soft wallpaper glow under the menu bar.
            UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 6, bottomTrailingRadius: 6,
                                   topTrailingRadius: 18)
                .fill(LinearGradient(colors: [Color(hex: "#2B3350"), Color(hex: "#151821")], startPoint: .top, endPoint: .bottom))
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 6, bottomTrailingRadius: 6,
                                                topTrailingRadius: 18).stroke(Color.white.opacity(0.08)))
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 12, bottomTrailingRadius: 12,
                                   topTrailingRadius: 0)
                .fill(Color.black)
                .frame(width: Self.notch.width, height: Self.notch.height)
            if !invite.isEmpty {
                Text(invite)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Paint.page)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Paint.text, in: RoundedRectangle(cornerRadius: 12))
                    .offset(x: Self.notch.width / 2 + 34, y: Self.notch.height + 28)
                    .scaleEffect(pulse ? 1.04 : 0.98)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
                    }
            }
        }
    }
}

// MARK: - The egg Tomo hatches from (drawn live, like Tomo; the egg itself is `TomoEgg`'s)

/// A speckled egg in the colours of the Tomo inside it. It rocks while it waits, now and then with a wiggle;
/// once `crackedAt` is set it shakes, cracks across, and the halves fly apart.
struct TomoEggView: View {
    let look: TomoLook
    let crackedAt: Date?

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in draw(context, size: size, now: timeline.date) }
        }
    }

    private func draw(_ context: GraphicsContext, size: CGSize, now: Date) {
        let t = now.timeIntervalSinceReferenceDate
        let w = size.width * 0.58, h = w * 1.28
        let cx = size.width / 2, base = size.height * 0.86          // where the egg sits
        let e = crackedAt.map { now.timeIntervalSince($0) } ?? -1   // seconds since the first tap
        let split = e - TomoEgg.crackTime                           // > 0: the halves are flying apart
        if split > 0.7 { return }

        // Rocking: a slow sway, a wiggle every few seconds, a hard shake while it cracks.
        var rot = sin(t * 2.1) * 0.035
        let beat = t.truncatingRemainder(dividingBy: 2.8)
        if beat < 0.5 { rot += sin(beat * 38) * 0.09 * (1 - beat / 0.5) }
        if e >= 0 && split < 0 { rot += sin(e * 60) * 0.12 * min(1, e * 3) }
        let hop = e >= 0 && split < 0 ? abs(sin(e * 14)) * 4 : 0

        // Shadow
        let shadowW = w * (0.95 - abs(rot) * 1.5)
        context.fill(Path(ellipseIn: CGRect(x: cx - shadowW / 2, y: base - 7, width: shadowW, height: 14)),
                     with: .color(.black.opacity(0.35 * (split > 0 ? max(0, 1 - split / 0.4) : 1))))

        let egg = TomoEgg.path(width: w, height: h)                 // centred on (0, 0)
        let crackShown = e < 0 ? 0 : min(1, e / TomoEgg.crackTime)
        let shell = { (ctx: GraphicsContext) in TomoEgg.drawShell(ctx, egg, width: w, height: h, look: look, outline: 1.5) }

        var ctx = context
        ctx.translateBy(x: cx, y: base - h / 2 - hop)
        if split <= 0 {
            ctx.rotate(by: .radians(rot))
            shell(ctx)
            TomoEgg.drawCrack(ctx, egg, width: w, y: TomoEgg.crackY(height: h), shown: crackShown, lineWidth: 2.5)
            return
        }
        TomoEgg.drawSplit(ctx, k: split / 0.7, width: w, height: h, shell: shell)
    }
}
