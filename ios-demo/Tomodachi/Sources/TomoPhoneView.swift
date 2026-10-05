import SwiftUI
import TomoCore

// MARK: - Tomo's screen on the iPhone
//
// Top to bottom: header (age, level, sound) and the level bar · Tomo, big and alive · what Tomo says ·
// the result · the answers (picture tiles, meaning pills, or the answer box when Tomo talks).
// Every text that can grow is capped (line limits, scaling), so the layout never shifts between rounds.
// While the keyboard is up, Tomo and the text shrink so the header and the answer box stay in view.
// All text comes from the language packs.

struct TomoPhoneView: View {
    @ObservedObject var shell: TomoPhoneShell
    @ObservedObject var game = TomoGame.shared
    @ObservedObject var lang = TomoLanguages.shared
    @FocusState private var typing: Bool

    private var growth: CGFloat { CGFloat(min(max(game.stage - 1, 0), 2)) }
    private var said: String { game.isChat ? game.line.say : game.round.say }
    /// Row sizes: full, or compact while the keyboard is up.
    private var tomoSize: CGFloat { typing ? 110 : 220 }
    private var speechHeight: CGFloat { typing ? 180 : 190 }   // two lines, the result, one line of why

    var body: some View {
        VStack(spacing: 0) {
            header
            GrowthBar(progress: game.levelProgress, dimmed: game.isPracticeRound)
                .frame(height: 6)
                .padding(.horizontal, 20)
                .padding(.top, 10)

            Spacer(minLength: 4)
            TomoChickView(state: shell.botState, growth: growth)
                .frame(width: tomoSize, height: tomoSize)
                .contentShape(Rectangle())
                .onTapGesture { NotificationCenter.default.post(name: .triggerSlap, object: nil) }
            speech
                .frame(height: speechHeight, alignment: .top)
                .padding(.horizontal, 24)
            Spacer(minLength: 4)

            answers
                .frame(height: typing ? nil : 230, alignment: .bottom)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .foregroundStyle(Color(hex: "#F5F6F8"))
        .background(background.ignoresSafeArea().onTapGesture { typing = false })
        .animation(.easeInOut(duration: 0.35), value: game.phase)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: typing)
        .sheet(isPresented: wordCardShown) {
            if case .word(let w) = game.help { TomoWordSheet(word: w) }
        }
    }

