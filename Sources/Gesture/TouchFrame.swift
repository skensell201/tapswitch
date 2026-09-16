import Foundation

/// One finger on the trackpad. Coordinates are normalized to 0…1 across the
/// device, which is what the movement threshold in `TapRecognizerConfig` is in.
public struct TouchContact: Equatable, Sendable {
    public let id: Int
    public let x: Double
    public let y: Double

    public init(id: Int, x: Double, y: Double) {
        self.id = id
        self.x = x
        self.y = y
    }
}

/// Every finger currently down, at one instant. `timestamp` is in seconds on
/// any monotonic clock — the recognizer only ever subtracts two of them.
public struct TouchFrame: Equatable, Sendable {
    public let timestamp: TimeInterval
    public let contacts: [TouchContact]

    public init(timestamp: TimeInterval, contacts: [TouchContact]) {
        self.timestamp = timestamp
        self.contacts = contacts
    }
}
