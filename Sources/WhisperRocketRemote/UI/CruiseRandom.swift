import Foundation

/// The randomness behind the cruise animation, as a *pure function* of what is
/// being randomised.
///
/// The Linux popup calls `random.uniform` while it draws and keeps the result in
/// mutable state until the star wraps around. That cannot be photographed: two
/// runs of the render probe would disagree, so a picture of the animation would
/// prove nothing about the animation.
///
/// Here every "random" value is instead derived by hashing its own coordinates —
/// which star, which lap, which frame — so the whole scene is a function of the
/// clock alone. Freeze the clock and you get the same frame every time, on every
/// machine; that is what makes `--anim-probe` evidence rather than decoration.
///
/// The mixer is SplitMix64's finaliser, which is cheap enough to call a few
/// dozen times per frame without anyone noticing.
nonisolated enum CruiseRandom {
    /// A value in `0..<1`, uniquely determined by the three coordinates.
    static func unit(_ a: Int, _ b: Int, _ c: Int = 0) -> Double {
        var z = UInt64(bitPattern: Int64(a)) &* 0x9E37_79B9_7F4A_7C15
        z ^= UInt64(bitPattern: Int64(b)) &* 0xBF58_476D_1CE4_E5B9
        z ^= UInt64(bitPattern: Int64(c)) &* 0x94D0_49BB_1331_11EB
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        // 53 bits is exactly what a Double's significand holds, so this is
        // uniform rather than merely uniform-looking.
        return Double(z >> 11) * 0x1p-53
    }

    /// A value in `low..<high`, uniquely determined by the three coordinates.
    static func value(
        in range: ClosedRange<Double>,
        _ a: Int,
        _ b: Int,
        _ c: Int = 0
    ) -> Double {
        range.lowerBound + unit(a, b, c) * (range.upperBound - range.lowerBound)
    }
}
