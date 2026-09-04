import Foundation

/// Module identity for the F0 smoke report, which proves at runtime that the
/// library actually linked into the signed bundle. Retire it together with
/// `SmokeReport` once the real panel replaces the probe.
public enum WRNetwork {
    public static let moduleName = "WRNetwork"
}