    /// The word card is open: the game's help is a word (TomoGame.openWord).
    private var wordCardShown: Binding<Bool> {
        Binding(get: { if case .word = game.help { true } else { false } },
                set: { if !$0 { game.help = nil } })
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .lineLimit(1).fixedSize()
            Text(game.age)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: "#FFD9A8"))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color(hex: "#4A3424"), in: Capsule())
            Text(lang.learner("level", ["n": "\(game.level)"]))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(hex: "#C9CDD4"))
            if game.isPracticeRound {
                Text(practiceText("practice.chip", until: game.practiceUntil, lang))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: PhoneColors.practice))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer()
            Button { game.soundEnabled.toggle() } label: {
                Image(systemName: game.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: What Tomo says, and the result

    @ViewBuilder private var speech: some View {
        VStack(spacing: 10) {
            switch game.phase {
            case .grew:
                banner(lang.target.lines.grew,
                       lang.learner(game.stage > TomoGame.chatStage ? "grewOlder"
                                    : game.stage == TomoGame.chatStage ? "grewTalking" : "grewPhrases", ["age": game.age]))
            case .leveledUp:
                banner(lang.target.lines.levelUp, lang.learner("levelUp", ["level": "\(game.level)"]))
            case .practiceIntro:
                banner(lang.target.lines.practice, practiceText("practice.offer", until: game.practiceUntil, lang))
            default:
                HStack(alignment: .center, spacing: 10) {
                    // Tap a word for its word card (TomoWordSheet)
                    TomoTappableLine(text: said, spacesOnly: !game.isChat)
                        .frame(maxHeight: 90)
                    if !said.isEmpty {
                        Button { game.replay() } label: {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 38, height: 38)
                                .background(Color.white.opacity(0.1), in: Circle())
                        }
                    }
                }
                result
            }
        }
        .transaction { $0.animation = nil }      // a new round replaces the old one; no cross-fade
    }

    @ViewBuilder private var result: some View {
        let showMeaning = game.phase == .right || game.help == .hint
        HStack(spacing: 8) {
            if let o = game.outcome, game.phase != .thinking { PhoneOutcomeBadge(outcome: o) }
            if game.phase == .thinking { ProgressView().tint(.white) }
            if showMeaning {
                Text(meaningLine)
                    .font(.system(size: 15))
                    .foregroundStyle(Color(hex: "#D5D8DE"))
                    .lineLimit(2).minimumScaleFactor(0.8)
            }
        }
        // Talking: why the answer got its result, and what Tomo read (romaji shows here as kana).
        if game.isChat, game.help != .hint, let you = game.lastAnswer, let o = game.outcome, game.phase != .thinking {
            Text("\(o.why(lang)) · \(lang.learner("you", ["x": you]))")
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "#9EA3AC"))
                .multilineTextAlignment(.center)
                .lineLimit(2).minimumScaleFactor(0.8)
        }
        if game.isChat, game.help == .hint, !game.line.examples.isEmpty {
            HStack(spacing: 6) {
                Text(lang.learner("hint.try")).font(.system(size: 11, weight: .bold)).foregroundStyle(Color(hex: "#9398A1"))
                ForEach(game.line.examples.prefix(2), id: \.self) { e in
                    Button { game.useExample(e) } label: {
                        Text(e).font(.system(size: 13)).lineLimit(1).minimumScaleFactor(0.7)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.white.opacity(0.1), in: Capsule())
                    }
                }
            }
        }
    }

    private var meaningLine: String {
        if game.isChat { return [game.line.romanization, game.line.translation].compactMap { $0 }.joined(separator: " · ") }
        return [game.round.romanization, game.round.meaning].compactMap { $0 }.joined(separator: " · ")
    }

    private func banner(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.system(size: 32, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
            Text(subtitle).font(.system(size: 15)).foregroundStyle(Color(hex: "#C9CDD4"))
                .multilineTextAlignment(.center).lineLimit(3)
        }
    }

    // MARK: Answers

    @ViewBuilder private var answers: some View {
        switch game.phase {
        case .practiceIntro:
            VStack(spacing: 10) {
                PhonePill(title: lang.learner("practice.start"), tint: PhoneColors.practice) { game.startPractice() }
                PhonePill(title: lang.learner("practice.later")) { game.skipPractice() }
            }
        case .grew, .leveledUp:
            EmptyView()
        default:
            if game.isChat { chatInput }
            else if game.round.kind == .meaning || game.round.kind == .reply {
                VStack(spacing: 10) {
                    ForEach(game.round.choices) { c in
                        PhonePill(title: c.label ?? "", border: border(c)) { game.pick(c) }
                    }
                }
            } else {
                HStack(spacing: 12) {
                    ForEach(game.round.choices) { c in
                        PhoneTile(choice: c, border: border(c)) { game.pick(c) }
                    }
                }
            }
        }
    }

    private var chatInput: some View {
        HStack(spacing: 10) {
            Button { game.showHint() } label: {
                Image(systemName: "lightbulb").font(.system(size: 18, weight: .semibold))
                    .frame(width: 50, height: 50)
                    .background(Color.white.opacity(game.help == .hint ? 0.2 : 0.08), in: Circle())
            }
            .accessibilityLabel(lang.learner("hint"))
            TextField("\(lang.target.labels.answerPrompt) \(lang.learner("typeIn", ["language": lang.targetName]))",
                      text: $game.draft)
                .focused($typing)
                .submitLabel(.send)
                .onSubmit { game.submitDraft() }
                .font(.system(size: 17))
                .padding(.horizontal, 16).frame(height: 50)
                .background(Color.white.opacity(0.08), in: Capsule())
            Button { game.submitDraft() } label: {
                Image(systemName: "arrow.up").font(.system(size: 18, weight: .bold))
                    .frame(width: 50, height: 50)
                    .background(Color(hex: game.draft.isEmpty ? "#3A3D44" : "#6366F1"), in: Circle())
            }
            .disabled(game.draft.isEmpty || game.phase != .asking)
        }
    }

    private func border(_ c: TomoChoice) -> Color {
        switch game.phase {
        case .right where c.id == game.round.answer: Color(hex: "#34D399")
        case .wrong(let e) where e == c.id: Color(hex: "#F4505E")
        default: Color.white.opacity(0.08)
        }
    }

    // MARK: Background: a soft wash that says how it went

    private var background: some View {
        ZStack {
            Color(hex: "#0E1014")
            RadialGradient(colors: [Color(hex: wash).opacity(0.45), .clear], center: .init(x: 0.5, y: 0.42),
                           startRadius: 10, endRadius: 420)
        }
    }

    private var wash: String {
        if game.isChat, let o = game.outcome, game.phase != .thinking {
            switch o {
            case .win(let counted): return counted ? "#2F8F6A" : "#3A3D44"
            case .loss: return "#9B2C3A"
            case .neutral: return "#3A3D44"
            }
        }
        switch game.phase {
        case .asking: return "#1F5C6E"
        case .thinking: return "#3B3F8F"
        case .right where game.outcome == .win(counted: false): return "#3A3D44"
        case .right: return game.round.need == .sleep ? "#3B3F8F" : "#2F8F6A"
        case .wrong: return "#9B2C3A"
        case .leveledUp, .grew: return "#9A6A1E"
        case .practiceIntro: return "#3A3D44"
        }
    }
}

