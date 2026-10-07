import SwiftUI
import TomoCore

// MARK: - Settings window (menu → Settings…), laid out like the Mac's System Settings
//
// A sidebar of pages on the left, the selected page on the right:
//   Tomo (growth: age, level, growing up, today) · Words (every level and word) · General · AI · Testing · About
// Testing shows only after a deliberate step (TomoTestingTools).
// All text comes from the learner's interface strings (TomoCore: Resources/languages/ui.<id>.json).

/// Starting over clears this language pair's saved Tomo, so it always asks first.
@MainActor
enum TomoStartOver {
    static func confirm() {
        let lang = TomoLanguages.shared
        let alert = NSAlert()
        alert.messageText = lang.learner("startOver.title")
        alert.informativeText = lang.learner("startOver.body", ["language": lang.targetName])
        alert.addButton(withTitle: lang.learner("startOver.confirm"))
        alert.addButton(withTitle: lang.learner("startOver.cancel"))
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { TomoGame.shared.startOver() }
    }
}

enum TomoSettingsPane: String, CaseIterable, Identifiable {
    case tomo, words, general, ai, testing, about
    var id: String { rawValue }

    var titleKey: String { "settings.pane.\(rawValue)" }
    var icon: String {
        switch self {
        case .tomo:    "bird.fill"
        case .words:   "character.book.closed.fill"
        case .general: "gearshape.fill"
        case .ai:      "sparkles"
        case .testing: "flask.fill"
        case .about:   "info.circle.fill"
        }
    }
    var color: Color {
        switch self {
        case .tomo:    .orange
        case .words:   .teal
        case .general: .gray
        case .ai:      .purple
        case .testing: .pink
        case .about:   .blue
        }
    }
}

/// Which page Settings shows. TOMO_OPEN_SETTINGS=<page> (tomo, words, general, ai, testing, about) picks one.
@MainActor
final class TomoSettingsNav: ObservableObject {
    static let shared = TomoSettingsNav()
    @Published var pane: TomoSettingsPane =
        ProcessInfo.processInfo.environment["TOMO_OPEN_SETTINGS"].flatMap(TomoSettingsPane.init(rawValue:)) ?? .tomo

    /// Opens Settings at a page (the menu bar, Tomo's age in the island header).
    static func open(_ pane: TomoSettingsPane) {
        shared.pane = pane
        NotificationCenter.default.post(name: .openFullSettings, object: nil)
    }
}

