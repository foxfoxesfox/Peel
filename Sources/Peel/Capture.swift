import AppKit

enum CaptureMode { case area, window, screen }

/// Taking the picture is left to Apple's own `screencapture` tool: its selection, window highlight, Space to switch
/// modes and Esc to cancel are exactly the native ones, and nothing of it has to be rebuilt here.
enum Capturer {
    private static var busy = false

    /// Screen Recording permission (System Settings > Privacy & Security). Without it macOS only captures the wallpaper.
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Adds Peel to the Screen Recording list (asking once), then opens that page.
    static func requestPermission() {
        if !CGRequestScreenCaptureAccess() { openPermissionSettings() }
    }

    static func openPermissionSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    /// Calls back on the main thread with a new PNG in the temporary folder, or nil when cancelled (Esc).
    static func run(_ mode: CaptureMode, sound: Bool, completion: @escaping (URL?) -> Void) {
        guard !busy else { return }
        busy = true
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("peel-\(UUID().uuidString).png")
        var args: [String]
        switch mode {
        case .area: args = ["-i"]
        case .window: args = ["-i", "-W"]
        case .screen:
            // shortcut: assumes screencapture's -D order matches NSScreen.screens (main display first); fine for 1–2 displays.
            let mouse = NSEvent.mouseLocation
            let index = NSScreen.screens.firstIndex { NSMouseInRect(mouse, $0.frame, false) } ?? 0
            args = ["-D", String(index + 1)]
        }
        if !sound { args.append("-x") }
        args.append(file.path)
        // A short pause so the menu we were picked from has faded out of the picture.
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + (mode == .screen ? 0.25 : 0.05)) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = args
            try? p.run()
            p.waitUntilExit()
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            DispatchQueue.main.async {
                busy = false
                completion(size > 0 ? file : nil)
            }
        }
    }
}
