import SwiftUI

/// The panel while the microphone is open.
///
/// Three things at once, in priority order: proof that sound is arriving (the
/// meter), how long it has been going (the clock), and any warning that changes
/// what the user should do (stored mode, the auto-stop countdown).
struct RecordingStageView: View {
    var level: Double
    var peak: Double
    var elapsed: TimeInterval
    var countdown: Int?
    /// `nil` while the health probe has not answered yet — which is not the
    /// same as "unreachable", and must not raise the banner.
    var hostReachable: Bool?
    var reduceMotion: Bool
    var onStop: () -> Void

    var body: some View {
        VStack(spacing: PanelMetrics.sectionSpacing) {
            if hostReachable == false {
                StoredModeBanner()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            LevelBarsView(level: level, peak: peak, reduceMotion: reduceMotion)
                .foregroundStyle(.tint)
                // Squashing down to nothing is how the meter gets out of the
                // rocket's way when the phase changes.
                .transition(.scale(scale: 0.12, anchor: .bottom).combined(with: .opacity))

            HStack(spacing: 8) {
                Text(Duration.seconds(elapsed), format: .time(pattern: .minuteSecond))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                if let countdown {
                    CountdownBadge(secondsRemaining: countdown)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }

            Button(L.stopRecording, action: onStop)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(L.recordingHint)
        }
        .frame(maxWidth: .infinity)
        .animation(PanelMetrics.phaseAnimation(reduceMotion: reduceMotion), value: hostReachable)
        .animation(PanelMetrics.phaseAnimation(reduceMotion: reduceMotion), value: countdown != nil)
    }
}
