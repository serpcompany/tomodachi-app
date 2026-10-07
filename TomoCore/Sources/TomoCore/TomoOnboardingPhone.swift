import SwiftUI

// MARK: - The first run's iPhone steps (issue #88)
//
// How Tomo comes to you on the iPhone, following the reference app (#83) screen for screen: a reminder from Tomo on
// the Lock Screen; "Set your rhythm" (how often a reminder may come, with how many times that is in a year); quiet
// hours; "Let words find you", whose button is the only place the iOS notification prompt appears; how to add a
// widget, on the Lock Screen or the Home Screen; and Tomo's Lock Screen card, yes or not now. The flow and its
// choices are in TomoOnboarding; what the reminders do with them is TomoReminders. The sketches of the iPhone's
// screens are drawn here, and the one live Tomo of the flow moves into them (`tomoOffset`).

enum WidgetTab: Hashable { case lockScreen, homeScreen }

/// Sizes and Tomo's place in the sketches, before they're scaled to the screen (`fit`).
enum PhoneSketches {
    static let notificationHero: CGFloat = 164
    static let notificationTomo: CGFloat = 50
    static let cardHero: CGFloat = 178
    static let cardTomo: CGFloat = 64
    static let phoneHero: CGFloat = 232
    static let phoneX: CGFloat = -40                 // the phone sits left of centre, Tomo beside it

    /// The sketch's width: the screen's, up to 340, before scaling.
    static func width(_ available: CGFloat, fit: CGFloat) -> CGFloat { min(available / max(fit, 0.1), 340) }
    static func notificationSlot(width: CGFloat, fit: CGFloat) -> CGSize {
        CGSize(width: (-Self.width(width, fit: fit) / 2 + 36) * fit, height: 34 * fit)
    }
    static func cardSlot(width: CGFloat, fit: CGFloat) -> CGSize {
        CGSize(width: (-Self.width(width, fit: fit) / 2 + 46) * fit, height: 38 * fit)
    }
    static func besidePhone(fit: CGFloat) -> CGSize { CGSize(width: 88 * fit, height: 56 * fit) }
}

extension TomoOnboardingView {

    // MARK: Hero: the iPhone's screens, sketched

