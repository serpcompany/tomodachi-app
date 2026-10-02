import SwiftUI

// MARK: - Main Tomo card (replaces the agent overview)

struct TomoView: View {
    @ObservedObject var state: AppState
    @ObservedObject var game = TomoGame.shared
    @ObservedObject var lang = TomoLanguages.shared

    private var wash: CardBackground<EmptyView>.Wash {
        if game.isChat, let o = game.outcome, game.phase != .thinking {
            switch o {
            case .win:     return .green
            case .loss:    return .red
            case .neutral: return .soft
            }
        }
        switch game.phase {
        case .asking:   return .cyan
        case .thinking: return .indigo
        case .right:    return game.round.need == .sleep ? .indigo : .green
        case .wrong:    return .red
        case .grew:     return .amber
        }
    }

    var body: some View {
        ZStack {
            CardBackground(wash: wash)
                .animation(.easeInOut(duration: 0.35), value: game.phase)

            HStack(spacing: 14) {
                Color.clear.frame(width: 112)   // Tomo sits here (drawn by BotPlacement)

                if game.phase == .grew {
                    banner(title: lang.target.lines.grew,
                           subtitle: lang.learner(game.stage == 1 ? "grewPhrases" : "grewTalking",
                                                  ["age": lang.target.ageLabel(game.stage + 1)]))
                } else if game.isChat {
                    TomoChatCard(game: game, listener: game.listener)
                } else {
                    speech
                    Spacer(minLength: 4)
                    choices
                }
            }
            .padding(.trailing, 14)
        }
    }

    // What Tomo is saying + hint
    private var speech: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(game.round.say)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .id(game.round.say)
                .transition(.scale(scale: 0.8).combined(with: .opacity))

            HStack(spacing: 6) {
                if let o = game.outcome { OutcomeBadge(outcome: o) }
                Group {
                if game.hintShown || game.phase == .right {
                    Text([game.round.romanization, game.round.meaning].compactMap { $0 }.joined(separator: " · "))
                        .foregroundColor(Color(hex: "#C9CDD4"))
                } else {
                    Text(lang.learner(game.round.need == nil ? "pickPicture" : "pickNeed"))
                        .foregroundColor(Color(hex: "#8E939C"))
                }
                }
                .font(.system(size: 12))
                .lineLimit(1)
            }

            HStack(spacing: 6) {
                if game.phase == .right, let adult = game.round.adult {
                    Text(lang.learner("grownUpsSay", ["x": adult]))
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                } else {
                    SmallPill(icon: "speaker.wave.2.fill", title: lang.target.labels.again) { game.replay() }
                    SmallPill(icon: "questionmark", title: lang.learner("hint")) { game.showHint() }
                }
            }
        }
        .frame(maxWidth: 250, alignment: .leading)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: game.round.say)
    }

    private var choices: some View {
        HStack(spacing: 8) {
            ForEach(game.round.choices) { c in
                ChoiceTile(choice: c, phase: game.phase, isAnswer: c.emoji == game.round.answer) {
                    game.pick(c)
                }
            }
        }
    }

    private func banner(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 26, weight: .bold, design: .rounded))
            Text(subtitle).font(.system(size: 12.5)).foregroundColor(Color(hex: "#C9CDD4"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Picture / action tile

private struct ChoiceTile: View {
    let choice: TomoChoice
    let phase: TomoPhase
    let isAnswer: Bool
    let action: () -> Void
    @State private var hovered = false
    @State private var shake: CGFloat = 0

    private var border: Color {
        switch phase {
        case .right where isAnswer: return Color(hex: "#34D399")
        case .wrong(let e) where e == choice.emoji: return Color(hex: "#F4505E")
        default: return Color.white.opacity(hovered ? 0.22 : 0.06)
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(choice.emoji).font(.system(size: 36))
                if let label = choice.label {
                    Text(label).font(.system(size: 10, weight: .medium)).foregroundColor(Color(hex: "#9398A1"))
                }
            }
            .frame(width: 76, height: 84)
            .background(Color.white.opacity(hovered ? 0.1 : 0.05))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(border, lineWidth: 2))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .scaleEffect(hovered && phase == .asking ? 1.05 : 1)
            .offset(x: shake)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovered)
        .onChange(of: phase) { _, p in
            guard case .wrong(let e) = p, e == choice.emoji else { return }
            withAnimation(.spring(response: 0.08, dampingFraction: 0.2)) { shake = 6 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.4)) { shake = 0 }
            }
        }
    }
}

private struct SmallPill: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9, weight: .bold))
                Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1).fixedSize()
            }
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Color.white.opacity(0.09))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Header status (left: name, age, growth bar · right: words, restart, voice)

struct TomoHeaderLeft: View {
    @ObservedObject var game = TomoGame.shared

    var body: some View {
        HStack(spacing: 8) {
            Text("Tomo").font(.system(size: 13, weight: .semibold))
            Text(game.age)
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Color(hex: "#F6B99A").opacity(0.25))
                .foregroundColor(Color(hex: "#FFD3BD"))
                .clipShape(Capsule())
            GrowthBar(progress: Double(game.progress) / Double(game.goal))
                .frame(width: 70, height: 6)
        }
    }
}

struct TomoHeaderRight: View {
    @ObservedObject var state: AppState
    @ObservedObject var game = TomoGame.shared
    @ObservedObject var lang = TomoLanguages.shared

