# TapSwitch

Toggle the keyboard layout by tapping the trackpad with five fingers (twice,
by default). A macOS menu bar app, nothing else.

Design: [`docs/superpowers/specs/2026-09-16-tapswitch-design.md`](docs/superpowers/specs/2026-09-16-tapswitch-design.md)

## Installing

Download `TapSwitch-<version>.dmg` from the
[latest release](https://github.com/skensell201/tapswitch/releases/latest), open
it, and drag TapSwitch to Applications.

**The first launch needs a trip through System Settings.** The app is signed but
not notarized — notarization needs a paid Developer ID, and the app's whole
technique is a private framework, so the App Store was never a destination.
macOS 26 shows *"Apple could not verify TapSwitch is free of malware"* and
offers only a Done button.

Double-click TapSwitch once and dismiss that dialog, then open **System Settings
→ Privacy & Security**, scroll to the bottom, and click **Open Anyway** next to
the message about TapSwitch. Confirm, and it launches — once. Every launch after
that is an ordinary one.

If you would rather not visit System Settings, clearing the quarantine flag does
the same job:

```bash
xattr -d com.apple.quarantine /Applications/TapSwitch.app
```

TapSwitch has no Dock icon. It lives in the menu bar as a keyboard symbol, and
that is where its settings and Quit are. No permissions are requested.

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
swift test                # unit tests
Scripts/make-dev-cert.sh  # once: stable signing identity
Scripts/run.sh            # build, bundle and launch build/TapSwitch.app
Scripts/make-dmg.sh       # release build wrapped in build/TapSwitch-<version>.dmg
swift Scripts/make-icon.swift  # redraws Resources/AppIcon.icns
```

Requires macOS 26 and the Xcode command line tools.
