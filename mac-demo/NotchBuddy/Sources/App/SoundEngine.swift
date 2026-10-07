import Foundation
import TomoCore

/// Coucou's sound player, now a thin shim. Coucou's sound files are deleted; the island's open, close and
/// peek blips come from Tomo's own synthesized sounds (TomoSounds).
@MainActor
final class SoundEngine {
    static let shared = SoundEngine()

    func play(_ name: String) {
        switch name {
        case "open": TomoSounds.shared.play(.open)
        case "close": TomoSounds.shared.play(.close)
        case "peek": TomoSounds.shared.play(.tick)
        default: break
        }
    }
}
