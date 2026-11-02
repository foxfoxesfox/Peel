import AppKit
import SwiftUI

/// Hover, previews and short "Copied" labels for the shelf. (ObservableObject instead of @State: see Prefs.)
final class ShelfModel: ObservableObject {
    @Published var query = ""
    @Published var hovered: String?
    @Published var flash: [String: String] = [:]
    @Published var thumbs: [String: NSImage] = [:]
    var onEdit: (Capture) -> Void = { _ in }
    var onPin: (Capture) -> Void = { _ in }
    var focusSearch: () -> Void = {}

    func say(_ text: String, on capture: Capture) {
        flash[capture.name] = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            if self?.flash[capture.name] == text { self?.flash[capture.name] = nil }
        }
    }

    func loadThumb(_ capture: Capture, from library: Library) {
        guard thumbs[capture.name] == nil else { return }
        let file = library.url(capture)
        DispatchQueue.global(qos: .userInitiated).async {
            let image = Library.thumbnail(file)
            DispatchQueue.main.async { self.thumbs[capture.name] = image ?? NSImage() }
        }
    }
}

/// A floating panel that can take typing (search) without making Peel the active app,
/// so a capture can be dragged straight into whatever you were using.
final class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

final class Shelf {
    let library: Library
    let model = ShelfModel()
    let panel: ShelfPanel
    private var hideTimer: Timer?

    init(library: Library) {
        self.library = library
        panel = ShelfPanel(contentRect: NSRect(x: 0, y: 0, width: 372, height: 500),
                           styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
                           backing: .buffered, defer: true)
        panel.title = "Peel"
        panel.titlebarAppearsTransparent = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 260, height: 260)
        panel.contentView = NSHostingView(rootView: ShelfView(library: library, model: model))
        model.focusSearch = { [weak self] in self?.panel.makeKey() }
    }

    var isVisible: Bool { panel.isVisible }

    /// From the menu or its shortcut: stays until you close it (Esc, or the close button).
    func show() {
        hideTimer?.invalidate()
        place()
        panel.makeKeyAndOrderFront(nil)
    }

    /// After a capture: appears without taking focus, and slips away after a few seconds unless you're using it.
    func showBriefly() {
        let wasVisible = panel.isVisible
        if !wasVisible { place() }
        panel.orderFrontRegardless()
        guard !wasVisible || hideTimer != nil else { return }
        scheduleHide(after: 6)
    }

    func toggle() { panel.isVisible ? panel.orderOut(nil) : show() }

    private func scheduleHide(after seconds: TimeInterval) {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.panel.isKeyWindow || NSMouseInRect(NSEvent.mouseLocation, self.panel.frame, false) || NSEvent.pressedMouseButtons != 0 {
                return self.scheduleHide(after: 2) // in use, or a drag out of it is under way
            }
            self.hideTimer = nil
            self.panel.orderOut(nil)
        }
    }

    /// Top-right of the screen the pointer is on, under the menu bar.
    private func place() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: area.maxX - size.width - 12, y: area.maxY - size.height - 12))
    }
}

