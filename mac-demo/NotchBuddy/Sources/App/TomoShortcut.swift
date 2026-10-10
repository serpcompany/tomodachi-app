import AppKit
import Carbon.HIToolbox
import SwiftUI
import TomoCore

// MARK: - A global shortcut to play (#130 batch 3; a Mac-only Setting)
//
// A key combination the learner records in Settings opens Tomo to play from any app, as a click on Tomo does: free play,
// and the island takes the keyboard, so Esc closes it. It's a Carbon hot key (`RegisterEventHotKey`), which needs no
// Accessibility permission. There's none by default: a hot key takes its combination from every app on the Mac, so only
// the learner picks one. Visits still never take a keystroke. The rules (what can be recorded, what's taken, how it's
// saved, what a press does in each island state) are pure and checked by TomoIslandSelfTest; headless runs never
// register a hot key, so a test run can't take the owner's.

struct TomoShortcut: Codable, Equatable {
    /// The key's position (a virtual key code, the same on every keyboard layout), what it types without modifiers
    /// (for its name: "T"), and the modifiers (Carbon's: cmdKey, shiftKey, optionKey, controlKey).
    var keyCode: UInt32
    var character: String
    var carbonModifiers: UInt32

    static let key = "tomoPlayShortcut"
    /// The shortcut changed (TomoHotKey registers it again).
    static let changed = Notification.Name("TomoShortcutChanged")

    // MARK: Saving

