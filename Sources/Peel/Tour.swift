import ServiceManagement
import SwiftUI

// Views use ObservableObject models rather than @State: the @State macro needs full Xcode to compile.

final class LoginItem: ObservableObject {
    @Published var status = SMAppService.mainApp.status
    @Published var error: String?

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch {
            self.error = "Couldn't change Launch at Login: \(error.localizedDescription)"
        }
        status = SMAppService.mainApp.status
    }
}

/// Live Screen Recording status while a Peel window shows it.
final class Permission: ObservableObject {
    static let shared = Permission()
    @Published var allowed = Capturer.hasPermission
    @Published var asked = false
    private var timer: Timer?

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            let now = Capturer.hasPermission
            if self?.allowed != now { self?.allowed = now }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    func request() {
        asked = true
        Capturer.requestPermission()
    }

    /// macOS often only applies the permission to a fresh copy of the app.
    static func relaunch() {
        let path = Bundle.main.bundlePath.replacingOccurrences(of: "'", with: "'\\''")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; open '\(path)'"]
        try? p.run()
        NSApp.terminate(nil)
    }
}

final class Pager: ObservableObject {
    @Published var page = UserDefaults.standard.integer(forKey: "tourPage") {
        didSet { UserDefaults.standard.set(page, forKey: "tourPage") } // so Quit & Reopen comes back to the same page
    }
}

// MARK: - First-launch welcome (5 pages)

struct WelcomeView: View {
    let onFinish: () -> Void
    @ObservedObject var pager = Pager()
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var login = LoginItem()
    @ObservedObject var permission = Permission.shared
    private let pageCount = 5

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch pager.page {
                case 0: welcomePage
                case 1: permissionPage
                case 2: shortcutsPage
                case 3: howToPage
                default: settingsPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Divider()
            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<pageCount, id: \.self) { i in
                        Circle()
                            .fill(i == pager.page ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("Step \(pager.page + 1) of \(pageCount)")
                Spacer()
                if pager.page > 0 {
                    Button("Back") { pager.page -= 1 }
                }
                Button(pager.page == pageCount - 1 ? "Start Using Peel" : "Continue") {
                    if pager.page == pageCount - 1 { onFinish() } else { pager.page += 1 }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 540, height: 660)
        .onAppear { permission.start() }
        .onDisappear { permission.stop() }
    }

    private var welcomePage: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
                .padding(.top, 28)
            VStack(spacing: 6) {
                Text("Welcome to Peel").font(.largeTitle.bold())
                Text("Screenshots that are easy to take, mark up and find again.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 16) {
                feature("keyboard", "One shortcut", "Press \(prefs.captureShortcut.title) and drag. No more remembering which number does what.")
                feature("tray.full", "A shelf for your captures", "Copy, drag into any app, pin on screen, or save. They wait there until you need them.")
                feature("pencil.tip.crop.circle", "Mark up in seconds", "Arrows, boxes, highlights, text, redaction and crop.")
                feature("text.magnifyingglass", "Find it by what's in it", "Search for any word you saw in a screenshot.")
                feature("lock.shield", "Private", "Captures and their text stay on your Mac. Nothing is uploaded.")
            }
            .padding(.horizontal, 48)
            .padding(.top, 8)
        }
    }

    private var permissionPage: some View {
        page("Let Peel see your screen", "macOS asks every screenshot app for this once. Peel only looks when you take a capture.") {
            Section { PermissionRows(permission: permission) }
        }
    }

    private var shortcutsPage: some View {
        page("Your shortcuts", "Pick keys that are easy for you. They work in every app.") {
            Section { ShortcutRows(prefs: prefs) }
            Section("Taking a capture") {
                Flow(steps: [.key(prefs.captureShortcut.title, "Press \(prefs.captureShortcut.title)"),
                             .icon("rectangle.dashed", "Drag over an area, or press Space for a window"),
                             .icon("tray.full", "It's copied and on the shelf")])
            }
        }
    }

    private var howToPage: some View {
        page("How to use Peel", "Everything happens from the shelf. You can see this again in Settings.") {
            Section { HowTo(prefs: prefs) }
        }
    }

    private var settingsPage: some View {
        page("A few more settings", "That's it. Peel is in your menu bar whenever you need it.") {
            Section("After a capture") { AfterCaptureRows(prefs: prefs) }
            Section("Captures") { LibraryRows(prefs: prefs) }
            Section("General") { GeneralRows(login: login) }
        }
    }

    private func page<Content: View>(_ title: String, _ subtitle: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.title.bold())
                Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            Form { content() }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
        }
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Settings window

struct SettingsView: View {
    let onShowWelcome: () -> Void
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var login = LoginItem()
    @ObservedObject var permission = Permission.shared

    var body: some View {
        Form {
            Section("How to use") { HowTo(prefs: prefs) }
            Section("Screen Recording") { PermissionRows(permission: permission) }
            Section("Shortcuts") { ShortcutRows(prefs: prefs) }
            Section("After a capture") { AfterCaptureRows(prefs: prefs) }
            Section("Captures") { LibraryRows(prefs: prefs) }
            Section("General") {
                GeneralRows(login: login)
                HStack {
                    Text("Welcome tour")
                    Spacer()
                    Button("Show Again", action: onShowWelcome)
                }
                LabeledContent("Version", value: Updater.currentVersion)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 720)
        .onAppear { permission.start() }
        .onDisappear { permission.stop() }
    }
}

// MARK: - Shared rows

struct HowTo: View {
    @ObservedObject var prefs: Prefs

