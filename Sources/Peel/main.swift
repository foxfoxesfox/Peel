import AppKit

// Headless check of the parts that don't need a screen: Peel --selftest
if CommandLine.arguments.dropFirst().first == "--selftest" {
    _ = NSApplication.shared
    exit(SelfTest.run() ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
