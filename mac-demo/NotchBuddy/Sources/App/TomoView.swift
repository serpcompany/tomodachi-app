import SwiftUI

// MARK: - Layout grid
//
// The island's content area is 620 × 144 pt for Tomo's card. Everything sits in fixed slots so nothing can
// grow into anything else: Tomo's column on the left, then fixed-height rows. Help (hint, explanation,
// word card) never squeezes into the card: the notch grows a help panel underneath (`helpPanel`).
// Change sizes here only.

enum TomoGrid {
    static let content = CGSize(width: 620, height: 144)
    static let tomoColumn: CGFloat = 112         // BotPlacement draws Tomo here
    static let gap: CGFloat = 14                 // between columns, and the right margin
    static var column: CGFloat { content.width - tomoColumn - gap * 2 }   // 480

    // Talking card rows: 56 + 26 + 34 + 2 × 7 = 130, centered in 144
    static let lineRow: CGFloat = 56             // Tomo's line: at most 2 lines, font fitted (24 → 15 pt)
    static let infoRow: CGFloat = 26             // result · one line of text · help buttons
    static let inputRow: CGFloat = 34
    static let rowGap: CGFloat = 7

    // Level bar: full width, between the header (which sits under the physical notch) and the card
    static let levelBar: CGFloat = 5
    static let levelBarGap: CGFloat = 7

    // Picture card, two rows: the word with its replay icon (44) · the result (40) + 8 = 92. No hint here:
    // a wrong pick just means picking again, which is its own hint.
    static let tile = CGSize(width: 76, height: 84)
    static let tileGap: CGFloat = 8
    static var tilesWidth: CGFloat { tile.width * 3 + tileGap * 2 }       // 244
    static var pictureColumn: CGFloat { column - tilesWidth - gap }       // 222
    static let pill = CGSize(width: 244, height: 30)    // "Pick the meaning": 3 × 30 + 2 × 8 = 106
    static let pillGap: CGFloat = 8
    static let wordRow: CGFloat = 44
    static let promptRow: CGFloat = 40
    static let iconButton: CGFloat = 26
    static let iconGap: CGFloat = 6
    static var wordWidth: CGFloat { pictureColumn - iconButton - iconGap }   // 190

    // Help panel under the card (the island grows by helpHeight while it's open)
    static let helpGap: CGFloat = 10
    static let helpPanel: CGFloat = 210
    static var helpHeight: CGFloat { helpGap + helpPanel }
}

// MARK: - Main Tomo card (replaces the agent overview)

struct TomoView: View {
    @ObservedObject var state: AppState
    @ObservedObject var game = TomoGame.shared
    @ObservedObject var lang = TomoLanguages.shared

