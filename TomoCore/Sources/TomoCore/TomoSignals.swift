import SwiftUI

// MARK: - How the game talks to whatever draws Tomo
//
// TomoGame sets Tomo's state (`BotState`) through `TomoGame.onBotState` and posts these notifications;
// TomoBlob (TomoCharacter.swift) and TomoSounds react to them. Each shell (the Mac island, the iPhone
// app) only has to draw a TomoBlob and pass the state on. The names come from Coucou and go with
// issue #1.

public enum BotState: String, CaseIterable, Sendable {
    case idle, working, thinking, searching
    case approval, question, error, finished
    case ratelimit, sleeping, dizzy
}

public enum BotEmote: String, CaseIterable, Sendable {
    case love, surprised, proud, wink, yawn, happy, annoyed
}

public extension Notification.Name {
    static let botTalk = Notification.Name("tomo.botTalk")
    static let botGrow = Notification.Name("tomo.botGrow")
    static let botNudge = Notification.Name("tomo.botNudge")
    static let botLevelUp = Notification.Name("tomo.botLevelUp")
    /// Set Tomo's age step without the growing-up animation (launch, switching language pairs).
    static let botSetGrowth = Notification.Name("tomo.botSetGrowth")
    static let triggerEmote = Notification.Name("tomo.triggerEmote")
    static let triggerSlap = Notification.Name("tomo.triggerSlap")
    static let botDizzy = Notification.Name("tomo.botDizzy")
    static let botGreet = Notification.Name("tomo.botGreet")
    static let botBlink = Notification.Name("tomo.botBlink")
    static let botSetTgEs = Notification.Name("tomo.botSetTgEs")
    static let botGulp = Notification.Name("tomo.botGulp")
}

/// Tomo shows its love (`BotEmote.love`) when the learner rests on it: the pointer resting on it on the Mac, a long
/// press on the iPhone. At most once every 6 s, so it stays a treat. Each shell keeps one and posts the emote when
/// `show` says so. Times are seconds on one clock (`CACurrentMediaTime()` in the shells).
public struct TomoLoveCooldown: Sendable {
    public static let seconds: Double = 6
    private var last = -Double.infinity

    public init() {}

    /// Love may show now.
    public func ready(at now: Double) -> Bool { now - last > Self.seconds }

    /// Love shows now if it may: true, and the cooldown starts again from now.
    public mutating func show(at now: Double) -> Bool {
        guard ready(at: now) else { return false }
        last = now
        return true
    }
}

extension Color {
    public init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let val = UInt64(h, radix: 16) ?? 0
        self.init(red: Double((val >> 16) & 0xFF) / 255, green: Double((val >> 8) & 0xFF) / 255,
                  blue: Double(val & 0xFF) / 255)
    }
}
