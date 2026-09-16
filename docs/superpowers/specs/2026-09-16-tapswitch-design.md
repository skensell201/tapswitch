# TapSwitch — Design

**Date:** 2026-09-16
**Status:** Approved

A macOS menu bar utility that toggles the keyboard layout when the user taps
the trackpad with five fingers (twice, by default). Nothing else.

---

## 1. Goal and scope

- Detect an N-finger tap (N = 3–5, default 5) repeated K times (K = 1–3,
  default 2) on any attached multitouch trackpad, while any application is
  focused.
- On detection, switch the keyboard input source to the previously used one —
  the same behaviour as the system `fn`/🌐 key. With two enabled layouts this
  is a plain toggle; with more, it alternates the last two.
- Live as a menu bar icon with a small menu. No dock icon, no windows.
- No custom feedback on switch: the system's own input-source indicator in the
  menu bar is enough.

Out of scope: cycling through all layouts, a fixed layout pair, HUD or sound
feedback, per-app rules, any gesture other than the tap.

## 2. Touch input: private MultitouchSupport.framework

Global gestures are invisible to `NSEvent` monitors and `CGEventTap` — touch
events are only delivered to the focused app. The public IOKit HID route needs
Input Monitoring permission and undocumented, per-model report parsing.

The chosen source is the private `MultitouchSupport.framework`
(`MTDeviceCreateList`, `MTRegisterContactFrameCallback`, `MTDeviceStart`),
the same one BetterTouchTool and MiddleClick use. It delivers every finger's
contact ~100 times per second with no TCC prompt.

Consequences, accepted:

- No headers; the symbols are loaded with `dlopen`/`dlsym` and declared by
  hand. Apple may break it in a major release. Not App Store material — not a
  goal.
- The private API is confined to one module (`Multitouch`) behind a protocol,
  so a breakage means changing one file, and everything downstream is testable
  with synthetic frames.

## 3. Structure

SwiftPM package, macOS 26, laid out like `notchdeck`:

```
tapswitch/
  Package.swift
  Sources/
    Multitouch/     dlopen of MultitouchSupport → stream of TouchFrame
    Gesture/        TapRecognizer — pure state machine, imports Foundation only
    InputSources/   Carbon TIS wrapper + LayoutToggler
    Preferences/    UserDefaults-backed settings
    TapSwitchApp/   NSStatusItem menu, wiring, launch at login
  Tests/
    GestureTests/  InputSourcesTests/  PreferencesTests/
  Resources/        Info.plist (LSUIElement = true), AppIcon.icns
  Scripts/          bundle.sh, run.sh, make-dev-cert.sh
  docs/superpowers/specs/
```

Module dependencies: `TapSwitchApp` → everything; `Gesture`, `Preferences`,
`Multitouch`, `InputSources` depend on nothing but Foundation/system
frameworks and never on each other.

## 4. Data flow

```
Multitouch ──TouchFrame──▶ TapRecognizer ──.recognized──▶ LayoutToggler ──▶ TISSelectInputSource
```

### 4.1 `Multitouch`

```swift
struct TouchContact { let id: Int; let x: Double; let y: Double }   // normalized 0…1
struct TouchFrame   { let timestamp: TimeInterval; let contacts: [TouchContact] }

protocol TouchSource: AnyObject {
    var onFrame: ((TouchFrame) -> Void)? { get set }
    func start() throws
    func stop()
}
```

`MultitouchDeviceSource` implements it: loads the framework, enumerates all
devices, registers one callback per device, and forwards frames. `start()`
throws `MultitouchError.frameworkUnavailable` or `.noDevices`.

The callback fires on a MultitouchSupport thread; frames are forwarded as-is
and the app hops to the main queue once, after recognition.

### 4.2 `Gesture` — `TapRecognizer`

```swift
struct TapRecognizerConfig {
    var fingers: Int           // 3…5
    var taps: Int              // 1…3
    var maxTapDuration = 0.30  // seconds, touch-down → all lifted
    var maxTapGap      = 0.40  // seconds, lift → next touch-down
    var maxMovement    = 0.05  // normalized distance any finger may travel
}

final class TapRecognizer {
    init(config: TapRecognizerConfig)
    var onRecognized: (() -> Void)?
    func process(_ frame: TouchFrame)
    func reset()
}
```

State machine:

- **idle** — waiting. A frame with contact count == `fingers` starts a
  candidate tap: remember timestamp and each contact's start position.
- **touching** — candidate in progress. Cancel (→ idle, taps counter cleared)
  if: count > `fingers`; elapsed > `maxTapDuration`; any contact moved more
  than `maxMovement` from its start. Complete the tap when count drops below
  `fingers`.
