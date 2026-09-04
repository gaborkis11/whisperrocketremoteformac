import SwiftUI
import WRCore

/// The dictation HUD: a 560×88 pill under the menu-bar icon, showing the one
/// thing that is happening right now.
///
/// It replaces the big panel as the *live* display. The panel still exists — it
/// is where the recording list and the way into Settings live — but it only
/// opens when the icon is clicked, because a 300-point column of chrome is not
/// what someone wants in front of them while they are talking.
///
/// Generic over the model rather than taking `any PanelModelProviding`, for the
/// same reason ``PanelView`` is: the compiler can see the concrete `@Observable`
/// type, so SwiftUI's observation tracking stays exact through the existential
/// ``MenuBarUI`` has to store.
///
/// The waveform's ring lives **here**, at the root, and not in the lane view:
/// the ghost waveform under a finished or failed dictation is the same history,
/// and putting the ring in a view that the stage change replaces would throw the
/// recording away at the exact moment it becomes the picture.
struct CapsuleView<Model: PanelModelProviding>: View {
    var model: Model
    var flash: CapsuleCancelFlash
    /// Set only by `--capsule-probe`, to photograph one stage. `nil` in the app.
    var frozenStage: CapsuleStage?
    /// Set only by `--capsule-probe`: a still cannot wait twenty seconds for a
    /// waveform to fill itself in.
    var frozenHistory: WaveformHistory?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var history = WaveformHistory()

    private var stage: CapsuleStage? {
        if let frozenStage { return frozenStage }
        return CapsuleStage(phase: model.phase, showingCancelled: flash.isShowing)
    }

    private var waveform: WaveformHistory { frozenHistory ?? history }

    var body: some View {
        content
            .frame(width: CapsuleMetrics.width, height: CapsuleMetrics.height)
            .background(CapsuleMetrics.background, in: .capsule)
            .overlay {
                Capsule().strokeBorder(borderColor, lineWidth: 1)
            }
            .overlay {
                // The lip along the top edge. A gradient rather than a real
                // inner shadow: one stroke, no blur, and it stops halfway down
                // exactly as the design's `inset 0 1` does.
                Capsule().strokeBorder(
                    LinearGradient(
                        colors: [CapsuleMetrics.topHighlight, .clear],
                        startPoint: .top,
                        endPoint: .center
                    ),
                    lineWidth: 1
                )
            }
            .opacity(stage == .cancelled ? 0.82 : 1)
            // Always dark: this hangs over whatever the user is looking at, and
            // a light-mode capsule would be a white slab in a dark editor.
            .environment(\.colorScheme, .dark)
            .animation(CapsuleMetrics.stageChange, value: stage)
            .task(id: stage?.isLive == true) {
                await sampleWaveform()
            }
    }

    @ViewBuilder
    private var content: some View {
        if let stage {
            HStack(spacing: CapsuleMetrics.itemSpacing) {
                CapsuleRocketBadge()

                CapsuleTextColumn(
                    title: title(for: stage),
                    isPrimary: stage == .recording,
                    subline: subline(for: stage)
                )

                lane(for: stage)

                CapsuleActionButton(
                    stage: stage,
                    reduceMotion: reduceMotion,
                    canRetry: model.failedRecordingID != nil,
                    onStop: model.toggleRecording,
                    onRetry: { if let id = model.failedRecordingID { model.resend(id) } }
                )
            }
            .padding(.leading, CapsuleMetrics.leadingPadding)
            .padding(.trailing, CapsuleMetrics.trailingPadding)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L.capsuleAccessibility)
            .accessibilityHint(stage == .recording ? L.capsuleCancelHint : "")
        } else {
            // Idle with nothing to announce. The window is ordered out in this
            // state; drawing an empty pill would be a flash of chrome on the way
            // there.
            Color.clear
        }
    }

    // MARK: - The lane

    @ViewBuilder
    private func lane(for stage: CapsuleStage) -> some View {
        switch stage {
        case .recording:
            CapsuleWaveformView(history: waveform, mode: .live)
        case .sending:
            RocketCruiseView(
                reduceMotion: reduceMotion,
                height: CapsuleMetrics.laneHeight
            )
        case .done, .cancelled:
            CapsuleWaveformView(history: waveform, mode: .ghost)
        case .failed:
            CapsuleWaveformView(history: waveform, mode: .ghostFailed)
        }
    }

    // MARK: - The words

    private func title(for stage: CapsuleStage) -> String {
        switch stage {
        case .recording: L.capsuleListening
        case .sending: L.sendingTitle
        case .done: model.summary?.delivery.localizedHeadline ?? L.statusDone
        case .failed: model.problem?.title ?? L.errorTitleGeneric
        case .cancelled: L.capsuleCancelledTitle
        }
    }

    private func subline(for stage: CapsuleStage) -> CapsuleTextColumn.Subline {
        switch stage {
        case .recording:
            // Priority, most urgent first: the auto-stop is about to take the
            // decision away, stored mode changes what happens next, and the
            // clock is what is true the rest of the time.
            if let countdown = model.countdown {
                return .countdown(countdown)
            }
            if model.hostReachable == false {
                return .warning(L.storedModeTitle)
            }
            // Whole seconds, deliberately. `elapsed` moves thirty times a
            // second and the counter shows m:ss, so letting the raw value
            // through re-ran the formatter and re-laid out the text thirty
            // times for every number a person actually sees. Measured on this
            // Mac, release build: 20 % of a core with the raw value, 1 % with
            // it standing still between ticks.
            return .counter(model.elapsed.rounded(.down))

        case .sending:
            if model.attempt > 1 {
                return .note(L.sendingAttempt(model.attempt, of: model.maxAttempts))
            }
            return .joke(reduceMotion: reduceMotion)

        case .done:
            guard let summary = model.summary else { return .note("") }
            switch summary.delivery {
            case .typed:
                return .note(L.doneCharacters(summary.characterCount))
            case .clipboardOnly:
                return .note(L.capsulePasteHint)
            }

        case .failed:
            return .note(L.capsuleFailedSubtitle)

        case .cancelled:
            return .note(L.capsuleCancelledSubtitle)
        }
    }

    private var borderColor: Color {
        stage == .failed ? CapsuleMetrics.failedBorder : CapsuleMetrics.border
    }

    // MARK: - Sampling

    /// A fixed 20 Hz sampler rather than `onChange(of: model.level)`: how often
    /// the microphone hands over a buffer is the hardware's choice, and a
    /// waveform whose bar spacing depends on the audio interface looks broken.
    ///
    /// Not a `TimelineView` either, tempting as it is — writing to `@State`
    /// from inside a view's body is exactly what SwiftUI forbids, and a ring
    /// buffer is state.
    private func sampleWaveform() async {
        guard frozenHistory == nil, stage?.isLive == true else { return }
        history.reset()
        while !Task.isCancelled {
            try? await Task.sleep(for: CapsuleMetrics.waveformSampleInterval)
            guard !Task.isCancelled else { return }
            history.push(model.level)
        }
    }
}