struct TomoSettingsView: View {
    @ObservedObject var lang = TomoLanguages.shared
    @ObservedObject var nav = TomoSettingsNav.shared
    @ObservedObject var testing = TomoTestingTools.shared

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)
                .background(SidebarMaterial())
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text(lang.learner(nav.pane.titleKey))
                    .font(.system(size: 20, weight: .bold))
                    .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 4)
                page
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 720, minHeight: 500)
        .ignoresSafeArea(.container, edges: .top)
    }

    private var sidebar: some View {
        List(selection: Binding<TomoSettingsPane?>(get: { nav.pane }, set: { if let p = $0 { nav.pane = p } })) {
            Section { TomoProfileRow().tag(TomoSettingsPane.tomo) }
            Section { row(.words) }
            Section { row(.general); row(.ai) }
            Section {
                if testing.shown { row(.testing) }   // ⌥-click the menu bar icon (TomoTestingTools)
                row(.about)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .padding(.top, 34)                   // clear of the window's close / minimize / zoom buttons
    }

    private func row(_ pane: TomoSettingsPane) -> some View {
        HStack(spacing: 8) {
            Image(systemName: pane.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(pane.color.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(lang.learner(pane.titleKey))
        }
        .padding(.vertical, 2)
        .tag(pane)
    }

    @ViewBuilder private var page: some View {
        switch nav.pane {
        case .tomo:    TomoGrowthPane()
        case .words:   TomoWordsPane()
        case .general: TomoGeneralSettings()
        case .ai:      TomoAISettingsView()
        case .testing: TomoTestingSettings()
        case .about:   TomoAboutView()
        }
    }
}

/// The sidebar's top row, like the account row in System Settings: live Tomo, its age and level.
private struct TomoProfileRow: View {
    @ObservedObject var game = TomoGame.shared
    @ObservedObject var lang = TomoLanguages.shared

    var body: some View {
        HStack(spacing: 10) {
            TomoLiveAvatar(size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(lang.learner("settings.pane.tomo")).font(.system(size: 14, weight: .semibold))
                Text("\(game.age) · \(lang.learner("level", ["n": "\(game.level)"]))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// A small live Tomo for Settings. Tomo is never a still image: it breathes, blinks and fidgets here too.
struct TomoLiveAvatar: View {
    let size: CGFloat
    @ObservedObject var game = TomoGame.shared
    @State private var blob = TomoBlob()

    private var step: CGFloat { game.growthStep }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            Canvas { ctx, sz in
                blob.frameDate = timeline.date
                blob.step()
                blob.draw(ctx, size: sz)
            }
        }
        .frame(width: size, height: size)
        .onAppear { blob.setGrowth(step) }
        .onChange(of: game.stage) { _, _ in blob.grow(to: step) }
    }
}

/// The translucent sidebar background of System Settings.
private struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .sidebar
        v.blendingMode = .behindWindow
        v.state = .followsWindowActiveState
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Tomo: how Tomo is growing

private struct TomoGrowthPane: View {
    @ObservedObject var game = TomoGame.shared
    @ObservedObject var lang = TomoLanguages.shared

    private var progress: TomoProgress { game.progress }
    /// Each age in the pack, with its first and last level.
    private var ages: [(age: Int, from: Int, to: Int)] {
        var out: [(age: Int, from: Int, to: Int)] = []
        for (i, l) in progress.pack.levels.enumerated() {
            if let last = out.last, last.age == l.age { out[out.count - 1].to = i + 1 }
            else { out.append((l.age, i + 1, i + 1)) }
        }
        return out
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    TomoLiveAvatar(size: 76)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(game.age).font(.system(size: 22, weight: .bold))
                            Text(lang.learner("level", ["n": "\(game.level)"])).font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(lang.learner("words.days", ["n": "\(daysTogether)"])).font(.callout).foregroundStyle(.secondary)
                        }
                        // The card's bar: the goal at its end fills only when the level is done.
                        TomoGrowthBar(progress: game.levelProgress, standing: game.levelStanding,
                                      colors: [.teal.opacity(0.7), .teal], empty: Color.secondary.opacity(0.18),
                                      outline: Color.secondary.opacity(0.4))
                            .frame(height: 6)
                            .padding(.vertical, 2)
                        Text(progress.isLastLevel
                             ? lang.learner("words.lastLevel", ["known": "\(game.levelKnown)", "needed": "\(game.levelNeeded)"])
                             : lang.learner("words.toNext", ["known": "\(game.levelKnown)", "needed": "\(game.levelNeeded)",
                                                             "next": "\(game.level + 1)"]))
                            .font(.callout).foregroundStyle(.secondary)
                        // What's left, and when the next word is ready; when Tomo rests, when it's back.
                        Label { Text(game.phase == .resting ? game.restLines.left : game.whatsLeft()) } icon: {
                            Image(systemName: "flag.fill").foregroundStyle(.teal)
                        }
                        .font(.callout.weight(.medium))
                        if game.phase == .resting {
                            Label(game.restLines.back, systemImage: "clock").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
                if game.isScratch {
                    Label(lang.learner("words.testing"), systemImage: "flask").foregroundStyle(.orange)
                }
            }

            Section(lang.learner("growth.growingUp")) {
                ForEach(ages, id: \.age) { a in ageRow(a) }
            }

            Section(lang.learner("growth.today")) {
                let t = progress.today()
                LabeledContent(lang.learner("growth.newToday"),
                               value: lang.learner("growth.ofMax", ["n": "\(t.newWords)", "max": "\(TomoProgress.newPerDay)"]))
                LabeledContent(lang.learner("growth.answersToday"), value: "\(t.answers)")
                LabeledContent(lang.learner("growth.strongerToday"), value: "\(t.stronger)")
            }
            .id(game.progressVersion)

            Section {
                Button(lang.learner("settings.restart"), role: .destructive) { TomoStartOver.confirm() }
            } footer: {
                Text(lang.learner("settings.restartNote")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var daysTogether: Int {
        max(1, (Calendar.current.dateComponents([.day], from: progress.metAt, to: TomoClock.now).day ?? 0) + 1)
    }

    private func ageRow(_ a: (age: Int, from: Int, to: Int)) -> some View {
        let state = a.age < game.stage ? "grown" : a.age == game.stage ? "now" : "later"
        let levels = a.from == a.to ? lang.learner("level", ["n": "\(a.from)"])
            : lang.learner("growth.levels", ["from": "\(a.from)", "to": "\(a.to)"])
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: state == "grown" ? "checkmark.circle.fill" : state == "now" ? "location.circle.fill" : "lock.circle")
                .font(.system(size: 16))
                .foregroundStyle(state == "grown" ? Color.teal : state == "now" ? Color.orange : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(lang.target.ageLabel(a.age)).font(.headline)
                    Text(levels).font(.caption).foregroundStyle(.secondary)
                }
                Text(lang.learner("growth.age.\(min(a.age, 6))")).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Text(lang.learner("growth.state.\(state)")).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .opacity(state == "later" ? 0.65 : 1)
    }
}

// MARK: - General

private struct TomoGeneralSettings: View {
    @ObservedObject var lang = TomoLanguages.shared
    @ObservedObject var state = AppState.shared
    @State private var visitEvery = DropIn.every
    @State private var newPerDay = TomoProgress.newPerDay

    var body: some View {
        Form {
            Section {
                Picker(lang.learner("settings.speak"), selection: Binding(
                    get: { lang.learner.id },
                    set: { lang.select(learner: $0); TomoGame.shared.reload() })) {
                    ForEach(lang.learners, id: \.id) { Text($0.name).tag($0.id) }
                }
                Picker(lang.learner("settings.learning"), selection: Binding(
                    get: { lang.target.id },
                    set: { lang.select(target: $0); TomoGame.shared.reload() })) {
                    ForEach(lang.targets, id: \.id) { t in
                        Text("\(t.name(lang.learner.id)) (\(t.nativeName))"
                             + (t.reviewedByNativeSpeaker ? "" : " · \(lang.learner("settings.draft"))")).tag(t.id)
                    }
                }
            } footer: {
                Text(lang.learner("settings.learningNote")).font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Picker(lang.learner("settings.visits"), selection: $visitEvery) {
                    ForEach(DropIn.choices, id: \.seconds) { Text(lang.learner($0.key)).tag($0.seconds) }
                }
                .onChange(of: visitEvery) { _, v in DropIn.setEvery(v); TomoGame.shared.rescheduleVisits() }
                Picker(lang.learner("settings.newPerDay"), selection: $newPerDay) {
                    ForEach(TomoProgress.newPerDayChoices, id: \.self) { Text("\($0)").tag($0) }
                }
                .onChange(of: newPerDay) { _, v in UserDefaults.standard.set(v, forKey: "tomoNewPerDay") }
                Toggle(lang.learner("settings.voice"), isOn: $state.soundEnabled)
            }

            Section {
                Toggle(lang.learner("settings.openAtLogin"), isOn: Binding(
                    get: { openAtLogin },
                    set: { openAtLogin = TomoLoginItem.set($0); loginNeedsApproval = TomoLoginItem.needsApproval }))
                if loginNeedsApproval {
                    HStack {
                        Text(lang.learner("settings.openAtLoginApprove")).font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button(lang.learner("settings.openLoginItems")) { TomoLoginItem.openSystemSettings() }
                    }
                }
            } footer: {
                Text(lang.learner("settings.openAtLoginNote")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {   // the learner may have changed it in System Settings → Login Items
            openAtLogin = TomoLoginItem.isOn
            loginNeedsApproval = TomoLoginItem.needsApproval
        }
    }

    @State private var openAtLogin = TomoLoginItem.isOn
    @State private var loginNeedsApproval = TomoLoginItem.needsApproval
}

// MARK: - Testing

private struct TomoTestingSettings: View {
    @ObservedObject var lang = TomoLanguages.shared
    @ObservedObject var game = TomoGame.shared

    var body: some View {
        Form {
            Section {
                Picker(lang.learner("settings.tryAge"), selection: Binding(
                    get: { game.stage },
                    set: { game.jump(toAge: $0) })) {
                    ForEach([1, 2, 3, 5, 7, 10, 12], id: \.self) { Text(lang.target.ageLabel($0)).tag($0) }
                }
                if game.isScratch {
                    Button(lang.learner("settings.backToTomo")) { game.reload() }
                }
            }
            Section {
                Button(lang.learner("settings.skipAhead")) { game.skipAhead(days: 1) }
                if TomoClock.offset > 0 {
                    Text(lang.learner("settings.clockAhead", ["n": String(format: "%.1f", TomoClock.offset / 86400)]))
                        .font(.callout).foregroundStyle(.secondary)
                }
            } footer: {
                Text(lang.learner("settings.testingNote")).font(.caption).foregroundStyle(.secondary)
            }
            .id(game.progressVersion)
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

private struct TomoAboutView: View {
    @ObservedObject var lang = TomoLanguages.shared
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("Tomodachi").font(.title2.bold())
            Text(lang.learner("about.by")).font(.callout.weight(.medium)).foregroundStyle(.secondary)
            Text(lang.learner("about.version", ["v": version])).foregroundStyle(.secondary)
            Text(lang.learner("about.tagline")).multilineTextAlignment(.center)
            Text(lang.learner("about.feedback")).font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Divider().padding(.vertical, 4)
            Text(lang.learner("about.credits")).font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
    }
}
