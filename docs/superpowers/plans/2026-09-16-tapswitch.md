# TapSwitch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS menu bar app that toggles the keyboard layout on an N-finger, K-tap trackpad gesture (default 5 fingers, 2 taps).

**Architecture:** Four leaf SwiftPM modules — `Gesture` (touch model + pure tap state machine), `Multitouch` (private MultitouchSupport.framework behind `TouchSource`), `InputSources` (Carbon TIS behind `InputSourceProvider` + `LayoutToggler`), `Preferences` (UserDefaults) — wired by the `TapSwitchApp` executable. Everything runs on the main actor: the Multitouch C callback hops to the main queue per frame, so no other module needs locks.

**Tech Stack:** Swift 6.3, SwiftPM (tools 6.2), macOS 26, Swift Testing, AppKit, Carbon HIToolbox (TIS), ServiceManagement (SMAppService), private MultitouchSupport.framework via dlopen.

**Spec:** `docs/superpowers/specs/2026-09-16-tapswitch-design.md`. Two small deviations, decided here: `TouchFrame` lives in `Gesture` (the recognizer's vocabulary) and `Multitouch` depends on `Gesture`; frames are hopped to the main queue per frame rather than once after recognition, so `TapRecognizer` is `@MainActor` and needs no locks.

---

## File structure

```
tapswitch/
  Package.swift
  Sources/
    Gesture/
      TouchFrame.swift           TouchContact, TouchFrame (input model)
      TapRecognizer.swift        TapRecognizerConfig, TapRecognizer (state machine)
    Multitouch/
      MultitouchFramework.swift  dlopen/dlsym of the private framework, C types
      MultitouchDeviceSource.swift  TouchSource protocol, MultitouchError, device source
    InputSources/
      InputSource.swift          InputSource value, InputSourceProvider protocol
      LayoutToggler.swift        toggle logic + history
      TISProvider.swift          Carbon TIS implementation of the provider
    Preferences/
      Preferences.swift
    TapSwitchApp/
      TapSwitchApp.swift         @main, NSApplication bootstrap
      AppDelegate.swift          wiring, wake handling
      StatusMenu.swift           NSStatusItem + menu
      LaunchAtLogin.swift        SMAppService wrapper
  Tests/
    GestureTests/TapRecognizerTests.swift
    InputSourcesTests/LayoutTogglerTests.swift
    PreferencesTests/PreferencesTests.swift
  Resources/Info.plist
  Scripts/bundle.sh  Scripts/run.sh  Scripts/make-dev-cert.sh
  README.md
```

---

### Task 1: Package skeleton

**Files:**
- Create: `Package.swift`
- Create: `Sources/Gesture/TouchFrame.swift`
- Create: `Sources/Multitouch/MultitouchDeviceSource.swift` (stub)
- Create: `Sources/InputSources/InputSource.swift` (stub)
- Create: `Sources/Preferences/Preferences.swift` (stub)
- Create: `Sources/TapSwitchApp/TapSwitchApp.swift` (stub)
- Create: `Tests/GestureTests/TapRecognizerTests.swift` (empty suite)
- Create: `Tests/InputSourcesTests/LayoutTogglerTests.swift` (empty suite)
- Create: `Tests/PreferencesTests/PreferencesTests.swift` (empty suite)

- [ ] **Step 1: Write Package.swift**

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "tapswitch",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "tapswitch", targets: ["TapSwitchApp"])
    ],
    targets: [
        // Pure: the touch vocabulary and the tap state machine. Imports Foundation only.
        .target(name: "Gesture"),
        // The only module that touches the private framework. Produces Gesture's frames.
        .target(name: "Multitouch", dependencies: ["Gesture"]),
        .target(name: "InputSources"),
        .target(name: "Preferences"),
        .executableTarget(
            name: "TapSwitchApp",
            dependencies: ["Gesture", "Multitouch", "InputSources", "Preferences"]),
        .testTarget(name: "GestureTests", dependencies: ["Gesture"]),
        .testTarget(name: "InputSourcesTests", dependencies: ["InputSources"]),
        .testTarget(name: "PreferencesTests", dependencies: ["Preferences"])
    ]
)
```

- [ ] **Step 2: Write the touch model (real, not a stub)**

`Sources/Gesture/TouchFrame.swift`:

```swift
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
```

- [ ] **Step 3: Write stubs so every target compiles**

`Sources/Multitouch/MultitouchDeviceSource.swift`:
```swift
import Gesture
```

`Sources/InputSources/InputSource.swift`:
```swift
import Foundation
```

`Sources/Preferences/Preferences.swift`:
```swift
import Foundation
```

`Sources/TapSwitchApp/TapSwitchApp.swift`:
```swift
import AppKit

