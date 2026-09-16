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
