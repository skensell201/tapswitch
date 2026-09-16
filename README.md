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
swift test                # unit tests
Scripts/make-dev-cert.sh  # once: stable signing identity
Scripts/run.sh            # build, bundle and launch build/TapSwitch.app
```

Requires macOS 26 and the Xcode command line tools.