    private var wash: CardBackground<EmptyView>.Wash {
        if game.isChat, let o = game.outcome, game.phase != .thinking {
            switch o {
            case .win(let counted): return counted ? .green : .soft
            case .loss:    return .red
            case .neutral: return .soft
            }
        }
        switch game.phase {
        case .asking:   return .cyan
        case .thinking: return .indigo
        case .right where game.outcome == .win(counted: false): return .soft
        case .right:    return game.round.need == .sleep ? .indigo : .green
        case .wrong:    return .red
        case .leveledUp, .grew: return .amber
        case .practiceIntro: return .soft
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress to the next level, the whole width of the card (an RPG-style experience bar)
            GrowthBar(progress: game.levelProgress, dimmed: game.isPracticeRound)
                .frame(width: TomoGrid.content.width - 28, height: TomoGrid.levelBar)
                .padding(.bottom, TomoGrid.levelBarGap)
                .help(game.isPracticeRound ? practiceText("practice.offer", until: game.practiceUntil, lang)
                      : lang.learner("words.toNext", ["known": "\(game.levelKnown)", "needed": "\(game.levelNeeded)",
                                                      "next": "\(game.level + 1)"]))
            VStack(spacing: TomoGrid.helpGap) {
                card
                if let help = game.help {
                    TomoHelpPanel(game: game, help: help)
                        .frame(width: TomoGrid.content.width, height: TomoGrid.helpPanel)
                        .transition(.opacity)
                }
            }
        }
        .frame(width: TomoGrid.content.width, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var card: some View {
        ZStack {
            CardBackground(wash: wash)
                .animation(.easeInOut(duration: 0.35), value: game.phase)

            HStack(alignment: .center, spacing: TomoGrid.gap) {
                Color.clear.frame(width: TomoGrid.tomoColumn)    // Tomo sits here

                Group {
                    if game.phase == .practiceIntro {
                        practiceOffer
                    } else if game.phase == .grew {
                        banner(title: lang.target.lines.grew,
                               subtitle: lang.learner(game.stage > TomoGame.chatStage ? "grewOlder"
                                                      : game.stage == TomoGame.chatStage ? "grewTalking" : "grewPhrases",
                                                      ["age": game.age]))
                    } else if game.phase == .leveledUp {
                        banner(title: lang.target.lines.levelUp,
                               subtitle: lang.learner("levelUp", ["level": "\(game.level)"]))
                    } else if game.isChat {
                        TomoChatCard(game: game, listener: game.listener)
                    } else {
                        HStack(alignment: .center, spacing: TomoGrid.gap) {
                            speech.frame(width: TomoGrid.pictureColumn, alignment: .leading)
                            choices.frame(width: TomoGrid.tilesWidth)
                        }
                    }
                }
                .frame(width: TomoGrid.column, height: TomoGrid.content.height, alignment: .leading)
            }
            .frame(width: TomoGrid.content.width, height: TomoGrid.content.height, alignment: .leading)
        }
        .frame(width: TomoGrid.content.width, height: TomoGrid.content.height)
    }

    // Picture stage, two fixed rows: the word with its replay icon · the result (empty while asking)
    private var speech: some View {
        VStack(alignment: .leading, spacing: TomoGrid.rowGap) {
            HStack(spacing: TomoGrid.iconGap) {
                // Clickable like the talking stage: click the word → word card in the panel below
                TomoLineView(game: game, selection: .constant(nil),
                             size: CGSize(width: TomoGrid.wordWidth, height: TomoGrid.wordRow),
                             text: game.round.say, maxSize: 30, selectable: false, spacesOnly: true)
                    .frame(width: TomoGrid.wordWidth, height: TomoGrid.wordRow, alignment: .leading)
                IconButton(icon: "speaker.wave.2.fill", help: lang.target.labels.again) { game.replay() }
            }
            .frame(height: TomoGrid.wordRow)

            VStack(alignment: .leading, spacing: 4) {
                // While Tomo asks, this row stays free (the choices say what to do); after a win, the answer.
                if game.outcome != nil || game.phase == .right {
                    HStack(alignment: .center, spacing: 6) {
                        if let o = game.outcome { OutcomeBadge(outcome: o) }
                        if game.phase == .right {
                            Text([game.round.romanization, game.round.meaning].compactMap { $0 }.joined(separator: " · "))
                                .foregroundColor(Color(hex: "#D5D8DE"))
                                .font(.system(size: 12))
                                .lineLimit(game.round.adult != nil ? 1 : 2)
                                .minimumScaleFactor(0.85)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if game.phase == .right, let adult = game.round.adult {
                    Button { game.openWord(TomoWords.bare(adult)) } label: {
                        Text(lang.learner("grownUpsSay", ["x": adult]))
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: TomoGrid.promptRow, alignment: .leading)
        }
        .transaction { $0.animation = nil }   // a new round replaces the old one; no cross-fade
    }

    @ViewBuilder private var choices: some View {
        if game.round.kind == .meaning {
            VStack(spacing: TomoGrid.pillGap) {
                ForEach(game.round.choices) { c in
                    MeaningPill(choice: c, phase: game.phase, isAnswer: c.id == game.round.answer) { game.pick(c) }
                }
            }
        } else {
            HStack(spacing: TomoGrid.tileGap) {
                ForEach(game.round.choices) { c in
                    ChoiceTile(choice: c, phase: game.phase, isAnswer: c.id == game.round.answer) {
                        game.pick(c)
                    }
                }
            }
        }
    }

    // Nothing counts right now: Tomo asks to play anyway; the card says it's practice and won't move the bar
    // (like WaniKani's "0 reviews" before its Extra Study). Practice starts only on "Practice".
    private var practiceOffer: some View {
        HStack(alignment: .center, spacing: TomoGrid.gap) {
            banner(title: lang.target.lines.practice,
                   subtitle: practiceText("practice.offer", until: game.practiceUntil, lang))
                .frame(width: TomoGrid.pictureColumn, alignment: .leading)
            VStack(spacing: TomoGrid.pillGap) {
                OfferButton(title: lang.learner("practice.start"), primary: true) { game.startPractice() }
                OfferButton(title: lang.learner("practice.later")) { game.skipPractice() }
            }
            .frame(width: TomoGrid.tilesWidth)
        }
    }

    private func banner(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 26, weight: .bold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(subtitle).font(.system(size: 12.5)).foregroundColor(Color(hex: "#C9CDD4"))
                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
        }
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
        case .wrong(let e) where e == choice.id: return Color(hex: "#F4505E")
        default: return Color.white.opacity(hovered ? 0.22 : 0.06)
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(choice.emoji ?? "").font(.system(size: 36))
                if let label = choice.label {
                    Text(label).font(.system(size: 10, weight: .medium)).foregroundColor(Color(hex: "#9398A1"))
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .frame(width: TomoGrid.tile.width, height: TomoGrid.tile.height)
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
            guard case .wrong(let e) = p, e == choice.id else { return }
            withAnimation(.spring(response: 0.08, dampingFraction: 0.2)) { shake = 6 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.4)) { shake = 0 }
            }
        }
    }
}

// MARK: - Meaning pill ("Pick the meaning": a word with no picture or action)

private struct MeaningPill: View {
    let choice: TomoChoice
    let phase: TomoPhase
    let isAnswer: Bool
    let action: () -> Void
    @State private var hovered = false
    @State private var shake: CGFloat = 0

    private var border: Color {
        switch phase {
        case .right where isAnswer: return Color(hex: "#34D399")
        case .wrong(let e) where e == choice.id: return Color(hex: "#F4505E")
        default: return Color.white.opacity(hovered ? 0.22 : 0.06)
        }
    }

    var body: some View {
        Button(action: action) {
            Text(choice.label ?? "")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(Color(hex: "#E6E8EC"))
                .lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, 12)
                .frame(width: TomoGrid.pill.width, height: TomoGrid.pill.height)
                .background(Color.white.opacity(hovered ? 0.1 : 0.05))
                .overlay(Capsule().stroke(border, lineWidth: 2))
                .clipShape(Capsule())
                .scaleEffect(hovered && phase == .asking ? 1.03 : 1)
                .offset(x: shake)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovered)
        .onChange(of: phase) { _, p in
            guard case .wrong(let e) = p, e == choice.id else { return }
            withAnimation(.spring(response: 0.08, dampingFraction: 0.2)) { shake = 6 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.4)) { shake = 0 }
            }
        }
    }
}

/// "Practice" / "Later" on the practice offer, the size of a meaning pill.
private struct OfferButton: View {
    let title: String
    var primary = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13.5, weight: primary ? .semibold : .medium))
                .foregroundColor(Color(hex: primary ? "#F5F6F8" : "#C9CDD4"))
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(width: TomoGrid.pill.width, height: TomoGrid.pill.height)
                .background(primary ? Color(hex: PracticeChip.tint).opacity(hovered ? 0.4 : 0.28)
                                    : Color.white.opacity(hovered ? 0.1 : 0.05))
                .overlay(Capsule().stroke(Color.white.opacity(hovered ? 0.22 : 0.06), lineWidth: 2))
                .clipShape(Capsule())
                .scaleEffect(hovered ? 1.03 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovered)
    }
}

