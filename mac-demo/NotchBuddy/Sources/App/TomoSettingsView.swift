import SwiftUI

// MARK: - Settings window (menu → Settings…): General · AI · About
// All text comes from the learner's interface strings (Resources/languages/ui.<id>.json).

struct TomoSettingsView: View {
    @ObservedObject var lang = TomoLanguages.shared

    var body: some View {
        TabView {
            TomoGeneralSettings()
                .tabItem { Label(lang.learner("settings.general"), systemImage: "gearshape") }
            TomoAISettingsView()
                .tabItem { Label(lang.learner("settings.ai"), systemImage: "sparkles") }
            TomoAboutView()
                .tabItem { Label(lang.learner("settings.about"), systemImage: "info.circle") }
        }
        .frame(width: 520)
        .padding(.top, 8)
    }
}

private struct TomoGeneralSettings: View {
    @ObservedObject var lang = TomoLanguages.shared
    @ObservedObject var state = AppState.shared
    @State private var visitEvery = DropIn.every

    var body: some View {
        Form {
            Section {
                Picker(lang.learner("settings.speak"), selection: Binding(
                    get: { lang.learner.id },
                    set: { lang.select(learner: $0) })) {
                    ForEach(lang.learners, id: \.id) { Text($0.name).tag($0.id) }
                }
                Picker(lang.learner("settings.learning"), selection: Binding(
                    get: { lang.target.id },
                    set: { lang.select(target: $0); TomoGame.shared.restart() })) {
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
                Toggle(lang.learner("settings.voice"), isOn: $state.soundEnabled)
            }

            Section {
                Picker(lang.learner("settings.tryAge"), selection: Binding(
                    get: { TomoGame.shared.stage },
                    set: { TomoGame.shared.jump(toAge: $0) })) {
                    ForEach([1, 2, 3, 5, 7, 10, 12], id: \.self) { Text(lang.target.ageLabel($0)).tag($0) }
                }
                Button(lang.learner("settings.restart")) { TomoGame.shared.restart() }
            } footer: {
                Text(lang.learner("settings.restartNote")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct TomoAboutView: View {
    @ObservedObject var lang = TomoLanguages.shared
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("Tomodachi").font(.title2.bold())
            Text(lang.learner("about.version", ["v": version])).foregroundStyle(.secondary)
            Text(lang.learner("about.tagline")).multilineTextAlignment(.center)
            Text(lang.learner("about.feedback")).font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Divider().padding(.vertical, 4)
            Text(lang.learner("about.credits")).font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}
