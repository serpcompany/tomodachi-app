import Foundation

/// Coucou's sound player, now a thin shim. Coucou's sound files are deleted; the island's open and
/// close blips come from Tomo's own synthesized sounds (TomoSounds). Other names Coucou played
/// (its coding-agent features, switched off) are silent.
@MainActor
final class SoundEngine {
    static let shared = SoundEngine()

    var enabled = true
    var volume: Float = 0.12

    func play(_ name: String) {
        guard enabled else { return }
        switch name {
        case "open": TomoSounds.shared.play(.open)
        case "close": TomoSounds.shared.play(.close)
        case "peek": TomoSounds.shared.play(.tick)
        default: break
        }
    }
}