@main
struct TapSwitchApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
```

`Tests/GestureTests/TapRecognizerTests.swift`:
```swift
import Testing
@testable import Gesture

@Suite("Tap recognizer")
struct TapRecognizerTests {}
```

`Tests/InputSourcesTests/LayoutTogglerTests.swift`:
```swift
import Testing
@testable import InputSources

@Suite("Layout toggler")
struct LayoutTogglerTests {}
```

`Tests/PreferencesTests/PreferencesTests.swift`:
```swift
import Testing
@testable import Preferences

@Suite("Preferences")
struct PreferencesTests {}
```

- [ ] **Step 4: Verify the package builds and tests run**

Run: `swift build && swift test`
Expected: build succeeds; `swift test` reports 0 tests, no failures.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Scaffold SwiftPM package with module layout"
```

---

### Task 2: TapRecognizer — single tap

**Files:**
- Create: `Sources/Gesture/TapRecognizer.swift`
- Modify: `Tests/GestureTests/TapRecognizerTests.swift`

- [ ] **Step 1: Write the failing tests**

Replace `Tests/GestureTests/TapRecognizerTests.swift` with:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter GestureTests`
Expected: compile error — `TapRecognizer` / `TapRecognizerConfig` not found.

- [ ] **Step 3: Implement the recognizer**

`Sources/Gesture/TapRecognizer.swift`:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter GestureTests`
Expected: 8 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Gesture Tests/GestureTests
git commit -m "Add TapRecognizer with single-tap recognition"
```

---

### Task 3: TapRecognizer — tap series

**Files:**
- Modify: `Tests/GestureTests/TapRecognizerTests.swift`

The implementation in Task 2 already carries `completedTaps`; these tests pin
the series behaviour down. If any fails, fix `TapRecognizer` — do not weaken
the test.

- [ ] **Step 1: Add the failing tests**

Append inside `TapRecognizerTests`, before the closing brace:

```swift
    @Test("two taps within the gap are a double tap")
    func doubleTap() {
        let (r, hits) = make(taps: 2)
        r.process(frame(0, 5))
        r.process(frame(0.1, 0))
        #expect(hits() == 0)
        r.process(frame(0.3, 5))
        r.process(frame(0.4, 0))
        #expect(hits() == 1)
    }

    @Test("one tap is not a double tap")
    func singleIsNotDouble() {
        let (r, hits) = make(taps: 2)
        r.process(frame(0, 5))
        r.process(frame(0.1, 0))
        #expect(hits() == 0)
    }

    @Test("a gap longer than maxTapGap starts a new series")
    func gapTooLong() {
        let (r, hits) = make(taps: 2)
        r.process(frame(0, 5))
        r.process(frame(0.1, 0))
        r.process(frame(0.6, 5))
        r.process(frame(0.7, 0))
        #expect(hits() == 0)
        r.process(frame(0.8, 5))
        r.process(frame(0.9, 0))
        #expect(hits() == 1)
    }

    @Test("a cancelled tap clears the series")
    func cancelClearsSeries() {
        let (r, hits) = make(taps: 2)
        r.process(frame(0, 5))
        r.process(frame(0.1, 0))
        r.process(frame(0.3, 5))
        r.process(frame(0.35, 5, shift: 0.2))
        r.process(frame(0.4, 0))
        r.process(frame(0.6, 5))
        r.process(frame(0.7, 0))
        #expect(hits() == 0)
    }

    @Test("reset clears the series")
    func resetClearsSeries() {
        let (r, hits) = make(taps: 2)
        r.process(frame(0, 5))
        r.process(frame(0.1, 0))
        r.reset()
        r.process(frame(0.3, 5))
        r.process(frame(0.4, 0))
        #expect(hits() == 0)
    }

    @Test("the series counts again after recognition")
    func seriesRestartsAfterRecognition() {
        let (r, hits) = make(taps: 2)
        for i in 0..<2 {
            let base = Double(i) * 2
            r.process(frame(base, 5))
            r.process(frame(base + 0.1, 0))
            r.process(frame(base + 0.3, 5))
            r.process(frame(base + 0.4, 0))
        }
        #expect(hits() == 2)
    }
