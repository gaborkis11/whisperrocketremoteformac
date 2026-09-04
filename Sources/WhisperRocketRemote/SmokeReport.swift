import Foundation
import KeyboardShortcuts
import WRCore
import WRNetwork

/// Proves at runtime that every link in the F0 chain actually resolved:
/// both libraries, the SPM resource bundle, and the signed app bundle identity.
enum SmokeReport {
    static func summary() -> [String] {
        [
            "bundle: \(Bundle.main.bundleIdentifier ?? "<none>")",
            "\(WRCore.moduleName) + \(WRNetwork.moduleName) linked",
            "sounds: \(soundStatus())",
            "rebuild-marker: 2",
        ]
    }

    static func emit(shortcut: KeyboardShortcuts.Shortcut?) {
        var lines = summary()
        lines.append("hotkey: \(shortcut.map(String.init(describing:)) ?? "<unset>")")
        lines.append("path: \(Bundle.main.bundlePath)")
        for line in lines {
            print("[smoke] \(line)")
            NSLog("[smoke] %@", line)
        }
        fflush(stdout)
    }

    private static func soundStatus() -> String {
        let names = ["start_soft_click_smooth", "stop_soft_click_smooth"]
        let found = names.filter { soundURL(named: $0) != nil }
        return "\(found.count)/\(names.count) found"
    }

    private static func soundURL(named name: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: "wav", subdirectory: "Sounds")
            ?? Bundle.module.url(forResource: name, withExtension: "wav")
    }
}
