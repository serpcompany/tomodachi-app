import SwiftUI

// MARK: - Settings for reminders (issue #88): on/off, the rhythm, quiet hours, and Tomo's Lock Screen card
//
// Self-contained: it reads and writes TomoReminderCenter.shared.settings, which saves and schedules again on every
// change. `TomoReminderSettingsView.Sections()` is the rows for a host with a Form of its own (the iPhone's Settings,
// TomoSettingsScreen's `device` slot); `TomoReminderSettingsView()` is a page with its own Form. Turning reminders on
// asks iOS first if it hasn't been asked; if notifications are off for the app in iOS Settings, it says so and links
// there. All text is in ui.<id>.json.

public struct TomoReminderSettingsView: View {
    private let showsLockScreen: Bool

    /// `showsLockScreen`: include the Lock Screen card's switch (iPhone).
    public init(showsLockScreen: Bool = true) { self.showsLockScreen = showsLockScreen }

    public var body: some View {
        Form { Sections(showsLockScreen: showsLockScreen) }
            .navigationTitle(TomoLanguages.shared.learner("reminders.settings.title"))
    }

    public struct Sections: View {
        @ObservedObject private var center = TomoReminderCenter.shared
        @ObservedObject private var lang = TomoLanguages.shared
        @Environment(\.openURL) private var openURL
        @State private var asking = false
        private let showsLockScreen: Bool

        public init(showsLockScreen: Bool = true) { self.showsLockScreen = showsLockScreen }

        private func ui(_ key: String, _ args: [String: String] = [:]) -> String { lang.learner(key, args) }
        private var denied: Bool { center.permission == .denied }

        public var body: some View {
            Section {
                Toggle(ui("reminders.settings.on"), isOn: Binding(get: { center.settings.on && !denied }, set: turn))
                    .disabled(asking)
                if denied {
                    Text(ui("reminders.settings.denied")).font(.footnote).foregroundStyle(.secondary)
                    #if os(iOS)
                    Button(ui("reminders.settings.openSettings")) {
                        if let url = URL(string: "app-settings:") { openURL(url) }   // UIApplication.openSettingsURLString
                    }
                    #endif
                }
                Picker(ui("reminders.settings.rhythm"), selection: $center.settings.every) {
                    ForEach(TomoReminders.choices.indices, id: \.self) { i in
                        let c = TomoReminders.choices[i]
                        Text(ui("reminders.every.\(c.key)") + " · " + ui("reminders.tag.\(c.key)")).tag(c.every)
                    }
                }
            } footer: {
                Text(TomoReminders.summary(center.settings) + " " + ui("reminders.settings.backOff"))
            }
            .task { await center.refreshPermission() }

            QuietHours(forVisits: false)

            if showsLockScreen {
                Section {
                    Toggle(ui("reminders.settings.lockScreen"), isOn: $center.settings.lockScreen)
                } footer: {
                    Text(ui("reminders.settings.lockScreenNote"))
                }
            }
        }

        /// On: ask iOS first if it hasn't been asked (the reason is the switch's own label). Off: no more reminders.
        private func turn(_ on: Bool) {
            guard on else { center.settings.on = false; return }
            Task { @MainActor in
                asking = true
                await center.refreshPermission()
                let granted = center.permission == .notDetermined ? await center.askPermission()
                    : center.permission == .authorized || center.permission == .provisional
                asking = false
                center.settings.on = granted
            }
        }
    }
}

extension TomoReminderSettingsView {
    /// Quiet hours, on its own: the iPhone's reminders keep them, and so do the Mac's visits by the notch
    /// (`forVisits`, the Mac's Settings), from the same setting.
    public struct QuietHours: View {
        @ObservedObject private var center = TomoReminderCenter.shared
        @ObservedObject private var lang = TomoLanguages.shared
        private let forVisits: Bool

        public init(forVisits: Bool) { self.forVisits = forVisits }

        private func ui(_ key: String) -> String { lang.learner(key) }

        public var body: some View {
            Section {
                Toggle(ui(forVisits ? "reminders.settings.quietOn.mac" : "reminders.settings.quietOn"),
                       isOn: Binding(get: { center.settings.hasQuietHours }, set: { on in
                    let standard = TomoReminderSettings.standard
                    center.settings.quietFrom = on ? standard.quietFrom : 0
                    center.settings.quietUntil = on ? standard.quietUntil : 0
                }))
                if center.settings.hasQuietHours {
                    DatePicker(ui("reminders.settings.from"), selection: TomoReminders.timeOfDay($center.settings.quietFrom),
                               displayedComponents: .hourAndMinute)
                    DatePicker(ui("reminders.settings.until"), selection: TomoReminders.timeOfDay($center.settings.quietUntil),
                               displayedComponents: .hourAndMinute)
                }
            } header: {
                Text(ui("reminders.settings.quiet"))
            } footer: {
                if forVisits { Text(ui("reminders.settings.quietNote.mac")) }
            }
            .environment(\.locale, Locale(identifier: lang.learner.id))
        }
    }
}