```

- [ ] **Step 2: Run tests**

Run: `swift test --filter GestureTests`
Expected: 14 tests pass. If one fails, fix the recognizer, re-run.

- [ ] **Step 3: Commit**

```bash
git add Tests/GestureTests
git commit -m "Pin down tap-series behaviour of TapRecognizer"
```

---

### Task 4: Preferences

**Files:**
- Modify: `Sources/Preferences/Preferences.swift`
- Modify: `Tests/PreferencesTests/PreferencesTests.swift`

- [ ] **Step 1: Write the failing tests**

Replace `Tests/PreferencesTests/PreferencesTests.swift` with:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PreferencesTests`
Expected: compile error — `Preferences` has no such initializer/members.

- [ ] **Step 3: Implement**

Replace `Sources/Preferences/Preferences.swift` with:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PreferencesTests`
Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Preferences Tests/PreferencesTests
git commit -m "Add UserDefaults-backed Preferences"
```

---

### Task 5: LayoutToggler

**Files:**
- Modify: `Sources/InputSources/InputSource.swift`
- Create: `Sources/InputSources/LayoutToggler.swift`
- Modify: `Tests/InputSourcesTests/LayoutTogglerTests.swift`

- [ ] **Step 1: Write the failing tests**

Replace `Tests/InputSourcesTests/LayoutTogglerTests.swift` with:

```swift
import Testing
@testable import InputSources

/// Stands in for TIS. `select` flips `current` and fires the change callback
/// synchronously — the real system posts a distributed notification shortly
/// after — and `externallySelect` fakes the user pressing fn.
@MainActor
private final class FakeProvider: InputSourceProvider {
    var enabled: [InputSource]
    var currentSource: InputSource?
    var selected: [InputSource] = []
    var onSelectionChanged: (() -> Void)?

    init(enabled: [InputSource], current: InputSource?) {
        self.enabled = enabled
        self.currentSource = current
    }

    func enabledKeyboardLayouts() -> [InputSource] { enabled }
    func current() -> InputSource? { currentSource }

    func select(_ source: InputSource) {
        selected.append(source)
        currentSource = source
        onSelectionChanged?()
    }

    func externallySelect(_ source: InputSource) {
        currentSource = source
        onSelectionChanged?()
    }
}

@MainActor
@Suite("Layout toggler")
struct LayoutTogglerTests {
    private let ru = InputSource(id: "com.apple.keylayout.Russian", name: "Russian")
    private let en = InputSource(id: "com.apple.keylayout.ABC", name: "ABC")
    private let de = InputSource(id: "com.apple.keylayout.German", name: "German")

    @Test("with two layouts, toggle picks the other one")
    func togglesToOther() {
        let provider = FakeProvider(enabled: [ru, en], current: ru)
        let toggler = LayoutToggler(provider: provider)
        toggler.toggle()
        #expect(provider.selected == [en])
        toggler.toggle()
        #expect(provider.selected == [en, ru])
    }

    @Test("with three layouts, toggle alternates the last two")
    func alternatesLastTwo() {
        let provider = FakeProvider(enabled: [ru, en, de], current: de)
        let toggler = LayoutToggler(provider: provider)
        toggler.toggle()
        #expect(provider.selected == [ru])
        toggler.toggle()
        #expect(provider.selected == [ru, de])
        toggler.toggle()
        #expect(provider.selected == [ru, de, ru])
    }

    @Test("a previous layout that was disabled is skipped")
    func previousDisabled() {
        let provider = FakeProvider(enabled: [ru, en, de], current: ru)
        let toggler = LayoutToggler(provider: provider)
        toggler.toggle()
        #expect(provider.currentSource == en)
        provider.enabled = [en, de]
        toggler.toggle()
        #expect(provider.selected == [en, de])
    }

    @Test("a single layout is a no-op")
    func singleLayout() {
        let provider = FakeProvider(enabled: [ru], current: ru)
        let toggler = LayoutToggler(provider: provider)
        toggler.toggle()
        #expect(provider.selected.isEmpty)
    }

    @Test("no current layout is a no-op")
    func noCurrent() {
        let provider = FakeProvider(enabled: [ru, en], current: nil)
        let toggler = LayoutToggler(provider: provider)
        toggler.toggle()
        #expect(provider.selected.isEmpty)
    }

    @Test("switching with fn between taps updates the history")
    func externalSwitchUpdatesHistory() {
        let provider = FakeProvider(enabled: [ru, en, de], current: ru)
        let toggler = LayoutToggler(provider: provider)
        provider.externallySelect(de)
        toggler.toggle()
        #expect(provider.selected == [ru])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter InputSourcesTests`
