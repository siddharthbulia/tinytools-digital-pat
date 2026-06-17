import AppKit

@main
@MainActor
struct DigitalPatApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // .accessory = no Dock icon, no app menu, but can show floating windows.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
