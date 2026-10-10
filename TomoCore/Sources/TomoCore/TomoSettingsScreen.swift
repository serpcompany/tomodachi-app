import SwiftUI

// MARK: - Settings, the same on the Mac and the iPhone
//
// How often Tomo visits and how a visit starts (the Mac's), new words a day, Tomo's voice and sounds; what only this device has (the `device`
// slot: open at login on the Mac, reminders and the Lock Screen card on the iPhone); the language Tomodachi's text is in; and Start over, which always
// asks first (`TomoScreenNav.confirmingStartOver`, so the Mac's menu bar item asks the same way). The "I'm learning"
// picker shows only with the testing tools (TomoFeatures): the MVP is Japanese only. `more` goes at the end (the
// iPhone's link to About).

public struct TomoSettingsScreen<Device: View, More: View>: View {
    @ObservedObject var lang = TomoLanguages.shared
    @ObservedObject var game = TomoGame.shared
    @ObservedObject var nav = TomoScreenNav.shared
    @ObservedObject var features = TomoFeatures.shared
    @State private var visitEvery = DropIn.every
    @State private var peekFirst = DropIn.peekFirst
    @State private var newPerDay = TomoProgress.newPerDay
    private let afterStartOver: (() -> Void)?
    private let device: Device
    private let more: More

    /// `afterStartOver`: what the shell does once the new Tomo is there (the iPhone shows it on the play tab).
    public init(afterStartOver: (() -> Void)? = nil, @ViewBuilder device: () -> Device, @ViewBuilder more: () -> More) {
        self.afterStartOver = afterStartOver
        self.device = device()
        self.more = more()
    }

    public var body: some View {
        Form {
            Section {
                #if os(macOS)
                // The iPhone's cadence is its reminders (the `device` slot, TomoReminderSettingsView): visits by the
                // notch are the Mac's.
                Picker(lang.learner("settings.visits"), selection: $visitEvery) {
                    ForEach(DropIn.choices, id: \.seconds) { Text(lang.learner($0.key)).tag($0.seconds) }
                }
                .onChange(of: visitEvery) { _, v in DropIn.setEvery(v); game.rescheduleVisits() }
                // How a visit starts: a peek by the notch that opens when pointed at or clicked, or the card (the
                // default; #19).
                Picker(lang.learner("settings.visitStart"), selection: $peekFirst) {
                    Text(lang.learner("settings.visitStart.peek")).tag(true)
                    Text(lang.learner("settings.visitStart.open")).tag(false)
                }
                .onChange(of: peekFirst) { _, v in DropIn.setPeekFirst(v) }
                #endif
                Picker(lang.learner("settings.newPerDay"), selection: $newPerDay) {
                    ForEach(TomoProgress.newPerDayChoices, id: \.self) { Text("\($0)").tag($0) }
                }
                .onChange(of: newPerDay) { _, v in UserDefaults.standard.set(v, forKey: "tomoNewPerDay") }
                Toggle(lang.learner("settings.voice"), isOn: $game.soundEnabled)
            }

            device

            Section {
                Picker(lang.learner("settings.speak"), selection: Binding(
                    get: { lang.learner.id },
                    set: { lang.select(learner: $0); game.reload() })) {
                    ForEach(lang.learners, id: \.id) { Text($0.name).tag($0.id) }
                }
                if features.targetPicker(current: lang.target.id) {
                    Picker(lang.learner("settings.learning"), selection: Binding(
                        get: { lang.target.id },
                        set: { lang.select(target: $0); game.reload() })) {
                        ForEach(lang.targets, id: \.id) { t in
                            Text("\(t.name(lang.learner.id)) (\(t.nativeName))"
                                 + (t.reviewedByNativeSpeaker ? "" : " · \(lang.learner("settings.draft"))")).tag(t.id)
                        }
                    }
                }
            } footer: {
                Text(features.targetPicker(current: lang.target.id) ? lang.learner("settings.learningNote")
                     : lang.learner("settings.languageNote", ["language": lang.targetName]))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Button(lang.learner("settings.restart"), role: .destructive) { nav.confirmingStartOver = true }
            } footer: {
                Text(lang.learner("settings.restartNote")).font(.caption).foregroundStyle(.secondary)
            }

            more
        }
        .formStyle(.grouped)
        .alert(lang.learner("startOver.title"), isPresented: $nav.confirmingStartOver) {
            Button(lang.learner("startOver.confirm"), role: .destructive) {
                game.startOver()
                afterStartOver?()
            }
            Button(lang.learner("startOver.cancel"), role: .cancel) {}
        } message: {
            Text(lang.learner("startOver.body", ["language": lang.targetName]))
        }
    }
}

extension TomoSettingsScreen where Device == EmptyView, More == EmptyView {
    public init(afterStartOver: (() -> Void)? = nil) {
        self.init(afterStartOver: afterStartOver, device: { EmptyView() }, more: { EmptyView() })
    }
}