Expected: compile error — `InputSource`, `InputSourceProvider`, `LayoutToggler` not found.

- [ ] **Step 3: Implement the model and protocol**

Replace `Sources/InputSources/InputSource.swift` with:

```swift
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
```

- [ ] **Step 4: Implement the toggler**

`Sources/InputSources/LayoutToggler.swift`:

```swift
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
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter InputSourcesTests`
Expected: 6 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/InputSources Tests/InputSourcesTests
git commit -m "Add LayoutToggler with fn-style previous-layout history"
```

---

### Task 6: TISProvider (Carbon)

**Files:**
- Create: `Sources/InputSources/TISProvider.swift`

No unit test — it is a thin wrapper over system calls; it gets exercised by
the smoke run in Task 10.

- [ ] **Step 1: Implement**

```swift
import AppKit
import Carbon

/// `InputSourceProvider` over Carbon's Text Input Source API. Must be used from
/// the main thread: `TISSelectInputSource` called elsewhere reports success and
/// changes nothing.
@MainActor
public final class TISProvider: InputSourceProvider {
    public var onSelectionChanged: (() -> Void)?

    private var observer: NSObjectProtocol?

    public init() {
        let name = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
        observer = DistributedNotificationCenter.default().addObserver(
            forName: name, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onSelectionChanged?()
            }
        }
    }

    deinit {
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    public func enabledKeyboardLayouts() -> [InputSource] {
        let filter: [CFString: Any] = [
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsEnabled: true,
            kTISPropertyInputSourceIsSelectCapable: true
        ]
        return sources(matching: filter).compactMap(Self.describe)
    }

    public func current() -> InputSource? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        return Self.describe(source)
    }

    public func select(_ source: InputSource) {
        let filter: [CFString: Any] = [kTISPropertyInputSourceID: source.id]
        guard let tis = sources(matching: filter).first else { return }
        TISSelectInputSource(tis)
    }

    private func sources(matching filter: [CFString: Any]) -> [TISInputSource] {
        guard let list = TISCreateInputSourceList(filter as CFDictionary, false)?
            .takeRetainedValue() as? [TISInputSource]
        else { return [] }
        return list
    }

    private static func describe(_ source: TISInputSource) -> InputSource? {
        guard let id = string(property: kTISPropertyInputSourceID, of: source),
              let name = string(property: kTISPropertyLocalizedName, of: source)
        else { return nil }
        return InputSource(id: id, name: name)
    }

    private static func string(property: CFString, of source: TISInputSource) -> String? {
        guard let raw = TISGetInputSourceProperty(source, property) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: succeeds with no warnings in `InputSources`.

- [ ] **Step 3: Commit**

```bash
git add Sources/InputSources/TISProvider.swift
git commit -m "Add TISProvider over Carbon Text Input Sources"
```

---

### Task 7: Multitouch — private framework loader

**Files:**
- Create: `Sources/Multitouch/MultitouchFramework.swift`

- [ ] **Step 1: Implement the loader**

```swift
import Foundation

// Layout of MultitouchSupport's per-finger record, as reverse-engineered and used
// by MiddleClick, Fingers, OpenMultitouchSupport and others. Field order and
// types must not change: the framework writes these bytes, we only read them.

struct MTPoint {
    var x: Float
    var y: Float
}

struct MTReadout {
    var position: MTPoint
    var velocity: MTPoint
}

struct MTFinger {
    var frame: Int32
    var timestamp: Double
    var identifier: Int32
    /// 3 = touch beginning, 4 = touching; anything else is hover or lift-off.
    var state: Int32
    var foo3: Int32
    var foo4: Int32
    /// Position normalized to 0…1 across the device.
    var normalized: MTReadout
    var size: Float
    var zero1: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var mm: MTReadout
    var zero2: (Int32, Int32)
    var unk2: Float
}

typealias MTDeviceRef = UnsafeMutableRawPointer
typealias MTContactCallback = @convention(c) (
    MTDeviceRef?, UnsafeMutablePointer<MTFinger>?, Int32, Double, Int32
) -> Int32

/// `dlopen`'d handle to the private framework plus the five entry points we use.
struct MultitouchFramework {
    private typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
    private typealias Register = @convention(c) (MTDeviceRef?, MTContactCallback?) -> Void
    private typealias Start = @convention(c) (MTDeviceRef?, Int32) -> Void
    private typealias Stop = @convention(c) (MTDeviceRef?) -> Void

    private let createList: CreateList
    private let register: Register
    private let unregister: Register
    private let start: Start
    private let stop: Stop

    static let path =
        "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"

    static func load() throws -> MultitouchFramework {
        guard let handle = dlopen(path, RTLD_NOW) else {
            throw MultitouchError.frameworkUnavailable("dlopen failed: \(String(cString: dlerror()))")
        }
        func symbol<T>(_ name: String, as _: T.Type) throws -> T {
            guard let sym = dlsym(handle, name) else {
                throw MultitouchError.frameworkUnavailable("missing symbol \(name)")
            }
            return unsafeBitCast(sym, to: T.self)
        }
        return MultitouchFramework(
            createList: try symbol("MTDeviceCreateList", as: CreateList.self),
            register: try symbol("MTRegisterContactFrameCallback", as: Register.self),
            unregister: try symbol("MTUnregisterContactFrameCallback", as: Register.self),
            start: try symbol("MTDeviceStart", as: Start.self),
            stop: try symbol("MTDeviceStop", as: Stop.self))
    }

    /// Every multitouch device. The array owns the device refs; keep it alive
    /// for as long as they are in use.
    func devices() -> (CFArray, [MTDeviceRef])? {
        guard let list = createList()?.takeRetainedValue() else { return nil }
        let refs = (0..<CFArrayGetCount(list)).compactMap { index -> MTDeviceRef? in
            guard let raw = CFArrayGetValueAtIndex(list, index) else { return nil }
            return MTDeviceRef(mutating: raw)
        }
        return (list, refs)
    }

    func startListening(_ device: MTDeviceRef, callback: MTContactCallback) {
        register(device, callback)
        start(device, 0)
    }

    func stopListening(_ device: MTDeviceRef, callback: MTContactCallback) {
        stop(device)
        unregister(device, callback)
    }
}

public enum MultitouchError: Error, Equatable {
    case frameworkUnavailable(String)
    case noDevices
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: succeeds. (`MultitouchDeviceSource.swift` is still the one-line stub.)

- [ ] **Step 3: Commit**

```bash
git add Sources/Multitouch/MultitouchFramework.swift
git commit -m "Add dlopen loader for the private MultitouchSupport framework"
```

---

### Task 8: Multitouch — device source

**Files:**
- Modify: `Sources/Multitouch/MultitouchDeviceSource.swift`

- [ ] **Step 1: Implement**

Replace the stub with:

```swift
import Foundation
import Gesture

/// Anything that produces touch frames. The app talks to this, never to
/// `MultitouchDeviceSource` directly.
@MainActor
public protocol TouchSource: AnyObject {
    var onFrame: ((TouchFrame) -> Void)? { get set }
    func start() throws
    func stop()
}

/// Frames from every attached multitouch device. Only one instance may be
/// started at a time: the framework's callback carries no context pointer, so
/// delivery goes through `active`.
@MainActor
public final class MultitouchDeviceSource: TouchSource {
    public var onFrame: ((TouchFrame) -> Void)?

    private static var active: MultitouchDeviceSource?

    private var framework: MultitouchFramework?
    private var deviceList: CFArray?
    private var devices: [MTDeviceRef] = []

    public init() {}

    public func start() throws {
        stop()
        let framework = try self.framework ?? MultitouchFramework.load()
        self.framework = framework

        guard let (list, refs) = framework.devices(), !refs.isEmpty else {
            throw MultitouchError.noDevices
        }
        deviceList = list
        devices = refs
        Self.active = self
        for device in refs {
            framework.startListening(device, callback: contactCallback)
        }
    }

    public func stop() {
        guard let framework, !devices.isEmpty else { return }
        for device in devices {
            framework.stopListening(device, callback: contactCallback)
        }
        devices = []
        deviceList = nil
        if Self.active === self {
            Self.active = nil
        }
    }

    fileprivate static func deliver(_ frame: TouchFrame) {
        active?.onFrame?(frame)
    }
}

/// Runs on the framework's own thread. Builds an immutable frame and hops to
/// the main queue, so nothing downstream needs to be thread-safe.
private let contactCallback: MTContactCallback = { _, fingers, count, timestamp, _ in
    var contacts: [TouchContact] = []
    if let fingers {
        for index in 0..<Int(count) {
            let finger = fingers[index]
            guard finger.state == 3 || finger.state == 4 else { continue }
            contacts.append(TouchContact(
                id: Int(finger.identifier),
                x: Double(finger.normalized.position.x),
                y: Double(finger.normalized.position.y)))
        }
    }
    let frame = TouchFrame(timestamp: timestamp, contacts: contacts)
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            MultitouchDeviceSource.deliver(frame)
        }
    }
    return 0
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: succeeds, no warnings in `Multitouch`.

