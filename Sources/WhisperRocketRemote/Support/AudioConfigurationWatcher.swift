import AVFoundation
import Foundation

/// Bridges `AVAudioEngineConfigurationChange` onto the main actor.
///
/// The notification fires for benign reasons too — an output device appearing,
/// a sample-rate renegotiation — and a false alarm must never cut a good
/// recording short. So the watcher does not decide anything; it reports the two
/// facts that separate a real input loss from noise (is the engine still
/// running, and what is the input format *now*) and lets the controller judge.
///
/// The notification is posted from CoreAudio's own thread, so the two readings
/// are taken there, synchronously, and only `Sendable` values cross over.
final class AudioConfigurationWatcher {
    struct Change: Equatable, Sendable {
        let engineIsRunning: Bool
        let sampleRate: Double
        let channelCount: UInt32
    }

    private var token: (any NSObjectProtocol)?

    init(handler: @escaping @Sendable @MainActor (Change) -> Void) {
        token = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: nil
        ) { notification in
            guard let engine = notification.object as? AVAudioEngine else { return }
            let change = Change(
                engineIsRunning: engine.isRunning,
                sampleRate: engine.inputNode.outputFormat(forBus: 0).sampleRate,
                channelCount: engine.inputNode.outputFormat(forBus: 0).channelCount
            )
            Task { @MainActor in handler(change) }
        }
    }

    func invalidate() {
        guard let token else { return }
        NotificationCenter.default.removeObserver(token)
        self.token = nil
    }
}