    var body: some View {
        step("keyboard", "Capture: press \(prefs.captureShortcut.title)",
             "Drag over part of the screen. Press Space to pick a window instead, or Esc to cancel. The menu bar icon also captures a window or the whole screen.")
        step("tray.full", "Use it from the shelf",
             "Each capture is copied and lands on the shelf. Click one to copy it again, or drag it into any app or folder.")
        step("pencil.tip.crop.circle", "Mark it up",
             "Double-click a capture for arrows, boxes, highlights, text, redaction and crop. Done adds an edited copy; the original stays.")
        step("text.viewfinder", "Copy its text",
             "Hover a capture and click the text button to copy the words in it.")
        step("pin", "Pin it on screen",
             "Keeps a capture floating above your windows while you work. Esc closes it.")
        step("text.magnifyingglass", "Find it later: press \(prefs.shelfShortcut.title)",
             "Opens the shelf. Type any word you remember seeing in the screenshot.")
    }

    private func step(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}

struct PermissionRows: View {
    @ObservedObject var permission: Permission

    var body: some View {
        if permission.allowed {
            Label("Allowed. Peel is ready to capture.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
            Label("Not allowed yet. Without it, captures only show your wallpaper.", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Turn on Peel in System Settings › Privacy & Security › Screen Recording.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Allow…") { permission.request() }.buttonStyle(.borderedProminent)
            }
            if permission.asked {
                HStack {
                    Text("Turned it on? macOS needs Peel to restart before it counts.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Quit & Reopen") { Permission.relaunch() }
                }
            }
        }
    }
}

struct ShortcutRows: View {
    @ObservedObject var prefs: Prefs
    @ObservedObject var status = HotkeyStatus.shared

    var body: some View {
        ShortcutRecorder(title: "Capture an area or window", shortcut: $prefs.captureShortcut, fallback: .capture,
                         taken: status.taken.contains(HotkeyStatus.captureID))
        ShortcutRecorder(title: "Open the shelf and search", shortcut: $prefs.shelfShortcut, fallback: .shelf,
                         taken: status.taken.contains(HotkeyStatus.shelfID))
    }
}

/// Click, then press the new keys. Esc cancels. One shared recorder, so a redrawn Settings window can't lose it
/// halfway (that would leave the global shortcuts paused).
final class Recorder: ObservableObject {
    static let shared = Recorder()
    @Published var active: String? // title of the shortcut being recorded
    @Published var hint: String?
    private var monitor: Any?

    func start(_ id: String, _ set: @escaping (Shortcut) -> Void) {
        if active != nil { stop() }
        active = id
        hint = nil
        Hotkeys.pause()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { self.stop(); return nil } // Esc
            guard let shortcut = Shortcut(event: event) else {
                self.hint = "Include ⌘ or ⌃, e.g. ⌘⇧2."
                return nil
            }
            set(shortcut)
            self.stop()
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        active = nil
        Hotkeys.resume()
    }
}

struct ShortcutRecorder: View {
    let title: String
    @Binding var shortcut: Shortcut
    let fallback: Shortcut
    let taken: Bool
    @ObservedObject var recorder = Recorder.shared
    private var recording: Bool { recorder.active == title }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                if shortcut != fallback && !recording {
                    Button("Reset") { shortcut = fallback }.buttonStyle(.borderless)
                }
                Button(recording ? "Type a shortcut…" : shortcut.title) {
                    recording ? recorder.stop() : recorder.start(title) { shortcut = $0 }
                }
                .frame(minWidth: 120)
                .accessibilityLabel("\(title): \(shortcut.title). Click to change.")
            }
            if let hint = recorder.hint, recording {
                Text(hint).font(.callout).foregroundStyle(.orange)
            } else if taken {
                Text("Another app already uses \(shortcut.title). Pick different keys.").font(.callout).foregroundStyle(.orange)
            }
        }
    }
}

struct AfterCaptureRows: View {
    @ObservedObject var prefs: Prefs

    var body: some View {
        Toggle("Copy it to the clipboard", isOn: $prefs.copyAfterCapture)
        Toggle("Show the shelf for a few seconds", isOn: $prefs.showShelfAfterCapture)
        Toggle("Play the camera sound", isOn: $prefs.playSound)
    }
}