- [ ] **Step 3: Commit**

```bash
git add Sources/Multitouch/MultitouchDeviceSource.swift
git commit -m "Add MultitouchDeviceSource delivering frames on the main queue"
```

---

### Task 9: App — status menu, launch at login, wiring

**Files:**
- Create: `Sources/TapSwitchApp/LaunchAtLogin.swift`
- Create: `Sources/TapSwitchApp/StatusMenu.swift`
- Create: `Sources/TapSwitchApp/AppDelegate.swift`
- Modify: `Sources/TapSwitchApp/TapSwitchApp.swift`

- [ ] **Step 1: LaunchAtLogin**

`Sources/TapSwitchApp/LaunchAtLogin.swift`:

```swift
import Foundation
import ServiceManagement

/// `SMAppService` needs a real `.app`; run straight from `swift build` there
/// is none, and the menu item is disabled.
@MainActor
struct LaunchAtLogin {
    var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
```

- [ ] **Step 2: StatusMenu**

`Sources/TapSwitchApp/StatusMenu.swift`:

```swift
import AppKit
import OSLog
import Preferences

@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    enum Status {
        case active
        case disabled
        case trackpadMissing
    }

    private let preferences: Preferences
    private let launchAtLogin: LaunchAtLogin
    private let item: NSStatusItem
    private let menu = NSMenu()
    private var status: Status = .disabled
    private let log = Logger(subsystem: "com.skensell.tapswitch", category: "menu")

    init(preferences: Preferences, launchAtLogin: LaunchAtLogin) {
        self.preferences = preferences
        self.launchAtLogin = launchAtLogin
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        item.button?.image = NSImage(
            systemSymbolName: "keyboard", accessibilityDescription: "TapSwitch")
        menu.delegate = self
        item.menu = menu
        setStatus(.disabled)
    }

    func setStatus(_ status: Status) {
        self.status = status
        item.button?.appearsDisabled = status != .active
    }

    // The menu is rebuilt every time it opens, so checkmarks always match the
    // preferences without any observation plumbing.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if status == .trackpadMissing {
            let missing = NSMenuItem(title: "Trackpad not found", action: nil, keyEquivalent: "")
            missing.isEnabled = false
            menu.addItem(missing)
            menu.addItem(.separator())
        }

        let enabled = NSMenuItem(
            title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.target = self
        enabled.state = preferences.isEnabled ? .on : .off
        menu.addItem(enabled)

        menu.addItem(submenu(
            title: "Fingers", values: Preferences.fingersRange,
            current: preferences.fingers, action: #selector(setFingers(_:))))
        menu.addItem(submenu(
            title: "Taps", values: Preferences.tapsRange,
            current: preferences.taps, action: #selector(setTaps(_:))))

        menu.addItem(.separator())

        let login = NSMenuItem(
            title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.isEnabled = launchAtLogin.isAvailable
        login.state = launchAtLogin.isAvailable && launchAtLogin.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit TapSwitch", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func submenu(
        title: String, values: ClosedRange<Int>, current: Int, action: Selector
    ) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu(title: title)
        for value in values {
            let entry = NSMenuItem(title: "\(value)", action: action, keyEquivalent: "")
            entry.target = self
            entry.tag = value
            entry.state = value == current ? .on : .off
            sub.addItem(entry)
        }
        parent.submenu = sub
        return parent
    }

    @objc private func toggleEnabled() {
        preferences.isEnabled.toggle()
    }

    @objc private func setFingers(_ sender: NSMenuItem) {
        preferences.fingers = sender.tag
    }

    @objc private func setTaps(_ sender: NSMenuItem) {
        preferences.taps = sender.tag
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try launchAtLogin.setEnabled(!launchAtLogin.isEnabled)
        } catch {
            log.error("launch at login: \(error.localizedDescription, privacy: .public)")
        }
    }
}
```

