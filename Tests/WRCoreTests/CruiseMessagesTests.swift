import Testing
@testable import WRCore

/// The rules the jokes have to keep, enforced rather than remembered.
///
/// The upstream Linux app has the same three tests in
/// `tests/test_popup_phase.py`; this is that suite, ported with the pool.
@Suite struct CruiseMessagesTests {
    @Test func bothPoolsSurvivedTheMergeIntact() {
        #expect(CruiseMessages.transcription.count == 18)
        #expect(CruiseMessages.cleanup.count == 15)
        #expect(CruiseMessages.all.count == 33)
    }

    /// The panel is 300 pt wide and the joke is centred: a longer line runs
    /// into the rounded corners instead of being read.
    @Test(arguments: CruiseMessages.all)
    func everyMessageFitsTheWidth(message: String) {
        #expect(
            message.count <= CruiseMessages.maxCharacters,
            "“\(message)” is \(message.count) characters, over \(CruiseMessages.maxCharacters)"
        )
    }

    @Test func noMessageIsBlankOrDuplicated() {
        #expect(CruiseMessages.all.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        #expect(Set(CruiseMessages.all).count == CruiseMessages.all.count)
    }

    /// The one behaviour a user would actually notice going wrong: the same
    /// joke twice in a row looks like the animation has frozen.
    @Test func theSameJokeNeverComesUpTwiceRunning() {
        // Seeded, so a failure is reproducible rather than a one-in-thirty-three
        // flake — and long enough to have hit a repeat many times over.
        var generator = SplitMix64(seed: 0x5EED_1234_5678_9ABC)
        var previous: String?
        for _ in 0..<5_000 {
            let message = CruiseMessages.next(after: previous, using: &generator)
            #expect(CruiseMessages.all.contains(message))
            #expect(message != previous)
            previous = message
        }
    }

    /// Over a long run every joke should get its turn — a pool where a third of
    /// the lines are unreachable would be a silent bug.
    @Test func everyJokeGetsToldEventually() {
        var generator = SplitMix64(seed: 0xC0FF_EE00_1234_5678)
        var seen: Set<String> = []
        var previous: String?
        for _ in 0..<5_000 {
            previous = CruiseMessages.next(after: previous, using: &generator)
            seen.insert(previous!)
        }
        #expect(seen.count == CruiseMessages.all.count)
    }
}

/// A tiny seeded generator, so the tests above are deterministic.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
