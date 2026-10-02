import SwiftUI

// MARK: - Main Tomo card (replaces the agent overview)

struct TomoView: View {
    @ObservedObject var state: AppState
    @ObservedObject var game = TomoGame.shared

    private var wash: CardBackground<EmptyView>.Wash {
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
                    banner(title: "おおきく なった！",
                           subtitle: game.stage == 1
                               ? "Tomo grew up → 2さい. Now it speaks in two-word phrases."
                               : "Tomo grew up → 3さい. Now it can talk with you. Answer in your own words!")
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

            Group {
                if game.hintShown || game.phase == .right {
                    Text("\(game.round.romaji) · \(game.round.meaning)")
                        .foregroundColor(Color(hex: "#C9CDD4"))
                } else {
                    Text(game.round.need == nil ? "Which one is Tomo talking about?" : "What does Tomo want?")
                        .foregroundColor(Color(hex: "#8E939C"))
                }
            }
            .font(.system(size: 12))
            .lineLimit(1)

            HStack(spacing: 6) {
                if game.phase == .right, let adult = game.round.adult {
                    Text("grown-ups say: \(adult)")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                } else {
                    SmallPill(icon: "speaker.wave.2.fill", title: "もういちど") { game.replay() }
                    SmallPill(icon: "questionmark", title: "hint") { game.showHint() }
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
                Text(title).font(.system(size: 11, weight: .medium))
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

    var body: some View {
        HStack(spacing: 14) {
            Text("\(game.isChat ? "かいわ" : "ことば") \(game.progress)/\(game.goal)")
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

// MARK: - 3さい conversation card

private struct TomoChatCard: View {
    @ObservedObject var game: TomoGame
    @ObservedObject var listener: TomoListener
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(game.phase == .thinking ? "…" : game.line.say)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .id(game.line.say)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                Spacer(minLength: 0)
                SmallPill(icon: "speaker.wave.2.fill", title: "") { game.replay() }
                SmallPill(icon: "questionmark", title: "hint") { game.showHint() }
            }

            subtitle
                .font(.system(size: 11.5))
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 8) {
                TextField(listener.isListening ? "きいてるよ…" : "こたえて… (type in Japanese)", text: $game.draft)
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
        if let problem = listener.problem {
            Text(problem).foregroundColor(Color(hex: "#FF8D97"))
        } else if game.hintShown {
            let examples = game.line.examples.isEmpty ? "" : "  ·  e.g. " + game.line.examples.joined(separator: " · ")
            Text("\(game.line.romaji) — \(game.line.english)\(examples)").foregroundColor(Color(hex: "#C9CDD4"))
        } else if let you = game.lastAnswer {
            Text("you: \(you)").foregroundColor(Color(hex: "#8E939C"))
        } else {
            Text("Answer in your own words: type or tap the mic · \(game.aiLabel ?? "offline replies")")
                .foregroundColor(Color(hex: "#8E939C"))
        }
    }
}
