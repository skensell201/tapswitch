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
