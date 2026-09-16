import AppKit

@main
struct TapSwitchApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