/// Header chip while practicing: "Practice until 5:44 AM". Practice never looks like progress.
struct PracticeChip: View {
    static let tint = "#8FB8DE"
    let until: Date?
    @ObservedObject var lang = TomoLanguages.shared

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 9, weight: .bold))
            Text(text).font(.system(size: 10.5, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundColor(Color(hex: Self.tint))
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Color(hex: Self.tint).opacity(0.16))
        .clipShape(Capsule())
        .frame(maxWidth: 130, alignment: .trailing)   // stays clear of the physical notch
        .help(practiceText("practice.offer", until: until, lang))
    }

    /// The time only when it's today; a later day is in the tooltip and the offer.
    private var text: String {
        guard let until, Calendar.current.isDateInToday(wallClock(until)) else { return lang.learner("practice.chip.now") }
        return practiceText("practice.chip", until: until, lang)
    }
}

/// "Nothing counts until 5:44 AM…" (`key`), or the `key.now` variant when there's no time to give.
@MainActor func practiceText(_ key: String, until: Date?, _ lang: TomoLanguages) -> String {
    guard let until else { return lang.learner("\(key).now") }
    let f = DateFormatter()
    f.locale = Locale(identifier: lang.learner.id)
    f.timeStyle = .short
    f.formattingContext = .middleOfSentence
    if !Calendar.current.isDateInToday(wallClock(until)) { f.dateStyle = .short; f.doesRelativeDateFormatting = true }
    return lang.learner(key, ["time": f.string(from: wallClock(until))])
}

