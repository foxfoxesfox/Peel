import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut, e.g. ⌘⇧2. `mods` are Carbon modifier flags (what RegisterEventHotKey takes).
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var mods: UInt32
    var key: String // the key's label, e.g. "2"

    static let capture = Shortcut(keyCode: UInt32(kVK_ANSI_2), mods: UInt32(cmdKey | shiftKey), key: "2")
    static let shelf = Shortcut(keyCode: UInt32(kVK_ANSI_1), mods: UInt32(cmdKey | shiftKey), key: "1")

    var title: String {
        (mods & UInt32(controlKey) != 0 ? "⌃" : "") + (mods & UInt32(optionKey) != 0 ? "⌥" : "")
            + (mods & UInt32(shiftKey) != 0 ? "⇧" : "") + (mods & UInt32(cmdKey) != 0 ? "⌘" : "") + key
    }

    /// The same flags for an NSMenuItem, so the menu shows the shortcut.
    var menuFlags: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if mods & UInt32(cmdKey) != 0 { f.insert(.command) }
        if mods & UInt32(shiftKey) != 0 { f.insert(.shift) }
        if mods & UInt32(optionKey) != 0 { f.insert(.option) }
        if mods & UInt32(controlKey) != 0 { f.insert(.control) }
        return f
    }

    /// From a key press while recording. macOS 15+ ignores global shortcuts that use only ⌥ or ⇧⌥, so ⌘ or ⌃ is required.
    init?(event: NSEvent) {
        let f = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard f.contains(.command) || f.contains(.control),
              let chars = event.charactersIgnoringModifiers?.uppercased(), !chars.isEmpty else { return nil }
        var m = 0
        if f.contains(.command) { m |= cmdKey }
        if f.contains(.shift) { m |= shiftKey }
        if f.contains(.option) { m |= optionKey }
        if f.contains(.control) { m |= controlKey }
        self.init(keyCode: UInt32(event.keyCode), mods: UInt32(m), key: chars == " " ? "Space" : chars)
    }

    init(keyCode: UInt32, mods: UInt32, key: String) {
        self.keyCode = keyCode
        self.mods = mods
        self.key = key
    }
}

enum SaveFormat: String, CaseIterable { case png, jpg }

/// User settings, stored in UserDefaults. (ObservableObject, not @State/@AppStorage macros: those need full Xcode.)
final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    @Published var captureShortcut: Shortcut { didSet { save(captureShortcut, "captureShortcut") } }
    @Published var shelfShortcut: Shortcut { didSet { save(shelfShortcut, "shelfShortcut") } }
    @Published var copyAfterCapture: Bool { didSet { d.set(copyAfterCapture, forKey: "copyAfterCapture") } }
    @Published var showShelfAfterCapture: Bool { didSet { d.set(showShelfAfterCapture, forKey: "showShelfAfterCapture") } }
    @Published var playSound: Bool { didSet { d.set(playSound, forKey: "playSound") } }
    /// How long captures stay on the shelf; 0 = forever.
    @Published var keepDays: Int { didSet { d.set(keepDays, forKey: "keepDays") } }
    @Published var saveFolder: String { didSet { d.set(saveFolder, forKey: "saveFolder") } }
    @Published var saveFormat: SaveFormat { didSet { d.set(saveFormat.rawValue, forKey: "saveFormat") } }
    @Published var autoUpdate: Bool { didSet { d.set(autoUpdate, forKey: "autoUpdate") } }

    static let keepChoices = [(1, "1 day"), (7, "1 week"), (30, "1 month"), (90, "3 months"), (0, "Forever")]

    private init() {
        d.register(defaults: ["copyAfterCapture": true, "showShelfAfterCapture": true, "playSound": true, "keepDays": 30,
                              "saveFolder": NSHomeDirectory() + "/Pictures/Peel", "saveFormat": "png", "autoUpdate": true])
        let load = { (key: String) in UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } }
        captureShortcut = load("captureShortcut") ?? .capture
        shelfShortcut = load("shelfShortcut") ?? .shelf
        copyAfterCapture = d.bool(forKey: "copyAfterCapture")
        showShelfAfterCapture = d.bool(forKey: "showShelfAfterCapture")
        playSound = d.bool(forKey: "playSound")
        keepDays = d.integer(forKey: "keepDays")
        saveFolder = d.string(forKey: "saveFolder")!
        saveFormat = SaveFormat(rawValue: d.string(forKey: "saveFormat") ?? "") ?? .png
        autoUpdate = d.bool(forKey: "autoUpdate")
    }

    private func save(_ shortcut: Shortcut, _ key: String) { d.set(try? JSONEncoder().encode(shortcut), forKey: key) }
}

/// System-wide shortcuts through Carbon's RegisterEventHotKey: works in every app and needs no permission.
enum Hotkeys {
    private static var entries: [UInt32: (shortcut: Shortcut, action: () -> Void)] = [:]
    private static var refs: [UInt32: EventHotKeyRef] = [:]
    private static var installed = false

    /// False if another app already owns this shortcut.
    @discardableResult
    static func register(_ id: UInt32, _ shortcut: Shortcut, _ action: @escaping () -> Void) -> Bool {
        entries[id] = (shortcut, action)
        return activate(id)
    }

    /// While a new shortcut is being typed, so pressing the current one doesn't take a screenshot.
    static func pause() { refs.keys.forEach(deactivate) }
    static func resume() { entries.keys.forEach { activate($0) } }

    @discardableResult
    private static func activate(_ id: UInt32) -> Bool {
        installHandler()
        deactivate(id)
        guard let shortcut = entries[id]?.shortcut else { return false }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.mods, EventHotKeyID(signature: 0x5045_454C, id: id), // "PEEL"
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs[id] = ref
        return true
    }

    private static func deactivate(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
    }

    private static func installHandler() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let action = Hotkeys.entries[hk.id]?.action
            DispatchQueue.main.async { action?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

/// Which shortcuts another app already owns, for Settings to point out.
final class HotkeyStatus: ObservableObject {
    static let shared = HotkeyStatus()
    static let captureID: UInt32 = 1, shelfID: UInt32 = 2
    @Published var taken: Set<UInt32> = []
}
