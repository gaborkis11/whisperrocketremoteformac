import AppKit
import Foundation

/// The two short clicks that bracket a recording.
///
/// The stop click matters more than the start one: the 5-minute auto-stop uses
/// the very same call, so the ceiling is never a silent data loss.
final class SoundPlayer {
    enum Cue: String, CaseIterable, Sendable {
        case start = "start_soft_click_smooth"
        case stop = "stop_soft_click_smooth"
    }

    /// Driven from `Settings.soundsEnabled`.
    var isEnabled: Bool

    private var sounds: [Cue: NSSound] = [:]

    init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
        for cue in Cue.allCases {
            sounds[cue] = Self.url(for: cue).flatMap { NSSound(contentsOf: $0, byReference: true) }
        }
    }

    /// True when both clicks were found in the bundle — surfaced so a broken
    /// resource copy shows up as a fact rather than as silence.
    var isLoaded: Bool { sounds.count == Cue.allCases.count }

    var missingCues: [Cue] { Cue.allCases.filter { sounds[$0] == nil } }

    func play(_ cue: Cue) {
        guard isEnabled, let sound = sounds[cue] else { return }
        // A stop click can land while the start click is still ringing; NSSound
        // refuses to `play()` a sound that is already playing.
        if sound.isPlaying { sound.stop() }
        sound.play()
    }

    /// `.process("Resources")` flattens the directory tree, so the WAVs sit in
    /// the resource bundle's root and *not* under `Sounds/` — the subdirectory
    /// lookup is only a fallback for a future non-flattened copy.
    static func url(for cue: Cue) -> URL? {
        Bundle.module.url(forResource: cue.rawValue, withExtension: "wav")
            ?? Bundle.module.url(forResource: cue.rawValue, withExtension: "wav", subdirectory: "Sounds")
    }
}