/// A time on Tomo's clock (which testing can move ahead, TomoClock) on the Mac's clock.
@MainActor private func wallClock(_ d: Date) -> Date { d.addingTimeInterval(Date().timeIntervalSince(TomoClock.now)) }

/// A round icon button (replay) next to the word; its label is the tooltip.
private struct IconButton: View {
    let icon: String
    let help: String
    var on = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .frame(width: TomoGrid.iconButton, height: TomoGrid.iconButton)
                .background(Circle().fill(Color.white.opacity(on ? 0.22 : 0.09)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct SmallPill: View {
    let icon: String
    let title: String
    var on = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9, weight: .bold))
                if !title.isEmpty {
                    Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1).fixedSize()
                }
            }
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(on ? Color.white.opacity(0.22) : Color.white.opacity(0.09))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Header status (left: name, age, level · right: voice, close). Start over lives in
// Settings and the menu only, never one click away here. The level bar sits under the header (TomoView).

struct TomoHeaderLeft: View {
    @ObservedObject var game = TomoGame.shared
    @ObservedObject var lang = TomoLanguages.shared

    var body: some View {
        HStack(spacing: 8) {
            Text("Tomodachi").font(.system(size: 13, weight: .semibold))   // the app; the character is Tomo
            Button { TomoSettingsNav.open(.tomo) } label: {    // Settings → Tomo: age, level, growing up
                HStack(spacing: 8) {
                    Text(game.age)
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color(hex: "#F6B99A").opacity(0.25))
                        .foregroundColor(Color(hex: "#FFD3BD"))
                        .clipShape(Capsule())
                    Text(lang.learner("level", ["n": "\(game.level)"]))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "#C9CDD4"))
                        .fixedSize()
                }
            }
            .buttonStyle(.plain)
            .help(lang.learner("settings.openTomo"))
        }
    }
}

struct TomoHeaderRight: View {
    @ObservedObject var state: AppState
    @ObservedObject var game = TomoGame.shared
    @ObservedObject var lang = TomoLanguages.shared

    var body: some View {
        HStack(spacing: 14) {
            if game.isPracticeRound { PracticeChip(until: game.practiceUntil) }
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
    /// Practice: the bar fades back, since nothing done now moves it.
    var dimmed = false

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule()
                    .fill(LinearGradient(colors: [Color(hex: "#FFD3BD"), Color(hex: "#7BD389")],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: g.size.width * min(1, max(0, progress)))
                    .opacity(dimmed ? 0.3 : 1)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: progress)
        .animation(.easeInOut(duration: 0.4), value: dimmed)
    }
}

// MARK: - Talking-stage card

private struct TomoChatCard: View {
    @ObservedObject var game: TomoGame
    @ObservedObject var listener: TomoListener
    @ObservedObject var lang = TomoLanguages.shared
    @FocusState private var focused: Bool
    @State private var selection: ClosedRange<Int>?

