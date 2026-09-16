import Foundation

/// A keyboard layout or input mode, identified by its TIS input source ID
/// (e.g. `com.apple.keylayout.ABC`).
public struct InputSource: Hashable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// What `LayoutToggler` needs from the system. `TISProvider` is the real one.
@MainActor
public protocol InputSourceProvider: AnyObject {
    /// Enabled, selectable keyboard layouts and input modes, in system order.
    func enabledKeyboardLayouts() -> [InputSource]
    func current() -> InputSource?
    func select(_ source: InputSource)
    /// Called whenever the selected layout changes, by anyone.
    var onSelectionChanged: (() -> Void)? { get set }
}
