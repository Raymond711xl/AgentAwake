import AppKit
import Foundation

@MainActor
final class CompletionSoundPlayer {
    static let shared = CompletionSoundPlayer()
    static let preferenceKey = "completionSoundEnabled"

    private let defaults: UserDefaults
    private let bundle: Bundle
    private var completionSound: NSSound?

    init(
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main
    ) {
        self.defaults = defaults
        self.bundle = bundle
    }

    func playCompletionIfEnabled() {
        guard isEnabled else {
            return
        }

        play()
    }

    func playPreview() {
        play()
    }

    private var isEnabled: Bool {
        guard defaults.object(
            forKey: Self.preferenceKey
        ) != nil else {
            return true
        }

        return defaults.bool(forKey: Self.preferenceKey)
    }

    private func play() {
        guard let sound = resolveSound() else {
            return
        }

        sound.stop()
        sound.currentTime = 0
        sound.play()
    }

    private func resolveSound() -> NSSound? {
        if let completionSound {
            return completionSound
        }

        guard let url = bundle.url(
            forResource: "CompletionSound",
            withExtension: "wav"
        ), let sound = NSSound(
            contentsOf: url,
            byReference: false
        ) else {
            return nil
        }

        sound.volume = 0.75
        completionSound = sound
        return sound
    }
}