    var body: some View {
        HStack(spacing: 14) {
            Text("\(game.isChat ? lang.target.labels.talk : lang.target.labels.words) \(game.progress)/\(game.goal)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(hex: "#8E939C"))
            Button(action: { game.restart() }) {
                Image(systemName: "arrow.counterclockwise").font(.system(size: 13))
                    .foregroundColor(Color(hex: "#8E939C"))
            }
            .buttonStyle(.plain)
            Button(action: { state.soundEnabled.toggle() }) {
                Image(systemName: state.soundEnabled ? "speaker.wave.2" : "speaker.slash")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "#8E939C"))
            }
            .buttonStyle(.plain)
            Button(action: { game.dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "#C9CDD4"))
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(lang.learner("notNow"))
        }
    }
}

private struct GrowthBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule()
                    .fill(LinearGradient(colors: [Color(hex: "#FFD3BD"), Color(hex: "#7BD389")],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: g.size.width * min(1, max(0, progress)))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: progress)
    }
}

// MARK: - Talking-stage card

private struct TomoChatCard: View {
    @ObservedObject var game: TomoGame
    @ObservedObject var listener: TomoListener
    @ObservedObject var lang = TomoLanguages.shared
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(game.phase == .thinking ? "…" : game.line.say)
                    .font(.system(size: game.line.say.count > 36 ? 18 : 24, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(game.line.say)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                Spacer(minLength: 0)
                SmallPill(icon: "speaker.wave.2.fill", title: "") { game.replay() }
                SmallPill(icon: "questionmark", title: lang.learner("hint")) { game.showHint() }
            }

            subtitle
                .font(.system(size: 11.5))
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 8) {
                TextField(listener.isListening
                          ? lang.target.labels.listening
                          : "\(lang.target.labels.answerPrompt) \(lang.learner("typeIn", ["language": lang.targetName]))",
                          text: $game.draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($focused)
                    .onSubmit { game.submitDraft() }
                    .disabled(game.phase != .asking)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                    .simultaneousGesture(TapGesture().onEnded {
                        game.focusInput?()
                        focused = true
                    })

                Button(action: { game.toggleMic() }) {
                    Image(systemName: listener.isListening ? "waveform" : "mic.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(listener.isListening ? .white : Color(hex: "#0B0C0E"))
                        .frame(width: 30, height: 30)
                        .background(listener.isListening ? Color(hex: "#F4505E") : Color(hex: "#F5F6F8"))
                        .clipShape(Circle())
                        .symbolEffect(.pulse, isActive: listener.isListening)
                }
                .buttonStyle(.plain)
                .disabled(game.phase != .asking)

                Button(action: { game.submitDraft() }) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(hex: "#0B0C0E"))
                        .frame(width: 30, height: 30)
                        .background(Color(hex: "#F5F6F8").opacity(game.draft.isEmpty ? 0.35 : 1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(game.draft.isEmpty || game.phase != .asking)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: game.line.say)
    }

    @ViewBuilder private var subtitle: some View {
        HStack(spacing: 6) {
            if let o = game.outcome, game.phase != .thinking { OutcomeBadge(outcome: o) }
            subtitleText
        }
    }

    @ViewBuilder private var subtitleText: some View {
        if let problem = listener.problem {
            Text(problem).foregroundColor(Color(hex: "#FF8D97"))
        } else if game.hintShown {
            let examples = game.line.examples.isEmpty ? ""
                : "  ·  \(lang.learner("eg")) " + game.line.examples.joined(separator: " · ")
            let meaning = [game.line.romanization, game.line.translation].compactMap { $0 }.joined(separator: " — ")
            Text(meaning + examples).foregroundColor(Color(hex: "#C9CDD4"))
        } else if let you = game.lastAnswer {
            let why = game.outcome.map { OutcomeBadge.why($0, lang) }.map { $0 + " · " } ?? ""
            Text(why + lang.learner("you", ["x": you])).foregroundColor(Color(hex: "#8E939C"))
        } else {
            Text(lang.learner("answerOwnWords", ["ai": game.aiLabel ?? lang.learner("offlineReplies")]))
                .foregroundColor(Color(hex: "#8E939C"))
        }
    }
}

// MARK: - Red dot on small Tomo while a visit is waiting

struct TomoPendingDot: View {
    @ObservedObject var game = TomoGame.shared

    var body: some View {
        Circle()
            .fill(Color(hex: "#FF3B30"))
            .frame(width: 7, height: 7)
            .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
            .scaleEffect(game.pending ? 1 : 0.2)
            .opacity(game.pending ? 1 : 0)
            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: game.pending)
    }
}

// MARK: - Win / Miss / No score badge

struct OutcomeBadge: View {
    let outcome: TomoOutcome
    @ObservedObject var lang = TomoLanguages.shared

    private var style: (icon: String, key: String, color: Color) {
        switch outcome {
        case .win:     ("checkmark.circle.fill", "outcome.win", Color(hex: "#34D399"))
        case .loss:    ("xmark.circle.fill", "outcome.loss", Color(hex: "#F4505E"))
        case .neutral: ("minus.circle.fill", "outcome.neutral", Color(hex: "#B0B5BE"))
        }
    }

    static func why(_ o: TomoOutcome, _ lang: TomoLanguages) -> String {
        switch o {
        case .win:             lang.learner("outcome.why.win")
        case .loss:            lang.learner("outcome.why.loss")
        case .neutral(let r):  lang.learner("outcome.why.\(r)", ["language": lang.targetName])
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: style.icon).font(.system(size: 10, weight: .bold))
            Text(lang.learner(style.key)).font(.system(size: 10.5, weight: .bold))
        }
        .foregroundColor(style.color)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(style.color.opacity(0.16))
        .clipShape(Capsule())
        .fixedSize()
        .help(Self.why(outcome, lang))
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }
}