    @ViewBuilder func phoneSketch(in size: CGSize) -> some View {
        let w = PhoneSketches.width(size.width, fit: fit)
        switch step {
        case .visits:
            NotificationSketch(width: w, app: appName, title: reminderLine?.say ?? lang.target.lines.invite ?? "",
                               message: reminderMessage, now: ui("onboarding.sketch.now"))
                .scaleEffect(fit)
        case .lockScreen:
            LockCardSketch(width: w, status: ui("glance.new"), age: game.age, level: ui("level", ["n": "\(game.level)"]),
                           progress: game.levelProgress)
                .scaleEffect(fit)
        case .widget:
            PhoneScreenSketch(tab: widgetTab, app: appName, age: game.age, level: ui("level", ["n": "\(game.level)"]),
                              status: ui("glance.new"), progress: game.levelProgress)
                .scaleEffect(fit)
                .offset(x: PhoneSketches.phoneX * fit)
        case .notify:
            Image(systemName: "bell.fill")
                .font(.system(size: 30 * fit, weight: .bold))
                .foregroundStyle(Paint.accent)
                .symbolEffect(.wiggle, options: .repeating)
                .offset(x: 64 * fit, y: -36 * fit)
        case .login:
            Image(systemName: "sunrise.fill")
                .font(.system(size: 30 * fit, weight: .bold))
                .foregroundStyle(Paint.accent)
                .symbolEffect(.breathe, options: .repeating)
                .offset(x: 66 * fit, y: -34 * fit)
        case .quiet:
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 28 * fit, weight: .bold))
                .foregroundStyle(Color(hex: "#C4B5FD"))
                .symbolEffect(.breathe, options: .repeating)
                .offset(x: -66 * fit, y: -34 * fit)
        default:
            EmptyView()
        }
    }

    /// Which how-to the widget step shows.
    var widgetTab: WidgetTab { model.widgetOnHomeScreen ? .homeScreen : .lockScreen }

    private var appName: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "" }
    private var reminderLine: TargetPack.SpokenLine? { lang.target.reminderLines(age: game.stage).first }
    private var reminderMessage: String {
        let status = ui("glance.new")
        guard let line = reminderLine else { return status }
        return ui("reminder.body", ["line": line.translation(lang.learner.id), "status": status])
    }

    // MARK: Pages

    var phoneVisitsPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            title(ui("onboarding.visits.title"))
            bodyText(ui("onboarding.visits.phone.body"))
            VStack(alignment: .leading, spacing: 10) {
                row(icon: "bell.badge.fill", ui("onboarding.visits.phone.notify"))
                row(icon: "lock.iphone", ui("onboarding.visits.phone.lock"))
                row(icon: "moon.zzz.fill", ui("onboarding.visits.phone.quiet"))
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var phoneRhythmPage: some View {
        VStack(alignment: .leading, spacing: 8) {
            title(ui("onboarding.rhythm.title"))
            bodyText(ui("onboarding.rhythm.phone.body"))
            VStack(spacing: 6) {
                ForEach(TomoReminders.choices.indices, id: \.self) { i in
                    let c = TomoReminders.choices[i]
                    RhythmRow(title: ui("reminders.every.\(c.key)"), tag: ui("reminders.tag.\(c.key)"),
                              selected: model.reminders.every == c.every, height: 36 + 6 * fit) {
                        model.reminders.every = c.every
                    }
                }
            }
            .padding(.top, 2)
            yearPanel.padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The reference's "4,745 words in the next year": how many times Tomo can find you, at most.
    private var yearPanel: some View {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: lang.learner.id)
        let year = f.string(from: NSNumber(value: TomoReminders.perDay(model.reminders) * 365)) ?? ""
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(year).font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(Paint.accent)
                    .contentTransition(.numericText())
                Text(ui("onboarding.rhythm.year")).font(.system(size: 13, weight: .semibold))
                    .lineLimit(2).minimumScaleFactor(0.8)
            }
            Text(TomoReminders.summary(model.reminders)).font(.system(size: 12)).foregroundStyle(Paint.soft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Paint.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        .animation(.easeInOut(duration: 0.25), value: model.reminders.every)
    }

    var quietPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            title(ui("onboarding.quiet.title"))
            bodyText(ui(isPhone ? "onboarding.quiet.body" : "onboarding.quiet.body.mac"))
            HStack(spacing: 12) {
                timeBox(ui("onboarding.quiet.from"), minutes: $model.reminders.quietFrom)
                timeBox(ui("onboarding.quiet.until"), minutes: $model.reminders.quietUntil)
            }
            .padding(14)
            .background(Paint.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08)))
            Text(ui("onboarding.quiet.note")).font(.system(size: 13)).foregroundStyle(Paint.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func timeBox(_ label: String, minutes: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(.system(size: 11, weight: .heavy)).kerning(1).foregroundStyle(Paint.faint)
            DatePicker(label, selection: TomoReminders.timeOfDay(minutes), displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.compact)
                .environment(\.locale, Locale(identifier: lang.learner.id))
                .colorScheme(.dark)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var notifyPage: some View {
        let s = model.reminders
        return VStack(alignment: .leading, spacing: 12) {
            title(ui("onboarding.notify.title"))
            bodyText(ui("onboarding.notify.body", ["every": ui("reminders.phrase." + TomoReminders.key(for: s.every))]))
            VStack(alignment: .leading, spacing: 10) {
                if s.hasQuietHours {
                    row(icon: "moon.zzz.fill", ui("onboarding.notify.quiet", ["from": TomoReminders.clock(s.quietFrom),
                                                                             "until": TomoReminders.clock(s.quietUntil)]))
                }
                row(icon: "hand.raised.fill", ui("onboarding.notify.guilt"))
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var widgetPage: some View {
        let tab = widgetTab == .lockScreen ? "lock" : "home"
        return VStack(alignment: .leading, spacing: 10) {
            title(ui("onboarding.widget.title"))
            HStack(spacing: 4) {
                tabButton(ui("onboarding.widget.tab.lock"), .lockScreen)
                tabButton(ui("onboarding.widget.tab.home"), .homeScreen)
            }
            .padding(3)
            .background(Paint.card, in: Capsule())
            VStack(alignment: .leading, spacing: 7) {
                ForEach(1...3, id: \.self) { n in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(n)").font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(Paint.accent)
                            .frame(width: 20, height: 20)
                            .background(Paint.accent.opacity(0.16), in: Circle())
                        Text(ui("onboarding.widget.\(tab).\(n)")).font(.system(size: 14)).foregroundStyle(Paint.soft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .id(tab)
            .transition(.opacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.25), value: widgetTab)
    }

    private func tabButton(_ label: String, _ tab: WidgetTab) -> some View {
        Button { model.widgetOnHomeScreen = tab == .homeScreen } label: {
            Text(label).font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(widgetTab == tab ? Color(hex: "#211A05") : Paint.soft)
                .frame(maxWidth: .infinity).frame(height: 30)
                .background(widgetTab == tab ? Paint.accent : Color.clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Mac: "Let Tomo find you" is opening Tomodachi at login. The reason first, then the switch, on but shown.
    var loginPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            title(ui("onboarding.login.title"))
            bodyText(ui("onboarding.login.body"))
            HStack {
                Text(ui("onboarding.login.toggle")).font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 8)
                Toggle(ui("onboarding.login.toggle"), isOn: $model.openAtLogin)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(Paint.accent)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Paint.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08)))
            Text(ui("onboarding.login.note")).font(.system(size: 13)).foregroundStyle(Paint.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var lockScreenPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            title(ui("onboarding.lock.title"))
            bodyText(ui("onboarding.lock.body"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Sketches (drawn live; Tomo itself is the flow's one TomoBlobView, moved into place)

/// The time on a Lock Screen, big.
private struct LockTime: View {
    var size: CGFloat = 54
    var body: some View {
        TimelineView(.everyMinute) { t in
            Text(t.date, format: .dateTime.hour().minute())
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.88))
        }
    }
}

/// A notification from Tomo on the Lock Screen. Tomo sits on the app icon's spot (`PhoneSketches.notificationSlot`).
private struct NotificationSketch: View {
    let width: CGFloat
    let app: String
    let title: String
    let message: String
    let now: String

    var body: some View {
        ZStack {
            LockTime().offset(y: -46)
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 11)
                    .fill(LinearGradient(colors: [Color(hex: "#7DD3FC"), Color(hex: "#38BDF8")], startPoint: .top, endPoint: .bottom))
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(app).font(.system(size: 13, weight: .semibold))
                        Spacer(minLength: 4)
                        Text(now).font(.system(size: 12)).foregroundStyle(Paint.faint)
                    }
                    Text(title).font(.system(size: 14, weight: .bold)).lineLimit(1)
                    Text(message).font(.system(size: 13)).foregroundStyle(Paint.soft).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .padding(.horizontal, 14)
            .frame(width: width, height: 76)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color.white.opacity(0.13)))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.1)))
            .offset(y: 34)
        }
    }
}

/// Tomo's Lock Screen card (the Live Activity): what's waiting, age and level, the bar, and ▶.
private struct LockCardSketch: View {
    let width: CGFloat
    let status: String
    let age: String
    let level: String
    let progress: Double

    var body: some View {
        ZStack {
            LockTime().offset(y: -52)
            HStack(spacing: 12) {
                Color.clear.frame(width: 64, height: 64)            // Tomo's spot
                VStack(alignment: .leading, spacing: 6) {
                    Text(status).font(.system(size: 14, weight: .bold)).lineLimit(2).minimumScaleFactor(0.8)
                    HStack(spacing: 6) {
                        Text(age).font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: "#FFD9A8"))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(hex: "#4A3424"), in: Capsule())
                        Text(level).font(.system(size: 11, weight: .semibold)).foregroundStyle(Paint.soft)
                    }
                    TomoGrowthBar(progress: progress, standing: progress,
                                  colors: [Color(hex: "#FFE68C"), Color(hex: "#34D399")])
                        .frame(height: 5)
                }
                Circle().fill(Paint.accent).frame(width: 42, height: 42)
                    .overlay(Image(systemName: "play.fill").font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(hex: "#211A05")))
            }
            .padding(.horizontal, 14)
            .frame(width: width, height: 100)
            .background(RoundedRectangle(cornerRadius: 24).fill(Color.black.opacity(0.45)))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.12)))
            .offset(y: 38)
        }
    }
}

