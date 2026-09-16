import Foundation
import Testing
@testable import Preferences

@MainActor
@Suite("Preferences")
struct PreferencesTests {
    /// Each test gets its own defaults domain so nothing leaks between tests or
    /// into the real app's settings.
    private let suite = "tapswitch.tests.\(UUID().uuidString)"

    private func make() -> (Preferences, UserDefaults) {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (Preferences(defaults: defaults), defaults)
    }

    @Test("defaults are five fingers, two taps, enabled")
    func defaults() {
        let (p, _) = make()
        #expect(p.fingers == 5)
        #expect(p.taps == 2)
        #expect(p.isEnabled == true)
    }

    @Test("values round-trip through defaults")
    func roundTrip() {
        let (p, defaults) = make()
        p.fingers = 4
        p.taps = 3
        p.isEnabled = false
        let again = Preferences(defaults: defaults)
        #expect(again.fingers == 4)
        #expect(again.taps == 3)
        #expect(again.isEnabled == false)
    }

    @Test("out-of-range stored values are clamped on read")
    func clampsOnRead() {
        let (p, defaults) = make()
        defaults.set(9, forKey: "fingers")
        defaults.set(0, forKey: "taps")
        #expect(p.fingers == 5)
        #expect(p.taps == 1)
        defaults.set(0, forKey: "fingers")
        defaults.set(7, forKey: "taps")
        #expect(p.fingers == 3)
        #expect(p.taps == 3)
    }

    @Test("setters clamp")
    func clampsOnWrite() {
        let (p, _) = make()
        p.fingers = 1
        p.taps = 10
        #expect(p.fingers == 3)
        #expect(p.taps == 3)
    }

    @Test("every change fires onChange")
    func onChange() {
        let (p, _) = make()
        var fired = 0
        p.onChange = { fired += 1 }
        p.fingers = 4
        p.taps = 1
        p.isEnabled = false
        #expect(fired == 3)
    }
}
