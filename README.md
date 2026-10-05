<p align="center">
  <img src="docs/logo.png" width="128" height="128" alt="TapSwitch logo">
</p>

<h1 align="center">TapSwitch</h1>

<p align="center">
  Switch the keyboard layout with a five-finger tap on the trackpad.
</p>

<p align="center">
  <a href="https://github.com/skensell201/tapswitch/releases/latest"><b>Download the latest release</b></a>
</p>

---

TapSwitch is a tiny macOS menu bar app with one job. Tap the trackpad with all
five fingers, twice, and the keyboard layout flips to the one you used before —
exactly like pressing the fn/🌐 key, without taking your hands off the trackpad.

## Features

- **One gesture, one action.** Five fingers, two taps by default; both are
  adjustable.
- **Previous layout, not the next one.** With three or more layouts it toggles
  between the two you actually use, the way fn/🌐 does.
- **No permissions.** No Accessibility, no Input Monitoring, no prompts.
- **Stays out of the way.** No Dock icon, no windows. Reconnects to the trackpad
  after sleep.
- **Launch at Login** from the menu.

## Menu

| Item | What it does |
|---|---|
| **Enabled** | Pause without quitting |
| **Fingers** | 3, 4 or 5 (default 5) |
| **Taps** | 1, 2 or 3 (default 2) |
| **Launch at Login** | Start with the Mac |
| **Quit TapSwitch** | ⌘Q |

The menu bar icon greys out while TapSwitch is paused or no trackpad is found.

## Installing

1. Download `TapSwitch-<version>.dmg` from the
   [latest release](https://github.com/skensell201/tapswitch/releases/latest).
2. Open it and drag **TapSwitch** to **Applications**.
3. Get it past Gatekeeper once (see below), then launch it.

### First launch

The app is signed but **not notarized** — notarization needs a paid Developer
ID, and reading the trackpad relies on a private framework, so the App Store was
never an option either. macOS therefore blocks the first launch with
*"Apple could not verify TapSwitch is free of malware"*.

**Option A — System Settings.** Double-click TapSwitch and dismiss the dialog.
Open **System Settings → Privacy & Security**, scroll to the bottom and click
**Open Anyway** next to the message about TapSwitch. Every launch after that is
an ordinary one.

**Option B — Terminal.** Clear the quarantine flag:

```bash
xattr -d com.apple.quarantine /Applications/TapSwitch.app
```

### Requirements

- macOS 26.0 or later
- A multitouch trackpad, built in or Magic Trackpad

## How it works

Finger contacts come from the private `MultitouchSupport.framework` — the same
source BetterTouchTool and MiddleClick use — which is why no permission is
needed. A tap is N fingers down and up within 300 ms without moving; K taps
within 400 ms of each other fire the switch.

## Documentation

- [Development](docs/DEVELOPMENT.md) — building from source, project layout, releasing
- [Design](docs/design.md)
- [Changelog](CHANGELOG.md)
