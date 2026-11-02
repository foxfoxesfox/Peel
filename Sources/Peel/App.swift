import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let prefs = Prefs.shared
    let library = Library.shared
    lazy var shelf = Shelf(library: library)
    let updater = Updater.shared
    var settingsWindow: NSWindow?
    var welcomeWindow: NSWindow?
    var updateWindow: NSWindow?
    var editors: [Editor] = []
    var pins: [Pin] = []
    var subscriptions: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Peel")
        NSApp.mainMenu = mainMenu()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        shelf.model.onEdit = { [weak self] c in self?.edit(c) }
        shelf.model.onPin = { [weak self] c in self?.pin(c) }

        prefs.$captureShortcut.combineLatest(prefs.$shelfShortcut)
            .sink { [weak self] capture, shelf in self?.registerHotkeys(capture, shelf) }
            .store(in: &subscriptions)

        // Old captures go to the Trash: now, and every few hours while Peel runs.
        library.prune(keepDays: prefs.keepDays)
        let prune = Timer(timeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.library.prune(keepDays: self.prefs.keepDays)
        }
        RunLoop.main.add(prune, forMode: .common)

        // Only the very first launch shows anything; after that Peel just sits in the menu bar.
        if !UserDefaults.standard.bool(forKey: "didOnboard") { showWelcome() }

        let updates = Timer(timeInterval: 6 * 3600, repeats: true) { [weak self] _ in self?.autoCheckForUpdates() }
        RunLoop.main.add(updates, forMode: .common)
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.autoCheckForUpdates() }
    }

    func registerHotkeys(_ capture: Shortcut, _ shelfKey: Shortcut) {
        var taken: Set<UInt32> = []
        if !Hotkeys.register(HotkeyStatus.captureID, capture, { [weak self] in self?.capture(.area) }) { taken.insert(HotkeyStatus.captureID) }
        if !Hotkeys.register(HotkeyStatus.shelfID, shelfKey, { [weak self] in self?.shelf.toggle() }) { taken.insert(HotkeyStatus.shelfID) }
        HotkeyStatus.shared.taken = taken
    }

    // MARK: - Capturing

    func capture(_ mode: CaptureMode) {
        guard Capturer.hasPermission else { return askForPermission() }
        Capturer.run(mode, sound: prefs.playSound) { [weak self] file in
            guard let self, let file else { return } // nil: cancelled with Esc
            do {
                let capture = try self.library.add(file)
                if self.prefs.copyAfterCapture { Library.copyImage(self.library.url(capture)) }
                if self.prefs.showShelfAfterCapture { self.shelf.showBriefly() }
            } catch {
                self.alert("Couldn't keep that capture", error.localizedDescription)
            }
        }
    }

    func askForPermission() {
        let alert = NSAlert()
        alert.messageText = "Peel needs Screen Recording"
        alert.informativeText = "Without it, macOS only lets Peel capture your wallpaper. Turn on Peel in System Settings › Privacy & Security › Screen Recording, then reopen Peel."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { Permission.shared.request() }
    }

    @objc func captureArea() { capture(.area) }
    @objc func captureWindow() { capture(.window) }
    @objc func captureScreen() { capture(.screen) }
    @objc func showShelf() { shelf.show() }

    func edit(_ capture: Capture) {
        guard let editor = Editor(capture: capture, library: library) else {
            return alert("Couldn't open that capture", "The file may have been moved or deleted.")
        }
        editor.onClose = { [weak self, weak editor] in
            self?.editors.removeAll { $0 === editor }
            self?.dropDockIconIfNoWindows()
        }
        editors.append(editor)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        editor.show()
    }

    func pin(_ capture: Capture) {
        guard let pin = Pin(file: library.url(capture)) else { return }
        pin.onClose = { [weak self, weak pin] in self?.pins.removeAll { $0 === pin } }
        pins.append(pin)
    }

    func alert(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - Updates

    func autoCheckForUpdates() {
        let last = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast
        guard prefs.autoUpdate, Date().timeIntervalSince(last) > 20 * 3600, updateWindow?.isVisible != true else { return }
        updater.check() // a newer version shows up as a menu item; no pop-ups
    }

    @objc func checkForUpdatesNow() { showUpdates(check: true) }
    @objc func showUpdateWindow() { showUpdates(check: false) }

    func showUpdates(check: Bool) {
        if check { updater.check() }
        present(&updateWindow, title: "Software Update", UpdateView(onClose: { [weak self] in self?.updateWindow?.close() }))
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func add(_ title: String, _ action: Selector?, symbol: String? = nil, shortcut: Shortcut? = nil) -> NSMenuItem {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: shortcut?.key.lowercased() ?? "")
            item.target = self
            if let shortcut { item.keyEquivalentModifierMask = shortcut.menuFlags }
            if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
            return item
        }
        _ = add("Capture Area", #selector(captureArea), symbol: "rectangle.dashed", shortcut: prefs.captureShortcut)
        _ = add("Capture Window", #selector(captureWindow), symbol: "macwindow")
        _ = add("Capture Full Screen", #selector(captureScreen), symbol: "display")
        if !Capturer.hasPermission {
            _ = add("Allow Screen Recording…", #selector(showSettings), symbol: "exclamationmark.triangle")
        }
        menu.addItem(.separator())
        _ = add("Show Shelf", #selector(showShelf), symbol: "tray.full", shortcut: prefs.shelfShortcut)
        menu.addItem(.separator())
        if let release = updater.release {
            _ = add("Update to Peel \(release.version)…", #selector(showUpdateWindow), symbol: "arrow.down.circle.fill")
        }
        let settings = add("How to Use & Settings…", #selector(showSettings))
        settings.keyEquivalent = ","
        _ = add("Check for Updates…", #selector(checkForUpdatesNow))
        menu.addItem(.separator())
        let quit = add("Quit Peel", #selector(quit))
        quit.keyEquivalent = "q"
    }

    @objc func showSettings() {
        present(&settingsWindow, title: "Peel Settings", SettingsView(onShowWelcome: { [weak self] in self?.showWelcome() }))
    }

    func showWelcome() {
        settingsWindow?.close()
        present(&welcomeWindow, title: "Welcome to Peel", WelcomeView(onFinish: { [weak self] in
            UserDefaults.standard.set(true, forKey: "didOnboard")
            UserDefaults.standard.removeObject(forKey: "tourPage")
            self?.welcomeWindow?.close()
        }))
    }

    /// Opening Peel again (Applications, Spotlight) brings Settings back, in case the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if UserDefaults.standard.bool(forKey: "didOnboard") { showSettings() } else { showWelcome() }
        return true
    }

    /// Back to menu-bar-only once the last Peel window closes.
    func windowWillClose(_ notification: Notification) { dropDockIconIfNoWindows(closing: notification.object as? NSWindow) }

    func dropDockIconIfNoWindows(closing: NSWindow? = nil) {
        DispatchQueue.main.async { // after the closing window is gone
            let open = NSApp.windows.contains { $0 !== closing && $0.isVisible && !($0 is NSPanel) && $0.styleMask.contains(.titled) }
            if !open { NSApp.setActivationPolicy(.accessory) }
        }
    }

    /// Menus shown while a window is open, so ⌘W, ⌘Q, ⌘, and copy/paste in text fields work.
    func mainMenu() -> NSMenu {
        let main = NSMenu()
        let app = NSMenu()
        app.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Peel", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let file = NSMenu(title: "File")
        file.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        for submenu in [app, file, edit] { main.addItem(withTitle: "", action: nil, keyEquivalent: "").submenu = submenu }
        return main
    }

    /// Shows a SwiftUI view in a reusable window, rebuilt each time so its status is fresh.
    func present<V: View>(_ window: inout NSWindow?, title: String, _ view: V) {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.delegate = self
            window = w
        }
        window?.title = title
        window?.contentViewController = NSHostingController(rootView: view)
        window?.center()
        // While a window is open, show a Dock icon and a ⌘-Tab entry so it can't get lost behind other apps.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc func quit() { NSApp.terminate(nil) }
}