struct ShelfView: View {
    @ObservedObject var library: Library
    @ObservedObject var model: ShelfModel
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        let results = library.search(model.query)
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("Search the text in your captures", text: $model.query)
                    .textFieldStyle(.plain)
                    .onTapGesture { model.focusSearch() }
                if !model.query.isEmpty {
                    Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary).accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12).padding(.top, 30).padding(.bottom, 10)
            Divider()
            if library.items.isEmpty {
                empty("camera.viewfinder", "No captures yet",
                      "Press \(prefs.captureShortcut.title) and drag over part of the screen. Press Space to pick a window instead.")
            } else if results.isEmpty {
                empty("text.magnifyingglass", "Nothing found", "No capture contains “\(model.query)”.")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 12) {
                        ForEach(results) { tile($0) }
                    }
                    .padding(12)
                }
            }
            Divider()
            Text("Click to copy · Drag into any app · Double-click to edit")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.vertical, 7)
        }
        .frame(minWidth: 260, minHeight: 260)
    }

    private func empty(_ symbol: String, _ title: String, _ detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 34)).foregroundStyle(.tertiary).accessibilityHidden(true)
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tile(_ c: Capture) -> some View {
        let file = library.url(c)
        let hovering = model.hovered == c.name
        return VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottom) {
                Group {
                    if let thumb = model.thumbs[c.name] {
                        Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Color.secondary.opacity(0.1).onAppear { model.loadThumb(c, from: library) }
                    }
                }
                .frame(maxWidth: .infinity).frame(height: 100)
                .background(Color.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(hovering ? 0.25 : 0.08)))
                if let note = model.flash[c.name] {
                    Text(note).font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(.regularMaterial)).padding(.bottom, 36)
                }
                if hovering { toolbar(c, file) }
            }
            Text(caption(c)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { model.hovered = c.name } else if model.hovered == c.name { model.hovered = nil }
        }
        .onTapGesture(count: 2) { model.onEdit(c) }
        .onTapGesture { copy(c, file) }
        .onDrag { NSItemProvider(contentsOf: file) ?? NSItemProvider() }
        .contextMenu {
            Button("Copy Image") { copy(c, file) }
            Button("Copy Text") { copyText(c) }
            Button("Edit…") { model.onEdit(c) }
            Button("Pin on Screen") { model.onPin(c) }
            Button("Save to \(folderName)") { save(c, file) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
            Divider()
            Button("Move to Trash") { library.remove(c) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Capture from \(caption(c))")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { copy(c, file) }
        .accessibilityAction(named: "Copy Text") { copyText(c) }
        .accessibilityAction(named: "Edit") { model.onEdit(c) }
        .accessibilityAction(named: "Pin on Screen") { model.onPin(c) }
        .accessibilityAction(named: "Save") { save(c, file) }
        .accessibilityAction(named: "Move to Trash") { library.remove(c) }
    }

    private func toolbar(_ c: Capture, _ file: URL) -> some View {
        HStack(spacing: 2) {
            icon("doc.on.doc", "Copy image") { copy(c, file) }
            icon("text.viewfinder", "Copy text") { copyText(c) }
            icon("pin", "Pin on screen") { model.onPin(c) }
            icon("pencil.tip", "Edit") { model.onEdit(c) }
            icon("square.and.arrow.down", "Save to \(folderName)") { save(c, file) }
            icon("trash", "Move to Trash") { library.remove(c) }
        }
        .padding(3)
        .background(Capsule().fill(.regularMaterial))
        .padding(.bottom, 6)
    }

    private func icon(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 20, height: 18) }
            .buttonStyle(.borderless)
            .help(help)
            .accessibilityLabel(help)
    }

    private var folderName: String { (prefs.saveFolder as NSString).lastPathComponent }

    /// The date, or while searching, the line of text that matched.
    private func caption(_ c: Capture) -> String {
        let words = model.query.lowercased().split(separator: " ")
        if let first = words.first, let line = c.text?.split(separator: "\n").first(where: { $0.lowercased().contains(first) }) {
            return String(line)
        }
        return c.date.formatted(date: .abbreviated, time: .shortened)
    }

    private func copy(_ c: Capture, _ file: URL) {
        Library.copyImage(file)
        model.say("Copied", on: c)
    }

    private func copyText(_ c: Capture) {
        guard let text = c.text else { return model.say("Still reading…", on: c) }
        guard !text.isEmpty else { return model.say("No text found", on: c) }
        Library.copyText(text)
        model.say("Text copied", on: c)
    }

    private func save(_ c: Capture, _ file: URL) {
        do {
            let out = try Library.export(file, to: URL(fileURLWithPath: prefs.saveFolder), format: prefs.saveFormat)
            model.say("Saved as \(out.pathExtension.uppercased())", on: c)
        } catch {
            model.say("Couldn't save", on: c)
            NSAlert(error: error).runModal()
        }
    }
}

/// A capture floating above every window, for keeping a reference in view. Esc or the close button removes it.
final class Pin: NSObject, NSWindowDelegate {
    let panel: NSPanel
    var onClose: () -> Void = {}

    init?(file: URL) {
        guard let image = NSImage(contentsOf: file), let rep = image.representations.first else { return nil }
        // Screenshots are at Retina pixel size; show them at the size they had on screen, at most 70% of it.
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        var size = NSSize(width: CGFloat(rep.pixelsWide) / scale, height: CGFloat(rep.pixelsHigh) / scale)
        if let screen = NSScreen.main?.visibleFrame.size {
            let fit = min(1, screen.width * 0.7 / size.width, screen.height * 0.7 / size.height)
            size = NSSize(width: size.width * fit, height: size.height * fit)
        }
        panel = PinPanel(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        super.init()
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentAspectRatio = size
        panel.hasShadow = true
        let view = NSImageView(image: image)
        view.imageScaling = .scaleProportionallyUpOrDown
        view.setAccessibilityLabel("Pinned capture")
        panel.contentView = view
        panel.delegate = self
        panel.center()
        panel.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) { onClose() }
}

private final class PinPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { close() }
}
