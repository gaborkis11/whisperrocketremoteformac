import Foundation

/// F0 placeholder — replaced by the real core logic (RecorderState, UploadPlan, …) in F1.
public enum WRCore {
    public static let moduleName = "WRCore"

    public static func greeting(for name: String) -> String {
        "Hello, \(name)!"
    }
}