    var body: some View {
        VStack(alignment: .leading, spacing: TomoGrid.rowGap) {
            // Row 1 — Tomo's line (clickable words), fitted to 2 lines
            Group {
                if game.phase == .thinking {
                    Text("…").font(.system(size: 24, weight: .bold, design: .rounded))
                } else {
                    TomoLineView(game: game, selection: $selection,
                                 size: CGSize(width: TomoGrid.column, height: TomoGrid.lineRow),
                                 text: game.line.say)
                }
            }
            .frame(width: TomoGrid.column, height: TomoGrid.lineRow, alignment: .leading)
            .transaction { $0.animation = nil }
            .onChange(of: game.line.say) { _, _ in selection = nil }

            // Row 2 — result / "I don't understand" · one line of text · help buttons
            HStack(alignment: .center, spacing: 6) {
                leading
                infoText
                    .font(.system(size: 11.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SmallPill(icon: "speaker.wave.2.fill", title: "") { game.replay() }
                SmallPill(icon: "lightbulb", title: lang.learner("hint"), on: game.help == .hint) {
                    game.help == .hint ? (game.help = nil) : game.showHint()
                }
                SmallPill(icon: "text.bubble", title: lang.learner("explain"), on: game.help == .explain) {
                    game.help == .explain ? (game.help = nil) : game.openExplain()
                }
            }
            .frame(width: TomoGrid.column, height: TomoGrid.infoRow)

            // Row 3 — answer
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
                    .padding(.horizontal, 12)
                    .frame(height: 32)
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
                        .frame(width: 32, height: 32)
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
                        .frame(width: 32, height: 32)
                        .background(Color(hex: "#F5F6F8").opacity(game.draft.isEmpty ? 0.35 : 1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(game.draft.isEmpty || game.phase != .asking)
            }
            .frame(width: TomoGrid.column, height: TomoGrid.inputRow)
        }
        .frame(width: TomoGrid.column, height: TomoGrid.content.height)
    }

    /// Result badge, or the "I don't understand" button while words are highlighted.
    @ViewBuilder private var leading: some View {
        if let range = selection {
            let words = TomoWords.tokens(game.line.say, script: lang.target.script)
            let phrase = TomoWords.bare(words[range.clamped(to: 0...max(0, words.count - 1))]
                .joined(separator: lang.target.script == "Jpan" ? "" : " "))
            Button {
                game.openExplain(focus: phrase)
                selection = nil
            } label: {
                Label(lang.learner("dontUnderstand", ["x": phrase]), systemImage: "questionmark.bubble.fill")
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color(hex: "#6366F1").opacity(0.45))
                    .clipShape(Capsule())
                    .fixedSize()
            }
            .buttonStyle(.plain)
        } else if let o = game.outcome, game.phase != .thinking {
            OutcomeBadge(outcome: o)
        }
    }

    /// One line: mic problem, or what you said and why it scored. Hints live in the help panel.
    @ViewBuilder private var infoText: some View {
        if let problem = listener.problem {
            Text(problem).foregroundColor(Color(hex: "#FF8D97"))
        } else if let you = game.lastAnswer {
            let why = game.outcome.map { OutcomeBadge.why($0, lang) }.map { $0 + " · " } ?? ""
            Text(why + lang.learner("you", ["x": you])).foregroundColor(Color(hex: "#9EA3AC"))
        } else {
            Text(lang.learner("answerOwnWords", ["ai": game.aiLabel ?? lang.learner("offlineReplies")]))
                .foregroundColor(Color(hex: "#9EA3AC"))
        }
    }
}

// MARK: - Help panel (grows out of the notch under the card): hint · explain · word card

private struct TomoHelpPanel: View {
    @ObservedObject var game: TomoGame
    let help: TomoHelp
    @ObservedObject var lang = TomoLanguages.shared
    @State private var question = ""

    private var title: (icon: String, text: String) {
        switch help {
        case .hint:    ("lightbulb", lang.learner("hint"))
        case .explain: ("text.bubble", lang.learner("explain"))
        case .word:    ("character.book.closed", lang.learner("word.title"))
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 20).fill(Color(hex: "#15171B"))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.05), lineWidth: 1))
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: title.icon).font(.system(size: 12, weight: .semibold))
                    Text(title.text).font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    Button { game.help = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                            .frame(width: 20, height: 20).background(Color.white.opacity(0.1)).clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .foregroundColor(Color(hex: "#9EA3AC"))

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        switch help {
                        case .hint: hint
                        case .explain: explain
                        case .word(let w): wordCard(w)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
        }
        .foregroundColor(Color(hex: "#F5F6F8"))
    }

