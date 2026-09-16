import Foundation

public struct TapRecognizerConfig: Equatable, Sendable {
    public var fingers: Int
    public var taps: Int
    /// Touch-down to lift, in seconds. Longer is a hold.
    public var maxTapDuration: TimeInterval
    /// Lift to the next touch-down, in seconds. Longer starts a new series.
    public var maxTapGap: TimeInterval
    /// How far any finger may travel, in normalized device units, before the
    /// gesture is a swipe.
    public var maxMovement: Double

    public init(
        fingers: Int,
        taps: Int,
        maxTapDuration: TimeInterval = 0.30,
        maxTapGap: TimeInterval = 0.40,
        maxMovement: Double = 0.05
    ) {
        self.fingers = fingers
        self.taps = taps
        self.maxTapDuration = maxTapDuration
        self.maxTapGap = maxTapGap
        self.maxMovement = maxMovement
    }
}

/// Recognizes `taps` quick taps with exactly `fingers` fingers. Pure: no timers,
/// no clock — timeouts are judged against the timestamps of incoming frames,
/// which is what makes it testable with synthetic frames.
@MainActor
public final class TapRecognizer {
    public var onRecognized: (() -> Void)?

    private let config: TapRecognizerConfig

    private struct Origin {
        let x: Double
        let y: Double
    }

    private enum State {
        /// Nothing in progress.
        case idle
        /// `fingers` fingers are down; waiting for them to lift.
        case touching(since: TimeInterval, origins: [Int: Origin])
        /// A tap finished; waiting for the next one in the series.
        case lifted(at: TimeInterval)
        /// Something went wrong mid-gesture; ignore everything until the
        /// trackpad is empty, so lifting one of six fingers does not become a tap.
        case cancelled
    }

    private var state: State = .idle
    private var completedTaps = 0

    public init(config: TapRecognizerConfig) {
        self.config = config
    }

    public func reset() {
        state = .idle
        completedTaps = 0
    }

    public func process(_ frame: TouchFrame) {
        let count = frame.contacts.count
        switch state {
        case .idle:
            if count == config.fingers {
                begin(frame)
            }

        case .cancelled:
            if count == 0 {
                state = .idle
            }

        case .lifted(let liftedAt):
            if frame.timestamp - liftedAt > config.maxTapGap {
                // Series expired. This frame may still open a new one.
                completedTaps = 0
                state = .idle
                if count == config.fingers {
                    begin(frame)
                }
            } else if count == config.fingers {
                begin(frame)
            }

        case .touching(let since, let origins):
            if count > config.fingers
                || frame.timestamp - since > config.maxTapDuration
                || moved(frame, from: origins)
            {
                cancel()
            } else if count < config.fingers {
                complete(at: frame.timestamp)
            }
        }
    }

    private func begin(_ frame: TouchFrame) {
        var origins: [Int: Origin] = [:]
        for contact in frame.contacts {
            origins[contact.id] = Origin(x: contact.x, y: contact.y)
        }
        state = .touching(since: frame.timestamp, origins: origins)
    }

    private func complete(at timestamp: TimeInterval) {
        completedTaps += 1
        if completedTaps >= config.taps {
            completedTaps = 0
            state = .idle
            onRecognized?()
        } else {
            state = .lifted(at: timestamp)
        }
    }

    private func cancel() {
        completedTaps = 0
        state = .cancelled
    }

    private func moved(_ frame: TouchFrame, from origins: [Int: Origin]) -> Bool {
        frame.contacts.contains { contact in
            guard let origin = origins[contact.id] else { return false }
            let dx = contact.x - origin.x
            let dy = contact.y - origin.y
            return (dx * dx + dy * dy).squareRoot() > config.maxMovement
        }
    }
}