- **between taps** — a tap completed. If `taps` reached → fire
  `onRecognized`, → idle. Otherwise wait for the next candidate; if
  `maxTapGap` passes without one → idle, counter cleared.

Design notes:

- "Lifted" is count < `fingers`, not == 0, so a resting thumb or palm does
  not block recognition. A tap requires the count to *reach* `fingers`, so
  four fingers plus a resting fifth already down counts — acceptable.
- Movement check kills swipes and pinches. Five-finger pinch is Launchpad in
  macOS; a tap is unbound, so nothing else fires.
- No timers: the gap timeout is evaluated on the next frame. If no frame
  arrives (fingers all off), the stale state is discarded when the next
  candidate starts, by comparing timestamps. This keeps the recognizer pure
  and fully testable with synthetic frames.

### 4.3 `InputSources` — `LayoutToggler`

```swift
struct InputSource: Equatable { let id: String; let name: String }

protocol InputSourceProvider {
    func enabledKeyboardLayouts() -> [InputSource]
    func current() -> InputSource?
    func select(_ source: InputSource)
    var onSelectionChanged: (() -> Void)? { get set }
}

final class LayoutToggler {
    init(provider: InputSourceProvider)
    func toggle()
}
```

`TISProvider` implements the protocol over `TISCreateInputSourceList`
(category keyboard, enabled, selectable) / `TISCopyCurrentKeyboardInputSource`
/ `TISSelectInputSource`, and observes
`kTISNotifySelectedKeyboardInputSourceChanged` via
`DistributedNotificationCenter`.

`toggle()`:
1. Read `current`. Target = the remembered previous layout if it is still in
   `enabledKeyboardLayouts()`, else the first enabled layout ≠ current.
2. If there is no target (single layout) → do nothing.
3. `select(target)`, then remember `current` as previous.

Every selection-changed notification updates the remembered previous layout,
so switching with `fn` between taps keeps the history correct.

All TIS calls run on the main thread — called from a background thread,
`TISSelectInputSource` reports success and does nothing.

### 4.4 `Preferences`

```swift
final class Preferences {
    var isEnabled: Bool   // default true
    var fingers: Int      // default 5, clamped 3…5
    var taps: Int         // default 2, clamped 1…3
    var onChange: (() -> Void)?
}
```

Backed by `UserDefaults` (injectable suite for tests). Out-of-range stored
values are clamped on read.

### 4.5 `TapSwitchApp`

- `NSApplication` with activation policy `.accessory`.
- `NSStatusItem` with a keyboard SF Symbol. Menu:
  - **Enabled** (checkmark)
  - **Fingers ▸** 3 / 4 / 5
  - **Taps ▸** 1 / 2 / 3
  - **Launch at Login** (checkmark, `SMAppService.mainApp`)
  - **Quit**
- Wiring: `Preferences.onChange` rebuilds the recognizer with a new config;
  `Enabled` off stops the touch source, on restarts it.
- Recognized gesture → `DispatchQueue.main.async { toggler.toggle() }`.

## 5. Error handling

| Condition | Behaviour |
|---|---|
| Framework fails to load / no trackpad | Status icon dimmed, first menu item reads "Trackpad not found" (disabled). Logged via `os_log`. App keeps running; retried on wake and on Enabled toggle. |
| Machine sleeps | MultitouchSupport callbacks stop after sleep. On `NSWorkspace.didWakeNotification` the source is stopped and restarted. |
| Only one layout enabled | `toggle()` is a no-op. |
| Not running from a bundle | `SMAppService` needs a `.app`; the Launch at Login item is disabled when `Bundle.main.bundleURL` is not an app bundle. |

## 6. Testing

- **GestureTests** (synthetic `TouchFrame` sequences, no timers):
  single tap; double tap; tap too long; extra finger; swipe; pinch; gap too
  long between taps; resting finger present throughout; stale state discarded
  after a long pause; config with fingers=3/taps=1.
- **InputSourcesTests** with a fake `InputSourceProvider`: basic toggle;
  previous layout no longer enabled; single layout; external switch updates
  history.
- **PreferencesTests** on an isolated `UserDefaults` suite: defaults; clamping;
  `onChange` fires.
- **Multitouch** is private API — no unit tests, manual smoke via
  `Scripts/run.sh`.

## 7. Build and packaging

`Scripts/bundle.sh` builds the executable and assembles a signed
`build/TapSwitch.app` (Info.plist with `LSUIElement`, icon), following the
notchdeck script minus the media adapter. `Scripts/make-dev-cert.sh` creates a
`TapSwitch Dev` self-signed identity so the bundle's signature is stable across
rebuilds. `Scripts/run.sh` bundles and launches.