- [ ] **Step 3: AppDelegate**

`Sources/TapSwitchApp/AppDelegate.swift`:

```swift
import AppKit
import Gesture
import InputSources
import Multitouch
import OSLog
import Preferences

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences()
    private let touchSource: TouchSource = MultitouchDeviceSource()
    private let log = Logger(subsystem: "com.skensell.tapswitch", category: "app")

    private var toggler: LayoutToggler?
    private var recognizer: TapRecognizer?
    private var statusMenu: StatusMenu?
    private var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        toggler = LayoutToggler(provider: TISProvider())
        statusMenu = StatusMenu(preferences: preferences, launchAtLogin: LaunchAtLogin())

        touchSource.onFrame = { [weak self] frame in
            self?.recognizer?.process(frame)
        }
        preferences.onChange = { [weak self] in
            self?.applyPreferences()
        }
        // Contact callbacks stop arriving after sleep; re-attach on wake.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.restartTouchSource()
            }
        }

        applyPreferences()
    }

    private func applyPreferences() {
        let recognizer = TapRecognizer(
            config: TapRecognizerConfig(fingers: preferences.fingers, taps: preferences.taps))
        recognizer.onRecognized = { [weak self] in
            self?.toggler?.toggle()
        }
        self.recognizer = recognizer
        restartTouchSource()
    }

    private func restartTouchSource() {
        touchSource.stop()
        guard preferences.isEnabled else {
            statusMenu?.setStatus(.disabled)
            return
        }
        do {
            try touchSource.start()
            statusMenu?.setStatus(.active)
        } catch {
            log.error("touch source: \(String(describing: error), privacy: .public)")
            statusMenu?.setStatus(.trackpadMissing)
        }
    }
}
```