/// A small iPhone showing where the widget goes: under the time on the Lock Screen, or on the Home Screen. The
/// Home Screen widget shows the mascot, like the real one, drawn live.
private struct PhoneScreenSketch: View {
    let tab: WidgetTab
    let app: String
    let age: String
    let level: String
    let status: String
    let progress: Double
    @State private var pulse = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .fill(LinearGradient(colors: [Color(hex: "#4C3A8F"), Color(hex: "#25407A"), Color(hex: "#101C36")],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 28).stroke(Color.white.opacity(0.3), lineWidth: 2)
            Capsule().fill(Color.black).frame(width: 44, height: 13).offset(y: -100)
            if tab == .lockScreen { lockScreen } else { homeScreen }
        }
        .frame(width: 140, height: 228)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private var ring: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(Paint.accent, lineWidth: 2)
            .opacity(pulse ? 0.95 : 0.25)
            .scaleEffect(pulse ? 1.06 : 1)
    }

    private var lockScreen: some View {
        ZStack {
            LockTime(size: 32).offset(y: -62)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(age) · \(level)").font(.system(size: 9, weight: .bold, design: .rounded))
                TomoGrowthBar(progress: progress, standing: progress, colors: [Color.white, Color.white], gap: 2)
                    .frame(height: 3)
                Text(status).font(.system(size: 8, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(6)
            .frame(width: 104, height: 42)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.18)))
            .overlay(ring)
            .offset(y: -22)
        }
    }

    private var homeScreen: some View {
        ZStack {
            VStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 10) {
                        ForEach(0..<4, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.17)).frame(width: 20, height: 20)
                        }
                    }
                }
            }
            .offset(y: -48)
            HStack(spacing: 6) {
                TomoBlobView(state: .idle, growth: 0, look: .mascot).frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app).font(.system(size: 9, weight: .bold, design: .rounded))
                    Text(status).font(.system(size: 8, weight: .semibold)).foregroundStyle(Paint.soft)
                        .lineLimit(2).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(width: 116, height: 54)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "#12202A")))
            .overlay(ring)
            .offset(y: 46)
        }
    }
}
