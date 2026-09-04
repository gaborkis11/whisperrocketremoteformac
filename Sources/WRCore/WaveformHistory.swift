import Foundation

/// The last handful of microphone levels, so a meter can draw a *scrolling*
/// waveform instead of one live value.
///
/// It lives here, in the logic module, rather than in the level monitor:
/// `AudioLevelMonitor` publishes the instantaneous level on purpose — that is
/// the honest measurement — and how much of the past a particular view chooses
/// to keep is a presentation decision. A ring makes the choice explicit,
/// bounded and testable.
///
/// A fixed-size ring rather than an array that grows and is trimmed: the whole
/// point is that a five-minute recording costs exactly the same memory and the
/// same per-sample work as a five-second one.
public struct WaveformHistory: Equatable, Sendable {
    /// Enough bars to fill the capsule's waveform lane at 3 pt + 3 pt.
    public static let defaultCapacity = 32

    public let capacity: Int

    /// The ring. `cursor` is the slot the *next* push overwrites, which is also
    /// the oldest sample.
    private var storage: [Double]
    private var cursor: Int

    public init(capacity: Int = WaveformHistory.defaultCapacity, filledWith value: Double = 0) {
        let capacity = max(1, capacity)
        self.capacity = capacity
        storage = Array(repeating: Self.clamped(value), count: capacity)
        cursor = 0
    }

    /// Values outside `0…1` (and non-finite ones) are clamped on the way in.
    /// Bar heights are a direct multiple of this number, and one stray sample
    /// would draw a bar straight out of the capsule.
    public mutating func push(_ value: Double) {
        storage[cursor] = Self.clamped(value)
        cursor = (cursor + 1) % capacity
    }

    public mutating func reset(to value: Double = 0) {
        let value = Self.clamped(value)
        for index in storage.indices {
            storage[index] = value
        }
        cursor = 0
    }

    /// Oldest first, newest last — the order a left-to-right waveform draws in.
    public var samples: [Double] {
        Array(storage[cursor...]) + Array(storage[..<cursor])
    }

    /// `0` is the newest sample, `capacity - 1` the oldest. Out-of-range ages
    /// are clamped rather than trapping: a view that asks for one more bar than
    /// the ring holds should get the oldest value, not a crash.
    public func sample(agedBy age: Int) -> Double {
        let age = min(max(age, 0), capacity - 1)
        let index = ((cursor - 1 - age) % capacity + capacity) % capacity
        return storage[index]
    }

    public var newest: Double { sample(agedBy: 0) }

    private static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }
}
