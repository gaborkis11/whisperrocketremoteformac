import AppKit
import QuartzCore

/// Draws one of the app's own views into a bitmap.
///
/// Used only by ``UIProbes``, and only because `screencapture` needs a Screen
/// Recording permission that an automated check cannot grant itself. Drawing
/// our own view costs nothing and needs no permission — and because it captures
/// the live window, it shows the animation at the moment it is called, which a
/// static `ImageRenderer` snapshot never can.
@MainActor
enum WindowCapture {
    static func image(of view: NSView) -> NSBitmapImageRep? {
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        // `layer.render(in:)` draws the *model* layer tree, so anything SwiftUI
        // has queued but not committed is simply not there yet — which comes out
        // as a nearly blank image. Flushing the transaction is what makes the
        // capture show what is actually on screen.
        view.window?.displayIfNeeded()
        CATransaction.flush()

        // SwiftUI content is layer-backed, so the layer tree is the truth;
        // `cacheDisplay` alone misses sublayers on a hosting view.
        if let layer = view.layer {
            let scale = view.window?.backingScaleFactor ?? 2
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(bounds.width * scale),
                pixelsHigh: Int(bounds.height * scale),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ) else { return nil }
            // Setting `size` in *points* is what tells the context it is a 2×
            // representation; it then scales point-space drawing to pixels on
            // its own. Scaling the CTM as well would draw everything twice as
            // large and clip three quarters of the panel away.
            rep.size = bounds.size

            guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            // A bitmap context is y-up; an `NSHostingView` is y-down. Without
            // this, SwiftUI content comes out upside down while AppKit content
            // (the panel's effect view) does not.
            if view.isFlipped {
                context.cgContext.translateBy(x: 0, y: bounds.height)
                context.cgContext.scaleBy(x: 1, y: -1)
            }
            layer.render(in: context.cgContext)
            NSGraphicsContext.restoreGraphicsState()
            return rep
        }

        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        view.cacheDisplay(in: bounds, to: rep)
        return rep
    }
}