    /// Saved as JSON on this Mac; anything that doesn't read back is no shortcut.
    var saved: String { (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "" }

    init(keyCode: UInt32, character: String, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.character = character
        self.carbonModifiers = carbonModifiers
    }

    init?(saved: String?) {
        guard let data = saved?.data(using: .utf8),
              let s = try? JSONDecoder().decode(TomoShortcut.self, from: data),
              s.keyCode < 128, s.carbonModifiers & Self.anyModifier != 0 else { return nil }
        self = s
    }

    /// The learner's shortcut, or none. TOMO_SHORTCUT=<saved JSON> stands in for it in test runs, without saving.
    static var current: TomoShortcut? {
        if let forced = ProcessInfo.processInfo.environment["TOMO_SHORTCUT"] { return TomoShortcut(saved: forced) }
        return TomoShortcut(saved: UserDefaults.standard.string(forKey: key))
    }

    static func set(_ shortcut: TomoShortcut?) {
        if let shortcut { UserDefaults.standard.set(shortcut.saved, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
        NotificationCenter.default.post(name: changed, object: nil)
    }

    // MARK: Modifiers

    static let command = UInt32(cmdKey), shift = UInt32(shiftKey), option = UInt32(optionKey), control = UInt32(controlKey)
    /// What a shortcut needs at least one of: ⇧ alone is typing.
    static let anyModifier = command | option | control

    static func carbon(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= command }
        if flags.contains(.shift) { m |= shift }
        if flags.contains(.option) { m |= option }
        if flags.contains(.control) { m |= control }
        return m
    }

    // MARK: Recording

    enum Rejection: Equatable {
        /// It needs ⌘, ⌃ or ⌥ (a key alone, or with ⇧ alone, is typing).
        case needsModifier
        /// macOS uses it (Spotlight, input sources, Mission Control, the lock screen…).
        case system
        /// Most apps use it: ⌘ (or ⌘⇧) with one key.
        case common
    }

    enum Recorded: Equatable {
        case set(TomoShortcut)
        case cancel        // Esc: keep what was there
        case clear         // Delete: no shortcut
        case rejected(Rejection)
    }

    /// What a key pressed while recording does.
    static func record(keyCode: UInt32, modifiers: UInt32, character: String) -> Recorded {
        if keyCode == UInt32(kVK_Escape) && modifiers & anyModifier == 0 { return .cancel }
        if (keyCode == UInt32(kVK_Delete) || keyCode == UInt32(kVK_ForwardDelete)) && modifiers & anyModifier == 0 {
            return .clear
        }
        let s = TomoShortcut(keyCode: keyCode, character: character.uppercased(), carbonModifiers: modifiers)
        if let why = s.rejection { return .rejected(why) }
        return .set(s)
    }

    /// Why this combination can't be Tomo's, or nil if it can.
    var rejection: Rejection? {
        let m = carbonModifiers & (Self.anyModifier | Self.shift)
        if m & Self.anyModifier == 0 || Self.modifierKeys.contains(keyCode) { return .needsModifier }
        if keyCode == UInt32(kVK_Escape) { return .system }   // ⌥⌘Esc is Force Quit; Esc closes Tomo
        if Self.system.contains(where: { $0.key == keyCode && $0.modifiers == m }) { return .system }
        if m == Self.command || m == Self.command | Self.shift { return .common }
        return nil
    }

    /// The modifier keys themselves, which can't be the shortcut's key.
    static let modifierKeys: Set<UInt32> = [kVK_Command, kVK_RightCommand, kVK_Shift, kVK_RightShift, kVK_Option,
                                            kVK_RightOption, kVK_Control, kVK_RightControl, kVK_CapsLock, kVK_Function]
        .map { UInt32($0) }.reduce(into: []) { $0.insert($1) }

    /// Combinations macOS keeps for itself, beyond ⌘ or ⌘⇧ with one key: switching input sources (which Japanese learners
    /// use all day), Spotlight and Finder search, emoji, Mission Control and Spaces, the lock screen, full screen, Dock
    /// hiding, look up, hide others, minimise all, close all, and keyboard navigation.
    static let system: [(key: UInt32, modifiers: UInt32)] = {
        let space = UInt32(kVK_Space)
        var list: [(UInt32, UInt32)] = [
            (space, control), (space, control | option), (space, option | command), (space, control | command),
            (UInt32(kVK_ANSI_Q), control | command), (UInt32(kVK_ANSI_F), control | command),
            (UInt32(kVK_ANSI_D), control | command), (UInt32(kVK_ANSI_D), option | command),
            (UInt32(kVK_ANSI_H), option | command), (UInt32(kVK_ANSI_M), option | command),
            (UInt32(kVK_ANSI_W), option | command), (UInt32(kVK_F2), control), (UInt32(kVK_F3), control),
        ]
        for arrow in [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow] {
            list.append((UInt32(arrow), control))
        }
        return list.map { (key: $0.0, modifiers: $0.1) }
    }()

    // MARK: Showing it

    /// Its name, as macOS writes shortcuts: ⌃⌥⇧⌘ then the key ("⌃⌥T"). The space bar's name comes from the pack.
    @MainActor func label(_ lang: TomoLanguages) -> String {
        var s = ""
        if carbonModifiers & Self.control != 0 { s += "⌃" }
        if carbonModifiers & Self.option != 0 { s += "⌥" }
        if carbonModifiers & Self.shift != 0 { s += "⇧" }
        if carbonModifiers & Self.command != 0 { s += "⌘" }
        return s + keyName(lang)
    }

    @MainActor private func keyName(_ lang: TomoLanguages) -> String {
        switch Int(keyCode) {
        case kVK_Space: return lang.learner("shortcut.space")
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default:
            if let n = Self.functionKeys.firstIndex(of: Int(keyCode)) { return "F\(n + 1)" }
            return character.isEmpty ? "#\(keyCode)" : character
        }
    }

    static let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                               kVK_F11, kVK_F12]

    // MARK: Pressing it

    enum Press: Equatable {
        /// Open the card for free play and take the keyboard, as a click on Tomo does (a peek opens into its visit).
        case open
        /// The card is open but Tomo came by itself, without the keyboard: take it, so the learner can answer and Esc
        /// closes it.
        case takeKeyboard
        /// The card is open with the keyboard: close it, as Esc does.
        case close
    }

    /// What a press does: resting, hidden, peeking or folding, it opens (a fold in progress stays open); open, it takes
    /// the keyboard if the island doesn't have it, and closes it if it does.
    static func press(mode: IslandMode, leaving: Bool, hasKeyboard: Bool) -> Press {
        if leaving || mode != .expanded { return .open }
        return hasKeyboard ? .close : .takeKeyboard
    }
}

// MARK: - Registering it (Carbon)

/// The registered hot key. It registers the learner's shortcut at launch and again when it changes, never in a headless
/// run; `onPress` is the island's (AppDelegate). Settings pauses it while recording, so the old shortcut can be typed.
@MainActor
final class TomoHotKey: ObservableObject {
    static let shared = TomoHotKey()

    enum Status: Equatable { case none, on, taken }
    /// `taken`: another app already has this combination (RegisterEventHotKey refused it).
    @Published private(set) var status = Status.none
    var onPress: () -> Void = {}

    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var paused = false
    private static let signature: OSType = 0x546F_6D6F   // "Tomo"

    private init() {}

