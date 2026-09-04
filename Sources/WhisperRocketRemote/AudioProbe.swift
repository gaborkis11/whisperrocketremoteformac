import AVFoundation

/// F0 probe only. Reached exclusively through the `--mic-probe` flag, because
/// `AVAudioEngine.inputNode` is enough to raise the microphone TCC prompt.
enum AudioProbe {
    static func run() {
        print("[mic-probe] TCC status for .audio: \(describe(AVCaptureDevice.authorizationStatus(for: .audio)))")

        let engine = AVAudioEngine()
        print("[mic-probe] AVAudioEngine created")

        let format = engine.inputNode.inputFormat(forBus: 0)
        print("[mic-probe] inputNode format: \(format)")
        print("[mic-probe]   sampleRate=\(format.sampleRate) channels=\(format.channelCount) interleaved=\(format.isInterleaved)")

        do {
            try engine.start()
            print("[mic-probe] engine.start() OK, isRunning=\(engine.isRunning)")
            Thread.sleep(forTimeInterval: 1)
            engine.stop()
            print("[mic-probe] engine stopped")
        } catch {
            print("[mic-probe] engine.start() FAILED: \(error)")
        }

        print("[mic-probe] TCC status after probe: \(describe(AVCaptureDevice.authorizationStatus(for: .audio)))")
    }

    private static func describe(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "notDetermined"
        case .restricted: "restricted"
        case .denied: "denied"
        case .authorized: "authorized"
        @unknown default: "unknown(\(status.rawValue))"
        }
    }
}
