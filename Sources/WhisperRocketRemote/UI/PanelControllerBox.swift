import Foundation

/// A one-slot box that breaks the chicken-and-egg between the panel window and
/// the SwiftUI view inside it.
///
/// The view has to be able to tell the controller its size, and the controller
/// cannot be built without the view. A box is filled in immediately after both
/// exist, and the reference is weak so the closure the view holds can never
/// keep the window alive.
@MainActor
final class PanelControllerBox {
    weak var controller: PanelController?
    init() {}
}
