import Testing
@testable import WRCore

@Suite struct WaveformHistoryTests {
    @Test func aFreshRingIsFullOfItsFillValue() {
        let history = WaveformHistory(capacity: 4, filledWith: 0.25)
        #expect(history.samples == [0.25, 0.25, 0.25, 0.25])
        #expect(history.newest == 0.25)
    }

    @Test func theNewestSampleIsLast() {
        var history = WaveformHistory(capacity: 4)
        history.push(0.1)
        history.push(0.2)
        #expect(history.samples == [0, 0, 0.1, 0.2])
        #expect(history.newest == 0.2)
        #expect(history.sample(agedBy: 1) == 0.1)
    }

    @Test func theRingWrapsWithoutGrowing() {
        var history = WaveformHistory(capacity: 3)
        for value in [0.1, 0.2, 0.3, 0.4, 0.5] {
            history.push(value)
        }
        #expect(history.samples.count == 3)
        #expect(history.samples == [0.3, 0.4, 0.5])
    }

    /// A bar height is a direct multiple of the sample, so one stray value out
    /// of range would draw straight out of the capsule.
    @Test func valuesAreClampedOnTheWayIn() {
        var history = WaveformHistory(capacity: 3)
        history.push(1.8)
        history.push(-0.5)
        history.push(.nan)
        #expect(history.samples == [1, 0, 0])
    }

    @Test func askingBeyondTheRingGivesTheOldestSample() {
        var history = WaveformHistory(capacity: 3)
        history.push(0.1)
        history.push(0.2)
        history.push(0.3)
        #expect(history.sample(agedBy: 2) == 0.1)
        #expect(history.sample(agedBy: 99) == 0.1)
        #expect(history.sample(agedBy: -5) == 0.3)
    }

    @Test func resetFlattensTheWholeRing() {
        var history = WaveformHistory(capacity: 4)
        history.push(0.9)
        history.push(0.8)
        history.reset()
        #expect(history.samples == [0, 0, 0, 0])
    }

    @Test func capacityIsNeverZero() {
        var history = WaveformHistory(capacity: 0)
        #expect(history.capacity == 1)
        history.push(0.5)
        #expect(history.samples == [0.5])
    }
}
