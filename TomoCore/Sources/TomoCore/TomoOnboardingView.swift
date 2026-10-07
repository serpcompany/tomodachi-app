import SwiftUI

// MARK: - The first run's screens (TomoOnboarding.swift has the flow and who sees it)
//
// A portrait page like the reference app's (#83): Tomo at the top, a short title and text, the action at the
// bottom. One Tomo stays on screen the whole way and moves between steps (it never re-appears from nothing);
// the egg it hatches from is drawn and animated live too (TomoEggView). Shared by every shell: the Mac shows it in
// a window, and the iPhone can show it full screen. All text comes from ui.<id>.json and the target pack.

public struct TomoOnboardingView: View {
    @ObservedObject var model: TomoOnboarding
    @ObservedObject var game = TomoGame.shared
    @ObservedObject var lang = TomoLanguages.shared
    var gaze: (() -> CGPoint)?

    /// `gaze`: where the pointer is relative to Tomo, −1…1 (positive y = above), for shells that know.
    public init(model: TomoOnboarding, gaze: (() -> CGPoint)? = nil) {
        self.model = model
        self.gaze = gaze
    }

    private var step: TomoOnboarding.Step { model.step }

    public var body: some View {
        VStack(spacing: 0) {
            dots.frame(height: 22)
            hero
                .frame(height: heroHeight)
                .padding(.top, 10)
            ZStack(alignment: .top) {
                page.id(step).transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 12)),
                                                     removal: .opacity))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 14)
            buttons
        }
        .padding(.horizontal, 28)
        .padding(.top, 10)
        .padding(.bottom, 22)
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
        case .visits: 132
        case .rhythm: 96
        case .ready: 116
        }
    }

    private var tomoSize: CGFloat {
        switch step {
        case .hatch, .welcomeBack: 220
        case .round, .result: 150
        case .visits: 58
        case .rhythm: 96
        case .ready: 116
        }
    }

    private var hero: some View {
        GeometryReader { geo in
            ZStack {
                if step == .visits {
                    NotchSketch(pending: true, invite: lang.target.lines.invite ?? "").transition(.opacity)
                }
                // The egg stays until its halves have flown off (it draws nothing after); not when opened past it.
                if step == .hatch && model.hatchStarted != .distantPast {
                    TomoEggView(look: TomoLook.current, crackedAt: model.hatchStarted)
                        .frame(width: 220, height: 236)
                        .contentShape(Rectangle())
                        .onTapGesture { model.hatch() }
                        .transition(.identity)
                }
                TomoBlobView(state: model.botState, growth: game.growthStep, gaze: gaze)
                    .frame(width: tomoSize, height: tomoSize)
                    .scaleEffect(model.hatched ? 1 : 0.2)
                    .opacity(model.hatched ? 1 : 0)
                    .offset(step == .visits ? CGSize(width: NotchSketch.notch.width / 2 + 30,
                                                     height: -geo.size.height / 2 + NotchSketch.notch.height / 2 + 2)
                                            : .zero)
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
        case .visits: visitsPage
        case .rhythm: rhythmPage
        case .ready: readyPage
        case .welcomeBack: welcomeBackPage
        }
    }

    @ViewBuilder private var hatchPage: some View {
        if model.hatched {
            VStack(alignment: .leading, spacing: 12) {
                if let line = lang.target.lines.hello { spoken(line) }
                title(ui("onboarding.hello.title"))
                bodyText(ui("onboarding.hello.body", ["age": game.age]))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                eyebrow(ui("onboarding.hatch.eyebrow"))
                title(ui("onboarding.hatch.title"))
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
            Text(ui("onboarding.result.title", ["language": lang.targetName]))
                .font(.system(size: 25, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
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
        f.locale = Locale(identifier: lang.learner.id)
        f.timeStyle = .short
        return ui("onboarding.result.stick.body", ["word": word, "time": f.string(from: back)])
    }

    private var visitsPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            title(ui("onboarding.visits.title"))
            bodyText(ui("onboarding.visits.body"))
            VStack(alignment: .leading, spacing: 10) {
                row(icon: "keyboard", ui("onboarding.visits.typing"))
                row(icon: "cursorarrow.click.2", ui("onboarding.visits.click"))
                row(icon: "moon.zzz.fill", ui("onboarding.visits.ignore"))
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rhythmPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            title(ui("onboarding.rhythm.title"))
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
            title(ui("onboarding.ready.title"))
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
            title(ui("onboarding.back.title"))
            bodyText(ui("onboarding.back.body", ["age": game.age, "level": "\(game.level)"]))
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
            case .visits, .rhythm:
                PrimaryButton(title: ui("onboarding.continue")) { model.next() }
            case .ready, .welcomeBack:
                PrimaryButton(title: ui("onboarding.ready.go")) { model.next() }
                Text(ui("onboarding.ready.note")).font(.system(size: 12)).foregroundStyle(Paint.faint)
            }
        }
        .frame(height: 74, alignment: .top)
    }

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
        case .visits: Color(hex: "#6366F1")
        case .rhythm, .ready: Color(hex: "#22D3EE")
        }
    }

    private func ui(_ key: String, _ args: [String: String] = [:]) -> String { lang.learner(key, args) }

    private func eyebrow(_ s: String) -> some View {
        Text(s.uppercased()).font(.system(size: 11, weight: .heavy)).kerning(1.2).foregroundStyle(Color(hex: "#22D3EE"))
    }

    private func title(_ s: String) -> some View {
        Text(s).font(.system(size: 28, weight: .heavy, design: .rounded))
            .lineLimit(2).minimumScaleFactor(0.7)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func bodyText(_ s: String) -> some View {
        Text(s).font(.system(size: 15)).foregroundStyle(Paint.soft)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Something Tomo says, in the target language, with its reading and translation.
    private func spoken(_ line: TargetPack.SpokenLine) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(line.say).font(.system(size: 26, weight: .bold, design: .rounded))
            Text([line.romanization, line.translation(lang.learner.id)].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 13)).foregroundStyle(Paint.faint)
        }
    }

    private func row(icon: String, _ s: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(Paint.accent)
                .frame(width: 22)
            Text(s).font(.system(size: 14)).foregroundStyle(Paint.soft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func panel(icon: String, title: String, text: String) -> some View {
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

private enum Paint {
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

private struct PrimaryButton: View {
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

private struct RhythmRow: View {
    let title: String
    let tag: String
    let selected: Bool
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
            .padding(.horizontal, 14).frame(height: 44)
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
    var pending: Bool
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
            if pending {
                Circle().fill(Paint.red)
                    .frame(width: 9, height: 9)
                    .scaleEffect(pulse ? 1.25 : 0.9)
                    .offset(x: Self.notch.width / 2 + 50, y: 5)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
                    }
            }
            if !invite.isEmpty {
                Text(invite)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Paint.page)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Paint.text, in: RoundedRectangle(cornerRadius: 12))
                    .offset(x: Self.notch.width / 2 + 34, y: Self.notch.height + 28)
                    .scaleEffect(pulse ? 1.04 : 0.98)
            }
        }
    }
}

