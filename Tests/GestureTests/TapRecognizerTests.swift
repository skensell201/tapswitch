import Testing
@testable import Gesture

@MainActor
@Suite("Tap recognizer")
struct TapRecognizerTests {
    /// `n` fingers spread along x; `shift` slides them all, to fake a swipe.
    private func frame(_ t: Double, _ n: Int, shift: Double = 0) -> TouchFrame {
        TouchFrame(
            timestamp: t,
            contacts: (0..<n).map { TouchContact(id: $0, x: 0.1 * Double($0) + shift, y: 0.5) })
    }

    /// A recognizer with a counter attached, so each test reads one number.
    private func make(fingers: Int = 5, taps: Int = 1) -> (TapRecognizer, () -> Int) {
        let recognizer = TapRecognizer(config: TapRecognizerConfig(fingers: fingers, taps: taps))
        var count = 0
        recognizer.onRecognized = { count += 1 }
        return (recognizer, { count })
    }

    @Test("five fingers down and up is a tap")
    func singleTap() {
        let (r, hits) = make()
        r.process(frame(0, 5))
        r.process(frame(0.1, 0))
        #expect(hits() == 1)
    }

    @Test("fingers landing one frame at a time still make a tap")
    func gradualLanding() {
        let (r, hits) = make()
        r.process(frame(0, 2))
        r.process(frame(0.01, 4))
        r.process(frame(0.02, 5))
        r.process(frame(0.1, 0))
        #expect(hits() == 1)
    }

    @Test("holding longer than maxTapDuration is not a tap")
    func tooLong() {
        let (r, hits) = make()
        r.process(frame(0, 5))
        r.process(frame(0.5, 5))
        r.process(frame(0.6, 0))
        #expect(hits() == 0)
    }

    @Test("a sixth finger cancels")
    func extraFinger() {
        let (r, hits) = make()
        r.process(frame(0, 5))
        r.process(frame(0.05, 6))
        r.process(frame(0.1, 0))
        #expect(hits() == 0)
    }

    @Test("fingers that move are a swipe, not a tap")
    func swipe() {
        let (r, hits) = make()
        r.process(frame(0, 5))
        r.process(frame(0.05, 5, shift: 0.2))
        r.process(frame(0.1, 0))
        #expect(hits() == 0)
    }

    @Test("a resting finger neither starts nor blocks a tap")
    func restingFinger() {
        let (r, hits) = make()
        r.process(frame(0, 1))
        r.process(frame(0.02, 5))
        r.process(frame(0.1, 1))
        #expect(hits() == 1)
    }

    @Test("after a cancel nothing counts until every finger is lifted")
    func cancelWaitsForClearTrackpad() {
        let (r, hits) = make()
        r.process(frame(0, 5))
        r.process(frame(0.02, 6))
        r.process(frame(0.05, 5))
        r.process(frame(0.08, 0))
        #expect(hits() == 0)
        r.process(frame(0.2, 5))
        r.process(frame(0.3, 0))
        #expect(hits() == 1)
    }

    @Test("finger count comes from the config")
    func threeFingers() {
        let (r, hits) = make(fingers: 3)
        r.process(frame(0, 3))
        r.process(frame(0.1, 0))
        #expect(hits() == 1)
        r.process(frame(0.5, 3))
        r.process(frame(0.51, 5))
        r.process(frame(0.6, 0))
        #expect(hits() == 1)
    }
}
