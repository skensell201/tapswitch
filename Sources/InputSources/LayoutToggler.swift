import Foundation

/// Toggles between the current layout and the one used before it — the same
/// thing the fn/🌐 key does. With more than two layouts enabled it alternates
/// the last two.
@MainActor
public final class LayoutToggler {
    private let provider: InputSourceProvider
    /// The layout to return to. Nil until a switch has been seen.
    private var previous: InputSource?
    /// What we last knew to be selected; lets a change notification tell us
    /// what it was before.
    private var lastSeen: InputSource?

    public init(provider: InputSourceProvider) {
        self.provider = provider
        lastSeen = provider.current()
        provider.onSelectionChanged = { [weak self] in
            self?.selectionChanged()
        }
    }

    public func toggle() {
        guard let current = provider.current() else { return }
        let enabled = provider.enabledKeyboardLayouts()

        let target: InputSource?
        if let previous, previous != current, enabled.contains(previous) {
            target = previous
        } else {
            target = enabled.first { $0 != current }
        }
        guard let target else { return }

        provider.select(target)
        previous = current
        lastSeen = target
    }

    private func selectionChanged() {
        let now = provider.current()
        guard now != lastSeen else { return }
        previous = lastSeen
        lastSeen = now
    }
}
