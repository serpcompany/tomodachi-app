import SwiftUI

// MARK: - How the game talks to whatever draws Tomo
//
// TomoGame sets Tomo's state (`BotState`) through `TomoGame.onBotState` and posts these notifications;
// TomoChick (TomoCharacter.swift) and TomoSounds react to them. Each shell (the Mac island, the iPhone
// app) only has to draw a TomoChick and pass the state on. The names come from Coucou and go with
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

extension Color {
    public init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let val = UInt64(h, radix: 16) ?? 0
        self.init(red: Double((val >> 16) & 0xFF) / 255, green: Double((val >> 8) & 0xFF) / 255,
                  blue: Double(val & 0xFF) / 255)
    }
}