// MARK: - The egg Tomo hatches from (drawn live, like Tomo)

public enum TomoEgg {
    /// From the first tap to the shell splitting open.
    public static let crackTime = 0.9
}

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

        let egg = Self.eggPath(width: w, height: h)                 // centred on (0, 0)
        let crackY = -h * 0.04
        let crack = Self.crackLine(width: w, y: crackY)
        let crackShown = e < 0 ? 0 : min(1, e / TomoEgg.crackTime)

        func drawEgg(_ ctx: GraphicsContext) {
            ctx.fill(egg, with: .linearGradient(Gradient(colors: [Color(hex: "#FFF9EC"), Color(hex: "#EBDDC3")]),
                                                startPoint: CGPoint(x: -w * 0.3, y: -h * 0.5),
                                                endPoint: CGPoint(x: w * 0.3, y: h * 0.5)))
            var inside = ctx
            inside.clip(to: egg)
            for (i, s) in Self.spots(seed: look.seed).enumerated() {
                let r = s.r * w
                let rect = CGRect(x: s.x * w - r, y: s.y * h - r, width: r * 2, height: r * 2)
                inside.fill(Path(ellipseIn: rect), with: .color((i % 3 == 0 ? look.accent : look.body).opacity(0.85)))
            }
            // A soft shine, top left
            inside.fill(Path(ellipseIn: CGRect(x: -w * 0.32, y: -h * 0.38, width: w * 0.2, height: h * 0.16)),
                        with: .color(.white.opacity(0.55)))
            ctx.stroke(egg, with: .color(Color(hex: "#C9B48F").opacity(0.6)), lineWidth: 1.5)
        }

        var ctx = context
        ctx.translateBy(x: cx, y: base - h / 2 - hop)
        if split <= 0 {
            ctx.rotate(by: .radians(rot))
            drawEgg(ctx)
            if crackShown > 0 {
                ctx.stroke(crack.trimmedPath(from: 0, to: crackShown), with: .color(Color(hex: "#7A5F3A")),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            return
        }
        // Split: the top flies up and spins away, the bottom drops and fades.
        let k = split / 0.7
        var top = ctx
        top.opacity = max(0, 1 - k * 1.3)
        top.translateBy(x: w * 0.25 * k, y: -h * 0.9 * k + h * 0.6 * k * k)
        top.rotate(by: .radians(0.9 * k))
        top.clip(to: Self.half(crackY: crackY, width: w, height: h, top: true))
        drawEgg(top)
        var bottom = ctx
        bottom.opacity = max(0, 1 - k * 1.5)
        bottom.translateBy(x: 0, y: h * 0.25 * k)
        bottom.clip(to: Self.half(crackY: crackY, width: w, height: h, top: false))
        drawEgg(bottom)
    }

    /// An egg: narrower at the top.
    private static func eggPath(width w: CGFloat, height h: CGFloat) -> Path {
        var p = Path()
        let n = 64
        for i in 0...n {
            let a = Double(i) / Double(n) * 2 * .pi
            let up = sin(a)                                         // 1 at the top
            let x = w / 2 * cos(a) * (1 - 0.14 * up)
            let y = -h / 2 * up
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        p.closeSubpath()
        return p
    }

    /// The zigzag crack across the egg, left to right.
    private static func crackLine(width w: CGFloat, y: CGFloat) -> Path {
        var p = Path()
        let teeth = 7
        p.move(to: CGPoint(x: -w * 0.56, y: y))
        for i in 1...teeth {
            let x = -w * 0.56 + w * 1.12 * CGFloat(i) / CGFloat(teeth)
            p.addLine(to: CGPoint(x: x, y: y + (i % 2 == 0 ? -1 : 1) * w * 0.07))
        }
        return p
    }

    /// The part of the shell above (or below) the crack.
    private static func half(crackY: CGFloat, width w: CGFloat, height h: CGFloat, top: Bool) -> Path {
        var p = crackLine(width: w, y: crackY)
        let edge = top ? -h : h
        p.addLine(to: CGPoint(x: w, y: crackY))
        p.addLine(to: CGPoint(x: w, y: edge))
        p.addLine(to: CGPoint(x: -w, y: edge))
        p.addLine(to: CGPoint(x: -w, y: crackY))
        p.closeSubpath()
        return p
    }

    /// Seven speckles placed from the seed (x, y in egg widths and heights from the centre; r in egg widths).
    private static func spots(seed: String) -> [(x: CGFloat, y: CGFloat, r: CGFloat)] {
        var h: UInt64 = 0xcbf29ce484222325
        for b in seed.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        func next() -> CGFloat {
            h ^= h << 13; h ^= h >> 7; h ^= h << 17
            return CGFloat(h % 10_000) / 10_000
        }
        return (0..<7).map { _ in (x: (next() - 0.5) * 0.8, y: (next() - 0.5) * 0.8, r: 0.05 + next() * 0.07) }
    }
}