- [ ] **Step 4: Bootstrap**

Replace `Sources/TapSwitchApp/TapSwitchApp.swift` with:

```swift
import AppKit

@main
struct TapSwitchApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
```

- [ ] **Step 5: Build and run all tests**

Run: `swift build && swift test`
Expected: build succeeds; 25 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/TapSwitchApp
git commit -m "Add menu bar app wiring recognizer, toggler and preferences"
```

---

### Task 10: Bundle scripts, Info.plist, README, smoke test

**Files:**
- Create: `Resources/Info.plist`
- Create: `Scripts/bundle.sh`
- Create: `Scripts/run.sh`
- Create: `Scripts/make-dev-cert.sh`
- Create: `README.md`

- [ ] **Step 1: Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>TapSwitch</string>
    <key>CFBundleIdentifier</key>
    <string>com.skensell.tapswitch</string>
    <key>CFBundleName</key>
    <string>TapSwitch</string>
    <key>CFBundleDisplayName</key>
    <string>TapSwitch</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 2: bundle.sh**

```bash
#!/usr/bin/env bash
# Builds the executable and assembles a signed TapSwitch.app in build/.
# Prints the bundle path on stdout; everything else goes to stderr.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-debug}"
APP="$ROOT/build/TapSwitch.app"

swift build --package-path "$ROOT" -c "$CONFIG" --product tapswitch >&2
BIN_DIR="$(swift build --package-path "$ROOT" -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/tapswitch" "$APP/Contents/MacOS/TapSwitch"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# A stable identity keeps the bundle's designated requirement the same across
# rebuilds, so Login Items keeps pointing at it. Ad-hoc works too.
IDENTITY="$(security find-identity -v -p codesigning \
  | awk -F'"' '$2 == "TapSwitch Dev" { split($1, f, " "); print f[2]; exit }')"