    // Hint: reading, meaning, example answers (click to use)
    @ViewBuilder private var hint: some View {
        let say = game.isChat ? game.line.say : game.round.say
        let reading = game.isChat ? game.line.romanization : game.round.romanization
        let meaning = game.isChat ? game.line.translation : game.round.meaning
        Text(say).font(.system(size: 22, weight: .bold, design: .rounded))
        if let r = reading { Text(r).font(.system(size: 15)).foregroundColor(Color(hex: "#9EA3AC")) }
        Text(meaning).font(.system(size: 18)).fixedSize(horizontal: false, vertical: true)
        if game.isChat && !game.line.examples.isEmpty {
            Text(lang.learner("hint.try")).font(.system(size: 12.5, weight: .semibold)).foregroundColor(Color(hex: "#9EA3AC"))
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(game.line.examples, id: \.self) { ex in
                    Button { game.useExample(ex) } label: {
                        Text(ex).font(.system(size: 15))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.white.opacity(0.1)).clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // Explain: meaning, key parts, tip, ask about a part, say it simpler
    @ViewBuilder private var explain: some View {
        if game.explaining {
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text(lang.learner("explain.loading")) }
                .font(.system(size: 15)).foregroundColor(Color(hex: "#9EA3AC"))
        } else if let e = game.explanation {
            Text(e.translation).font(.system(size: 18)).fixedSize(horizontal: false, vertical: true)
            ForEach(e.parts, id: \.self) { part in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(part.phrase).font(.system(size: 15.5, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color(hex: "#6366F1").opacity(0.35)).clipShape(Capsule())
                        .fixedSize()
                    Text(part.meaning).font(.system(size: 15.5)).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let tip = e.tip {
                Text("💡 " + tip).font(.system(size: 14.5)).foregroundColor(Color(hex: "#C9CDD4"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !e.usedAI {
                Text(lang.learner("explain.noAI")).font(.system(size: 12.5)).foregroundColor(Color(hex: "#7E838C"))
            }
        }
        HStack(spacing: 8) {
            TextField(lang.learner("explain.askPlaceholder"), text: $question)
                .textFieldStyle(.plain).font(.system(size: 14.5))
                .padding(.horizontal, 12).frame(height: 30)
                .background(Color.white.opacity(0.08)).clipShape(Capsule())
                .onSubmit { ask() }
                .simultaneousGesture(TapGesture().onEnded { game.focusInput?() })
            Button(lang.learner("explain.ask")) { ask() }
                .buttonStyle(.plain).font(.system(size: 13.5, weight: .semibold))
                .padding(.horizontal, 12).frame(height: 30)
                .background(Color.white.opacity(question.isEmpty ? 0.06 : 0.16)).clipShape(Capsule())
                .disabled(question.isEmpty || game.explaining)
            Button { game.sayItSimpler() } label: {
                Label(lang.learner("explain.simpler"), systemImage: "tortoise").font(.system(size: 13.5, weight: .semibold))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12).frame(height: 30)
            .background(Color.white.opacity(0.1)).clipShape(Capsule())
            .disabled(game.simplifying || game.phase != .asking)
        }
    }

    // Word card: word, reading, 🔊, meaning, note, the Mac dictionary, links
    @ViewBuilder private func wordCard(_ word: String) -> some View {
        let card = game.wordCard?.word == word ? game.wordCard : nil
        let head = card?.headword ?? word
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(head).font(.system(size: 26, weight: .bold, design: .rounded))
            if let r = card?.reading, r != head { Text(r).font(.system(size: 16)).foregroundColor(Color(hex: "#9EA3AC")) }
            Button { game.speak(head, slow: true) } label: { Image(systemName: "speaker.wave.2.fill").font(.system(size: 14)) }
                .buttonStyle(.plain)
            Spacer()
            Button(lang.learner("word.openMac")) { TomoWords.openMacDictionary(head) }
                .buttonStyle(.plain).font(.system(size: 13, weight: .medium)).foregroundColor(Color(hex: "#8AB4F8"))
            if let url = lang.target.dictionaryURL(for: head) {
                Link(lang.learner("word.open"), destination: url).font(.system(size: 13, weight: .medium))
            }
        }
        if game.lookingUp && card == nil {
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text(lang.learner("word.loading")) }
                .font(.system(size: 15)).foregroundColor(Color(hex: "#9EA3AC"))
        } else if let c = card, c.usedAI {
            Text(c.meaning).font(.system(size: 18)).fixedSize(horizontal: false, vertical: true)
            if let n = c.note {
                Text(n).font(.system(size: 14.5)).foregroundColor(Color(hex: "#C9CDD4")).fixedSize(horizontal: false, vertical: true)
            }
        }
        VStack(alignment: .leading, spacing: 3) {
            Text(lang.learner("word.mac")).font(.system(size: 11.5, weight: .semibold)).foregroundColor(Color(hex: "#7E838C"))
            Text(TomoWords.macDictionary(head) ?? TomoWords.macDictionary(word) ?? lang.learner("word.none"))
                .font(.system(size: 13.5)).foregroundColor(Color(hex: "#9EA3AC"))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func ask() {
        guard !question.isEmpty else { return }
        game.explain(focus: question)
        question = ""
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
        case .win(true):  ("checkmark.circle.fill", "outcome.win", Color(hex: "#34D399"))
        case .win(false): ("checkmark.circle.fill", "outcome.practice", Color(hex: PracticeChip.tint))   // not progress
        case .loss:    ("xmark.circle.fill", "outcome.loss", Color(hex: "#F4505E"))
        case .neutral: ("minus.circle.fill", "outcome.neutral", Color(hex: "#B0B5BE"))
        }
    }

    static func why(_ o: TomoOutcome, _ lang: TomoLanguages) -> String {
        switch o {
        case .win(let counted): lang.learner(counted ? "outcome.why.win" : "outcome.why.practice")
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
    }
}
