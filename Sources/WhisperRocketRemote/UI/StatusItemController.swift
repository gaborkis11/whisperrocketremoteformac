import AppKit

/// The menu-bar item: one rocket, four states, one menu.
///
/// The image is rebuilt whenever the state *or the menu bar's appearance*
/// changes. The appearance part matters because the badged image cannot be a
/// template — a template image has no colours, and the badge is the whole point
/// — so its rocket has to be painted in the menu bar's own ink, and the menu
/// bar can go dark without the app doing so (a dark wallpaper is enough).
/// `effectiveAppearance` on the status button is the only thing that knows.
@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private var appearanceObservation: NSKeyValueObservation?

    /// Filled while the microphone is open or an upload is in flight.
    private(set) var style: StatusItemIcon.Style = .outline
    /// The red dot: at least one recording failed and is waiting for the user.
    private(set) var showsBadge = false

    /// The capsule hangs off this. `nil` only if AppKit refused us an item.
    var button: NSStatusBarButton? { statusItem.button }

    /// Whether the *menu bar* is dark right now, which is not the same question
    /// as whether the app is: a dark wallpaper alone is enough.
    var isMenuBarDark: Bool {
        statusItem.button?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    init(menu: NSMenu) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // AppKit tracks the click itself once the item has a menu: left and
        // right both open it, the highlight is the system's, and nothing here
        // needs an action.
        statusItem.menu = menu

        if let button = statusItem.button {
            appearanceObservation = button.observe(\.effectiveAppearance) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    // Only the badged composite depends on the appearance; the
                    // template flavour is tinted by AppKit itself.
                    guard let self, self.showsBadge else { return }
                    self.refreshImage()
                }
            }
        }
        refreshImage()
    }

    /// Sets both flags at once, so one phase change never paints the icon twice.
    func update(style: StatusItemIcon.Style, showsBadge: Bool) {
        guard style != self.style || showsBadge != self.showsBadge else { return }
        self.style = style
        self.showsBadge = showsBadge
        refreshImage()
    }

    private func refreshImage() {
        guard let button = statusItem.button else { return }
        button.image = StatusItemIcon.image(
            style: style,
            badged: showsBadge,
            appearance: button.effectiveAppearance
        )
        button.toolTip = showsBadge ? L.statusItemAccessibilityFailed : L.statusItemAccessibility
    }
}