if [ -z "$IDENTITY" ]; then
    echo "warning: no 'TapSwitch Dev' identity found — signing ad-hoc." >&2
    echo "warning: run Scripts/make-dev-cert.sh for a stable signature." >&2
    IDENTITY="-"
fi

codesign --force --sign "$IDENTITY" "$APP" >&2

echo "$APP"
```

- [ ] **Step 3: run.sh**

```bash
#!/usr/bin/env bash
# Rebuilds the bundle, replaces any running instance and launches it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$("$ROOT/Scripts/bundle.sh")"

pkill -x TapSwitch 2>/dev/null || true
open "$APP"
echo "Launched $APP"
```

- [ ] **Step 4: make-dev-cert.sh**

Copy `/Users/skensel/WORKING/AI/notchdeck/Scripts/make-dev-cert.sh` and change
every `NotchDeck Dev` to `TapSwitch Dev`, `notchdeck` (the transit password)
to `tapswitch`, and the comment's "Camera / Calendar / Accessibility" to
"Login Items":

```bash
cp /Users/skensel/WORKING/AI/notchdeck/Scripts/make-dev-cert.sh Scripts/make-dev-cert.sh
sed -i '' -e 's/NotchDeck Dev/TapSwitch Dev/g' -e 's/PASSWORD="notchdeck"/PASSWORD="tapswitch"/' \
    -e 's#re-prompts for Camera / Calendar / Accessibility access#forgets the Login Items registration#' \
    Scripts/make-dev-cert.sh
chmod +x Scripts/*.sh
```

- [ ] **Step 5: README.md**

```markdown
# TapSwitch

Toggle the keyboard layout by tapping the trackpad with five fingers (twice,
by default). A macOS menu bar app, nothing else.

Design: [`docs/superpowers/specs/2026-09-16-tapswitch-design.md`](docs/superpowers/specs/2026-09-16-tapswitch-design.md)

## How it works

Finger contacts come from the private `MultitouchSupport.framework` — the same
source BetterTouchTool and MiddleClick use — so no Accessibility or Input
Monitoring permission is needed. A tap is N fingers down and up within 300 ms
without moving; K taps within 400 ms of each other fire the switch. The switch
selects the previously used layout, exactly like the fn/🌐 key.

## Menu

- **Enabled** — pause without quitting
- **Fingers** — 3, 4 or 5 (default 5)
- **Taps** — 1, 2 or 3 (default 2)
- **Launch at Login**
- **Quit**

## Building

```bash
swift test              # unit tests
Scripts/make-dev-cert.sh  # once: stable signing identity
Scripts/run.sh          # build, bundle and launch build/TapSwitch.app
```

Requires macOS 26 and the Xcode command line tools.
```

- [ ] **Step 6: Smoke test**

Run: `Scripts/run.sh`
Expected: `Launched .../build/TapSwitch.app`; a keyboard icon appears in the menu bar, not dimmed. Double-tap the trackpad with five fingers → the layout indicator in the menu bar flips. Open the menu: Enabled ✓, Fingers ▸ 5 ✓, Taps ▸ 2 ✓, Launch at Login enabled (not checked).

If the icon is dimmed and the menu says "Trackpad not found", read
`log stream --predicate 'subsystem == "com.skensell.tapswitch"'` for the
loader's error.

- [ ] **Step 7: Commit**

```bash
git add Resources Scripts README.md
git commit -m "Add bundle scripts, Info.plist and README"
```
