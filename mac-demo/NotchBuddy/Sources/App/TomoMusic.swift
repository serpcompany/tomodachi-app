import AppKit
import Combine
import TomoCore

// MARK: - Music playing, from the players' own announcements (#130: Tomo dances to music)
//
// Music and Spotify post a distributed notification whenever they play, pause, skip or stop
// (`com.apple.Music.playerInfo`, `com.spotify.client.PlaybackStateChanged`), with the player's state in its userInfo
// ("Player State": "Playing", "Paused", "Stopped"). Tomo only reads that state: no AppleScript, no Automation prompt, no
// permission, and nothing about the song. A sandboxed build gets them too (checked for the Mac App Store build, #108,
// with a throwaway sandboxed app: named distributed notifications arrive with their userInfo). AppKit holds an inactive
// app's distributed notifications (`DistributedNotificationCenter.suspended`), and Tomodachi is rarely the active app,
// so every observer here asks for them at once (`.deliverImmediately`).
// Known gap (#130, accepted): music already playing when Tomodachi starts shows at the player's next notification.

/// Distributed notifications, delivered at once even while Tomodachi isn't the active app (`.deliverImmediately`),
/// as a publisher. Combine's own `publisher(for:)` uses the default (`.coalesce`), which AppKit holds while the app is
/// inactive.
@MainActor
final class TomoDistributed: NSObject {
    private let subject = PassthroughSubject<Notification, Never>()

    init(_ names: [String]) {
        super.init()
        for name in names {
            DistributedNotificationCenter.default().addObserver(self, selector: #selector(heard(_:)), name: Notification.Name(name),
                                                                object: nil, suspensionBehavior: .deliverImmediately)
        }
    }

    var publisher: AnyPublisher<Notification, Never> { subject.eraseToAnyPublisher() }

    @objc private func heard(_ n: Notification) { subject.send(n) }
}

/// Whether music is playing in Music or Spotify, from their notifications; the pure part is `TomoMusicState`.
@MainActor
final class TomoMusic: ObservableObject {
    static let shared = TomoMusic()

    @Published private(set) var playing = TomoMusic.testPlaying
    private var state = TomoMusicState()
    private var listener: TomoDistributed?
    private var quits: AnyCancellable?
    private var heard: AnyCancellable?

    /// TOMO_MUSIC=playing: music plays, as if a player said so (a test run can't play any).
    nonisolated static let testPlaying = ProcessInfo.processInfo.environment["TOMO_MUSIC"] == "playing"
    /// TOMO_MUSIC_PROBE=1: log every player notification that arrives (its state and which keys it carries, never a
    /// song's name), to check the players' notifications by hand (debug-flags.md).
    nonisolated static let probe = ProcessInfo.processInfo.environment["TOMO_MUSIC_PROBE"] == "1"

    private init() {}

    /// Starts listening (once). Called by the island's Tomo when it first appears.
    func start() {
        guard listener == nil else { return }
        let listener = TomoDistributed(TomoMusicState.players.map(\.notification))
        self.listener = listener
        heard = listener.publisher.sink { [weak self] n in self?.heard(n) }
        // A player that quits stops playing, whether or not it said so.
        quits = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .sink { [weak self] n in
                guard let id = (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                else { return }
                self?.update { $0.quit(bundle: id) }
            }
        if Self.probe {
            NSLog("Tomo music: listening for %@ (sandboxed: %@, active: %@)",
                  TomoMusicState.players.map(\.notification).joined(separator: ", "),
                  ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil ? "no" : "yes",
                  NSApp.isActive ? "yes" : "no")
        }
    }

    private func heard(_ n: Notification) {
        let info = n.userInfo ?? [:]
        update { $0.heard(name: n.name.rawValue, playerState: info["Player State"] as? String) }
        if Self.probe {
            NSLog("Tomo music: %@ Player State=%@ keys=[%@] active=%@ → playing=%@", n.name.rawValue,
                  (info["Player State"] as? String) ?? "none",
                  info.keys.map { "\($0)" }.sorted().joined(separator: ", "),
                  NSApp.isActive ? "yes" : "no", playing ? "yes" : "no")
        }
    }

    private func update(_ change: (inout TomoMusicState) -> Void) {
        change(&state)
        playing = Self.testPlaying || state.playing
    }
}

/// Which players are playing, from their notifications: pure, so `TomoIslandSelfTest` checks it.
struct TomoMusicState: Equatable {
    /// The players Tomo listens to: their notification and bundle ID.
    static let players: [(notification: String, bundle: String)] = [
        ("com.apple.Music.playerInfo", "com.apple.Music"),
        ("com.spotify.client.PlaybackStateChanged", "com.spotify.client"),
    ]

    private var playingBundles: Set<String> = []

    var playing: Bool { !playingBundles.isEmpty }

    /// A player's notification: playing only when its state says "Playing" ("Paused", "Stopped" or none: not).
    mutating func heard(name: String, playerState: String?) {
        guard let bundle = Self.players.first(where: { $0.notification == name })?.bundle else { return }
        if playerState == "Playing" { playingBundles.insert(bundle) } else { playingBundles.remove(bundle) }
    }

    /// A player quit.
    mutating func quit(bundle: String) { playingBundles.remove(bundle) }
}