struct LibraryRows: View {
    @ObservedObject var prefs: Prefs

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Keep captures on the shelf for", selection: $prefs.keepDays) {
                ForEach(Prefs.keepChoices, id: \.0) { Text($0.1).tag($0.0) }
            }
            Text("Older ones go to the Trash, so you can still get them back for a while. Saved copies are never touched.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        HStack {
            Text("Save to")
            Spacer()
            Text((prefs.saveFolder as NSString).abbreviatingWithTildeInPath).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
            Button("Choose…") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.canCreateDirectories = true
                panel.prompt = "Choose"
                panel.message = "Where Save puts copies of your captures."
                NSApp.activate(ignoringOtherApps: true)
                if panel.runModal() == .OK, let url = panel.url { prefs.saveFolder = url.path }
            }
        }
        Picker("Save as", selection: $prefs.saveFormat) {
            Text("PNG (sharpest)").tag(SaveFormat.png)
            Text("JPG (smaller)").tag(SaveFormat.jpg)
        }
        HStack {
            Text("All captures")
            Spacer()
            Button("Show in Finder") { NSWorkspace.shared.open(Library.shared.dir) }
        }
    }
}

struct GeneralRows: View {
    @ObservedObject var login: LoginItem
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        Toggle("Launch at Login", isOn: Binding(
            get: { login.status == .enabled || login.status == .requiresApproval },
            set: login.set))
        if login.status == .requiresApproval {
            HStack {
                Text("Allow Peel in Login Items to finish turning this on.").foregroundStyle(.secondary)
                Spacer()
                Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
            }
        }
        if let error = login.error {
            Text(error).foregroundStyle(.red)
        }
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle("Check for updates automatically", isOn: $prefs.autoUpdate)
                Spacer()
                Button("Check Now") { (NSApp.delegate as? AppDelegate)?.showUpdates(check: true) }
            }
            Text("Once a day Peel asks GitHub if there's a newer version, then lets you install it with one click. Nothing about you or your captures is sent.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A row of pictures showing the steps, e.g. ⌘⇧2 → area → shelf.
struct Flow: View {
    enum Step {
        case icon(String, String)
        case key(String, String)
    }
    let steps: [Step]

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(steps.indices, id: \.self) { i in
                if i > 0 {
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary).padding(.top, 20).accessibilityHidden(true)
                }
                VStack(spacing: 8) {
                    switch steps[i] {
                    case .icon(let symbol, _):
                        Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(Color.accentColor)
                            .frame(width: 56, height: 56).accessibilityHidden(true)
                    case .key(let glyph, _):
                        Text(glyph).font(.system(size: 18, weight: .medium))
                            .frame(minWidth: 56, minHeight: 56)
                            .padding(.horizontal, 4)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor)))
                            .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                            .accessibilityHidden(true)
                    }
                    Text(caption(steps[i])).font(.callout).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 118)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private func caption(_ step: Step) -> String {
        switch step { case .icon(_, let c), .key(_, let c): return c }
    }
}

// MARK: - Updates

struct UpdateView: View {
    @ObservedObject var updater = Updater.shared
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title3.bold())
                    Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let release = updater.release, !release.notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What's new").font(.headline)
                    ScrollView {
                        Text(notes(release.notes)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    }
                    .frame(height: 200)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
                }
            }
            status
            HStack {
                if case .failed = updater.state, let page = Updater.homepage {
                    Link("Open GitHub page", destination: page)
                }
                Spacer()
                buttons
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private var title: String {
        switch updater.state {
        case .checking: return "Checking for updates…"
        case .upToDate: return "Peel is up to date"
        case .failed where updater.release == nil: return "Couldn't check for updates"
        default: return updater.release.map { "Peel \($0.version) is available" } ?? "Updates"
        }
    }

    private var subtitle: String {
        switch updater.state {
        case .upToDate: return "You have the latest version, \(Updater.currentVersion)."
        case .checking: return "Asking GitHub for the latest version."
        default:
            if updater.release == nil { return "Check your internet connection and try again." }
            return "You have \(Updater.currentVersion). Updating takes a few seconds and keeps your settings."
        }
    }

    @ViewBuilder private var status: some View {
        switch updater.state {
        case .downloading(let fraction):
            ProgressView(value: fraction) { Text("Downloading… \(Int(fraction * 100))%") }
        case .installing:
            ProgressView { Text("Installing. Peel will reopen in a moment.") }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var buttons: some View {
        switch updater.state {
        case .available:
            Button("Later", action: onClose).keyboardShortcut(.cancelAction)
            Button("Install and Relaunch") { updater.install() }.keyboardShortcut(.defaultAction)
        case .failed:
            Button("Close", action: onClose).keyboardShortcut(.cancelAction)
            Button("Try Again") { updater.release == nil ? updater.check() : updater.install() }.keyboardShortcut(.defaultAction)
        case .downloading, .installing, .checking:
            Button("Close", action: onClose).disabled(updater.state == .installing)
        default:
            Button("OK", action: onClose).keyboardShortcut(.defaultAction)
        }
    }

    /// CHANGELOG markdown: headings in bold, bullets as •, bold/links inline, line breaks kept.
    private func notes(_ text: String) -> AttributedString {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            if line.hasPrefix("### ") { return "**\(line.dropFirst(4))**" }
            if line.hasPrefix("  - ") { return "    ◦ " + line.dropFirst(4) }
            if line.hasPrefix("- ") { return "• " + line.dropFirst(2) }
            return String(line)
        }
        let cleaned = lines.joined(separator: "\n")
        return (try? AttributedString(markdown: cleaned, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(cleaned)
    }
}