    /// Starts following the saved shortcut. Not in a headless run (a test run must never take the owner's keys).
    func start() {
        // TOMO_SHORTCUT_PRESS=<seconds,…> (snapshots): presses the shortcut then, as the learner would, since a test run
        // can neither press keys nor register a hot key.
        for t in (ProcessInfo.processInfo.environment["TOMO_SHORTCUT_PRESS"] ?? "").split(separator: ",")
            .compactMap({ Double($0) }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in self?.onPress() }
        }
        guard !TomoHeadless.isOn else { return }   // a test run never registers one
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { TomoHotKey.shared.pressed() } }
            return noErr
        }, 1, &spec, nil, &handler)
        NotificationCenter.default.addObserver(forName: TomoShortcut.changed, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { TomoHotKey.shared.apply() }
        }
        apply()
    }

    /// Settings is recording a new shortcut: the old one types into the recorder instead of opening Tomo.
    func pause(_ on: Bool) {
        guard paused != on else { return }
        paused = on
        apply()
    }

    private func pressed() { if ref != nil { onPress() } }

    /// Whether a shortcut is registered: never in a headless run (a test run must not take the owner's keys), nor while
    /// Settings records a new one, nor one that can't be Tomo's.
    nonisolated static func registers(_ s: TomoShortcut?, headless: Bool, paused: Bool) -> Bool {
        guard let s, !headless, !paused else { return false }
        return s.rejection == nil
    }

    private func apply() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        guard let s = TomoShortcut.current else { status = .none; return }
        guard Self.registers(s, headless: TomoHeadless.isOn, paused: paused) else { return }
        var newRef: EventHotKeyRef?
        let err = RegisterEventHotKey(s.keyCode, s.carbonModifiers, EventHotKeyID(signature: Self.signature, id: 1),
                                      GetApplicationEventTarget(), 0, &newRef)
        ref = err == noErr ? newRef : nil
        status = err == noErr ? .on : .taken
    }
}

// MARK: - Settings' row

/// The recorder, in the Mac's `device` slot: the shortcut (or none), a button to record a new one, which takes the next
/// key combination typed (Esc keeps the old one, Delete removes it), and a button to remove it. A combination that
/// can't be Tomo's says why; one another app holds says so.
struct TomoShortcutSection: View {
    @ObservedObject var lang = TomoLanguages.shared
    @ObservedObject var hotKey = TomoHotKey.shared
    @State private var shortcut = TomoShortcut.current
    @State private var recording = false
    @State private var rejected: TomoShortcut.Rejection?
    @State private var monitor: Any?

    var body: some View {
        Section {
            LabeledContent(lang.learner("settings.shortcut")) {
                HStack(spacing: 8) {
                    Button(recording ? lang.learner("settings.shortcut.recording")
                           : shortcut?.label(lang) ?? lang.learner("settings.shortcut.record")) {
                        recording ? stop() : start()
                    }
                    if shortcut != nil && !recording {
                        Button { save(nil) } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless)
                            .help(lang.learner("settings.shortcut.clear"))
                    }
                }
            }
        } footer: {
            Text(footer).font(.caption).foregroundStyle(rejected == nil && hotKey.status != .taken ? .secondary : .primary)
        }
        .onDisappear { stop() }
    }

    private var footer: String {
        switch rejected {
        case .needsModifier?: return lang.learner("settings.shortcut.needsModifier")
        case .system?: return lang.learner("settings.shortcut.system")
        case .common?: return lang.learner("settings.shortcut.common")
        case nil: return hotKey.status == .taken && shortcut != nil ? lang.learner("settings.shortcut.taken")
            : lang.learner("settings.shortcutNote")
        }
    }

    private func start() {
        recording = true
        rejected = nil
        TomoHotKey.shared.pause(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let result = TomoShortcut.record(keyCode: UInt32(event.keyCode),
                                             modifiers: TomoShortcut.carbon(event.modifierFlags),
                                             character: event.characters(byApplyingModifiers: []) ?? "")
            MainActor.assumeIsolated {
                switch result {
                case .set(let s): save(s); stop()
                case .clear: save(nil); stop()
                case .cancel: stop()
                case .rejected(let why): rejected = why
                }
            }
            return nil   // the recorder takes every key while it listens
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        TomoHotKey.shared.pause(false)
    }

    private func save(_ s: TomoShortcut?) {
        shortcut = s
        rejected = nil
        TomoShortcut.set(s)
    }
}
