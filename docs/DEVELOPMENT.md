# Development

## Requirements

- macOS 26.0 or later
- Swift 6.2+ toolchain (Xcode 26 command line tools)

## First-time setup

Create a local code signing identity, so rebuilt bundles keep the same
designated requirement. Without it every rebuild is signed ad hoc with a new
code hash, and macOS forgets the Login Items registration:

```bash
./Scripts/make-dev-cert.sh
```

macOS asks for your login password once while it trusts the certificate.

## Build and run

```bash
swift test          # unit tests
./Scripts/bundle.sh # build, bundle, sign — prints the .app path
./Scripts/run.sh    # build, bundle, sign, replace any running copy, launch
```

TapSwitch has no Dock icon and no window. Quit it from the menu bar, or with
`pkill -x TapSwitch`.

## Scripts

| Script | Purpose |
|---|---|
| `Scripts/make-dev-cert.sh` | Creates the `TapSwitch Dev` signing identity |
| `Scripts/bundle.sh` | Builds and assembles a signed `build/TapSwitch.app` (`CONFIG=release` for a release build) |
| `Scripts/run.sh` | `bundle.sh`, then relaunches the app |
| `Scripts/make-dmg.sh` | Release build wrapped in `build/TapSwitch-<version>.dmg` |
| `Scripts/make-icon.swift` | Draws `Resources/AppIcon.icns`, `Resources/StatusIcon.pdf` and `docs/logo.png` |

## Project layout

```
Sources/
  Gesture/        touch frames and the tap state machine — Foundation only
  Multitouch/     the only module that touches MultitouchSupport.framework
  InputSources/   Carbon TIS wrapper and the previous-layout toggler
  Preferences/    UserDefaults-backed settings
  TapSwitchApp/   menu bar item, wiring, launch at login
Tests/            Swift Testing suites for Gesture, InputSources, Preferences
Resources/        Info.plist, AppIcon.icns, StatusIcon.pdf
Scripts/          build, bundle, release and icon scripts
docs/             design notes and the README logo
```

The leaf modules never depend on each other; `TapSwitchApp` wires them together.
The rationale is in [design.md](design.md).

## Icon

The mark is drawn in code, not checked in as an opaque image: change the numbers
in `Scripts/make-icon.swift`, run it, and commit the regenerated files with it.

```bash
swift Scripts/make-icon.swift
```

## Releasing

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in
   `Resources/Info.plist`, and add an entry to [CHANGELOG.md](../CHANGELOG.md).
2. `./Scripts/make-dmg.sh` — prints the path of the new `.dmg`.
3. Tag `v<version>` and attach the `.dmg` to a GitHub release.
