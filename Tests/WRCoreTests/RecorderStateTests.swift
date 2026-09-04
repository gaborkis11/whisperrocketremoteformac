import Testing
@testable import WRCore

@Suite struct RecorderStateTests {
    // MARK: - Allowed edges

    @Test func startFromIdleBeginsRecordingWithAnUnknownHost() {
        #expect(RecorderState.idle.applying(.start) == .success(.recording(hostReachable: nil)))
    }

    @Test func stopFromRecordingReturnsToIdle() {
        #expect(RecorderState.recording(hostReachable: nil).applying(.stop) == .success(.idle))
        #expect(RecorderState.recording(hostReachable: true).applying(.stop) == .success(.idle))
        #expect(RecorderState.recording(hostReachable: false).applying(.stop) == .success(.idle))
    }

    @Test(arguments: [true, false])
    func healthResultOnlyFillsInTheHostField(reachable: Bool) {
        let result = RecorderState.recording(hostReachable: nil).applying(.healthResult(reachable: reachable))
        #expect(result == .success(.recording(hostReachable: reachable)))
    }

    @Test func aLaterHealthResultOverwritesTheEarlierOne() {
        var state = RecorderState.recording(hostReachable: true)
        state.apply(.healthResult(reachable: false))
        #expect(state == .recording(hostReachable: false))
        // Still recording — a health answer never interrupts the capture.
        #expect(state.isRecording)
    }

    // MARK: - Forbidden edges

    @Test func startWhileRecordingIsRejected() {
        #expect(RecorderState.recording(hostReachable: nil).applying(.start) == .failure(.alreadyRecording))
        #expect(RecorderState.recording(hostReachable: true).applying(.start) == .failure(.alreadyRecording))
    }

    @Test func stopWhileIdleIsRejected() {
        #expect(RecorderState.idle.applying(.stop) == .failure(.notRecording))
    }

    @Test func aHealthResultThatOutlivesTheRecordingIsRejected() {
        #expect(RecorderState.idle.applying(.healthResult(reachable: true)) == .failure(.healthResultWhileIdle))
        #expect(RecorderState.idle.applying(.healthResult(reachable: false)) == .failure(.healthResultWhileIdle))
    }

    @Test func aRejectedEventLeavesTheStateUntouched() {
        var state = RecorderState.recording(hostReachable: true)
        #expect(state.apply(.start) == .alreadyRecording)
        #expect(state == .recording(hostReachable: true))

        var idle = RecorderState.idle
        #expect(idle.apply(.stop) == .notRecording)
        #expect(idle.apply(.healthResult(reachable: true)) == .healthResultWhileIdle)
        #expect(idle == .idle)
    }

    // MARK: - Accessors and the whole cycle

    @Test func accessorsDescribeTheState() {
        #expect(!RecorderState.idle.isRecording)
        #expect(RecorderState.idle.hostReachable == nil)
        #expect(RecorderState.recording(hostReachable: nil).isRecording)
        #expect(RecorderState.recording(hostReachable: nil).hostReachable == nil)
        #expect(RecorderState.recording(hostReachable: false).hostReachable == false)
    }

    @Test func aFullDictationCycleRunsWithoutRejection() {
        var state = RecorderState.idle
        #expect(state.apply(.start) == nil)
        #expect(state == .recording(hostReachable: nil))
        // The probe answers while the user is still talking.
        #expect(state.apply(.healthResult(reachable: true)) == nil)
        #expect(state == .recording(hostReachable: true))
        #expect(state.apply(.stop) == nil)
        #expect(state == .idle)
        // The next recording starts over with an unknown host.
        #expect(state.apply(.start) == nil)
        #expect(state.hostReachable == nil)
    }
}