// MARK: - Pieces

enum PhoneColors {
    static let practice = "#8FB8DE"   // the Mac card's practice tint
}

private struct GrowthBar: View {
    let progress: Double
    let dimmed: Bool

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [Color(hex: "#FFE68C"), Color(hex: "#34D399")],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, g.size.width * min(max(progress, 0), 1)))
                    .opacity(dimmed ? 0.35 : 1)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progress)
    }
}

private struct PhoneTile: View {
    let choice: TomoChoice
    let border: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(choice.emoji ?? "").font(.system(size: 52))
                if let label = choice.label {
                    Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(Color(hex: "#9398A1"))
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity).frame(height: 120)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(border, lineWidth: 2.5))
        }
        .buttonStyle(PressStyle())
    }
}

private struct PhonePill: View {
    let title: String
    var icon: String?
    var tint: String?
    var border: Color = Color.white.opacity(0.08)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon) }
                Text(title).lineLimit(1).minimumScaleFactor(0.7)
            }
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(tint.map { Color(hex: $0).opacity(0.3) } ?? Color.white.opacity(0.06), in: Capsule())
            .overlay(Capsule().stroke(border, lineWidth: 2))
        }
        .buttonStyle(PressStyle())
    }
}

private struct PhoneOutcomeBadge: View {
    let outcome: TomoOutcome
    @ObservedObject var lang = TomoLanguages.shared

    private var style: (icon: String, key: String, color: String) {
        switch outcome {
        case .win(true): ("checkmark.circle.fill", "outcome.win", "#34D399")
        case .win(false): ("checkmark.circle.fill", "outcome.practice", PhoneColors.practice)
        case .loss: ("xmark.circle.fill", "outcome.loss", "#F4505E")
        case .neutral: ("minus.circle.fill", "outcome.neutral", "#B0B5BE")
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: style.icon)
            Text(lang.learner(style.key))
        }
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(Color(hex: style.color))
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Color(hex: style.color).opacity(0.16), in: Capsule())
        .fixedSize()
    }
}

/// Buttons sink a little under the finger.
private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

extension Color {
    init(hex: String) {
        let v = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
