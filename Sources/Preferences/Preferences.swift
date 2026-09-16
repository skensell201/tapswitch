import Foundation

@MainActor
public final class Preferences {
    public static let fingersRange = 3...5
    public static let tapsRange = 1...3

    /// Fires after any value is written.
    public var onChange: (() -> Void)?

    private enum Key {
        static let enabled = "enabled"
        static let fingers = "fingers"
        static let taps = "taps"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var isEnabled: Bool {
        get { defaults.object(forKey: Key.enabled) as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: Key.enabled)
            onChange?()
        }
    }

    public var fingers: Int {
        get { Self.fingersRange.clamping(defaults.object(forKey: Key.fingers) as? Int ?? 5) }
        set {
            defaults.set(Self.fingersRange.clamping(newValue), forKey: Key.fingers)
            onChange?()
        }
    }

    public var taps: Int {
        get { Self.tapsRange.clamping(defaults.object(forKey: Key.taps) as? Int ?? 2) }
        set {
            defaults.set(Self.tapsRange.clamping(newValue), forKey: Key.taps)
            onChange?()
        }
    }
}

private extension ClosedRange where Bound == Int {
    func clamping(_ value: Int) -> Int {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}
