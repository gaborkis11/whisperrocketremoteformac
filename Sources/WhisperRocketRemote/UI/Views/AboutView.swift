import AppKit
import SwiftUI

/// The About window's contents, laid out exactly as the Linux app's
/// `about_window.py`: the icon, the name, the version, what it does, who made
/// it, and the copyright — in that order, centred, in one narrow column.
///
/// **Deliberately English, and deliberately not localized.** The original is,
/// and the things it says are names: "WhisperRocket Remote", "Studio137",
/// "Gabor Kis". Only the menu item that opens this window is translated.
///
/// The gap between the version and the first divider is where a "Check for
/// updates" button goes when there is something to check against. There is not
/// yet, so there is no button — but the anatomy has the room for one.
struct AboutView: View {
    /// The width the original was drawn at. Fixed, because every line in here
    /// is short and a resizable About window is a window with nothing to do.
    private static let windowWidth: Double = 340
    private static let iconSize: Double = 64

    private static let repository = URL(string: "https://github.com/gaborkis11/WhisperRocket")!

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 10) {
            icon

            Text("WhisperRocket Remote")
                .font(.system(size: 16, weight: .bold))

            Text(Self.versionLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()
                .padding(.vertical, 2)

            Text("Dictate from your Mac through your WhisperRocket host")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Text("Powered by ") + Text("Studio137").bold()

            Divider()
                .padding(.vertical, 2)

            VStack(spacing: 3) {
                Text("Developed by")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Gabor Kis")
                    .bold()
                // Drawn rather than a `Link`: `ImageRenderer` cannot draw one —
                // `--about-probe` got a yellow "unsupported control" block
                // where the link should have been — and this window's whole
                // automated check is that still.
                Button {
                    openURL(Self.repository)
                } label: {
                    Text("GitHub")
                        .font(.callout)
                        .foregroundStyle(Color.accentColor)
                        .underline()
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help(Self.repository.absoluteString)
            }

            Text("© 2026 Gabor Kis. All rights reserved.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        // The frame goes *outside* the padding, so this is the window's width
        // rather than the column's.
        .frame(width: Self.windowWidth)
    }

    // MARK: - The icon

    @ViewBuilder
    private var icon: some View {
        if let image = Self.applicationIcon {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: Self.iconSize, height: Self.iconSize)
                .accessibilityHidden(true)
        } else {
            // `swift run` has no bundle and therefore no icns. The motif the
            // icon is drawn from is in the binary either way, so the window
            // still signs its name.
            RocketShape()
                .stroke(.primary, style: StrokeStyle(lineWidth: 4, lineJoin: .round))
                .frame(width: Self.iconSize, height: Self.iconSize)
                .accessibilityHidden(true)
        }
    }

    /// `Contents/Resources/AppIcon.icns`, by the name `Info.plist` gives it.
    /// `nil` outside a bundle, which is what the fallback above is for —
    /// `NSApp.applicationIconImage` would answer with the generic macOS
    /// application icon instead, and a generic icon in an About window is worse
    /// than none.
    private static var applicationIcon: NSImage? {
        guard let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String
        else { return nil }
        return Bundle.main.image(forResource: name)
    }

    // MARK: - The version

    /// "Version 0.2.0 (2)", straight out of `Info.plist`. Outside a bundle
    /// there is no plist at all, and saying so is more honest than inventing a
    /// number.
    static var versionLine: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (short, build) {
        case (let short?, let build?): return "Version \(short) (\(build))"
        case (let short?, nil): return "Version \(short)"
        default: return "Version dev"
        }
    }
}
