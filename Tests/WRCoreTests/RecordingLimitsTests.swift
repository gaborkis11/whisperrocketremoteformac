import Testing
@testable import WRCore

@Suite struct RecordingLimitsTests {
    private let limits = RecordingLimits.default

    @Test func theShippedCeilingIsFiveMinutesWithAThirtySecondCountdown() {
        #expect(limits.maxDuration == 300)
        #expect(limits.countdownThreshold == 30)
    }

    @Test(arguments: [
        (16_000.0, Int64(4_800_000)),
        (44_100.0, Int64(13_230_000)),
        (48_000.0, Int64(14_400_000)),
    ])
    func theFrameBudgetFollowsTheSampleRate(sampleRate: Double, expected: Int64) {
        #expect(limits.maxFrames(sampleRate: sampleRate) == expected)
        // 30 s earlier, in frames.
        #expect(limits.countdownStartFrame(sampleRate: sampleRate) == expected - Int64(30 * sampleRate))
    }

    @Test func theStopFiresOnTheExactFrameAndNotBefore() {
        let budget = limits.maxFrames(sampleRate: 16_000)
        #expect(!limits.hasReachedLimit(frameCount: budget - 1, sampleRate: 16_000))
        #expect(limits.hasReachedLimit(frameCount: budget, sampleRate: 16_000))
        #expect(limits.hasReachedLimit(frameCount: budget + 1, sampleRate: 16_000))
        #expect(!limits.hasReachedLimit(frameCount: 0, sampleRate: 16_000))
    }

    @Test func elapsedAndRemainingAreFrameDerived() {
        #expect(limits.elapsed(frameCount: 16_000, sampleRate: 16_000) == 1)
        #expect(limits.remaining(frameCount: 16_000, sampleRate: 16_000) == 299)
        #expect(limits.elapsed(frameCount: 0, sampleRate: 16_000) == 0)
        // Never negative, even if the tap overshoots the budget.
        #expect(limits.remaining(frameCount: 16_000 * 400, sampleRate: 16_000) == 0)
    }

    @Test func theCountdownStaysHiddenUntilThirtySecondsAreLeft() {
        let rate = 16_000.0
        #expect(limits.countdown(frameCount: 0, sampleRate: rate) == nil)
        // 30.001 s left.
        #expect(limits.countdown(frameCount: Int64(269.999 * rate), sampleRate: rate) == nil)
    }

    @Test func theCountdownRunsThirtyDownToZero() {
        let rate = 16_000.0
        #expect(limits.countdown(frameCount: limits.countdownStartFrame(sampleRate: rate), sampleRate: rate) == 30)
        // Rounds up, so each number is shown for a full second and none is skipped.
        #expect(limits.countdown(frameCount: Int64(270.5 * rate), sampleRate: rate) == 30)
        #expect(limits.countdown(frameCount: Int64(271.0 * rate), sampleRate: rate) == 29)
        #expect(limits.countdown(frameCount: Int64(299.5 * rate), sampleRate: rate) == 1)
        #expect(limits.countdown(frameCount: limits.maxFrames(sampleRate: rate), sampleRate: rate) == 0)
    }

    @Test func anInvalidSampleRateNeverTriggersTheAutoStop() {
        for rate in [0.0, -44_100.0] {
            #expect(limits.maxFrames(sampleRate: rate) == 0)
            #expect(!limits.hasReachedLimit(frameCount: 999_999_999, sampleRate: rate))
            #expect(limits.countdown(frameCount: 999_999_999, sampleRate: rate) == nil)
            #expect(limits.elapsed(frameCount: 999_999_999, sampleRate: rate) == 0)
        }
    }

    @Test func theLimitsAreConfigurable() {
        let short = RecordingLimits(maxDuration: 10, countdownThreshold: 3)
        #expect(short.maxFrames(sampleRate: 100) == 1000)
        #expect(short.countdownStartFrame(sampleRate: 100) == 700)
        #expect(short.countdown(frameCount: 600, sampleRate: 100) == nil)
        #expect(short.countdown(frameCount: 700, sampleRate: 100) == 3)
        #expect(short.hasReachedLimit(frameCount: 1000, sampleRate: 100))
    }
}
