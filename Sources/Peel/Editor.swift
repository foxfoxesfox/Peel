import AppKit

enum Tool: Int, CaseIterable {
    case arrow, box, highlight, text, redact, crop

    var title: String { ["Arrow", "Box", "Highlight", "Text", "Redact", "Crop"][rawValue] }
    var key: String { ["a", "r", "h", "t", "b", "c"][rawValue] }
    var symbol: String {
        ["arrow.up.right", "rectangle", "highlighter", "textformat", "rectangle.fill", "crop"][rawValue]
    }
}

/// One annotation, in image pixels (origin bottom-left). Undo removes the last one; only the last crop counts.
struct Mark {
    var tool: Tool
    var a: CGPoint
    var b: CGPoint
    var color: CGColor
    var text = ""
    var rect: CGRect { CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)) }
}

/// Draws the screenshot and its marks, and turns drags into marks.
final class Canvas: NSView, NSTextFieldDelegate {
    let image: CGImage
    var marks: [Mark] = [] { didSet { needsDisplay = true } }
    var tool = Tool.arrow { didSet { onToolChange(tool) } }
    var color = NSColor.systemRed
    var onToolChange: (Tool) -> Void = { _ in }
    var onDone: () -> Void = {}
    private var live: Mark?
    private var field: NSTextField?
    private var fieldPoint = CGPoint.zero

    init(image: CGImage) {
        self.image = image
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    var size: CGSize { CGSize(width: image.width, height: image.height) }
    var lineWidth: CGFloat { Self.lineWidth(for: size) }
    static func lineWidth(for size: CGSize) -> CGFloat { max(3, max(size.width, size.height) / 280) }

    /// Where the image sits in the view: centred, never larger than it was on screen.
    var fit: CGRect {
        let r = bounds.insetBy(dx: 16, dy: 16)
        let s = min(r.width / size.width, r.height / size.height, 1 / (window?.backingScaleFactor ?? 2))
        let w = size.width * s, h = size.height * s
        return CGRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h)
    }
    private var scale: CGFloat { fit.width / size.width }

    private func toImage(_ p: NSPoint) -> CGPoint {
        CGPoint(x: min(max((p.x - fit.minX) / scale, 0), size.width), y: min(max((p.y - fit.minY) / scale, 0), size.height))
    }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.translateBy(x: fit.minX, y: fit.minY)
        ctx.scaleBy(x: scale, y: scale)
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        Self.draw(marks + (live.map { [$0] } ?? []), in: ctx, size: size, preview: true)
        ctx.restoreGState()
    }

    /// Shared by the screen and the export, so what you see is what you get.
    static func draw(_ marks: [Mark], in ctx: CGContext, size: CGSize, preview: Bool) {
        let lw = lineWidth(for: size)
        for m in marks {
            ctx.saveGState()
            switch m.tool {
            case .arrow:
                let angle = atan2(m.b.y - m.a.y, m.b.x - m.a.x), head = lw * 4.5, spread = CGFloat.pi / 7
                let base = CGPoint(x: m.b.x - cos(angle) * head * 0.8, y: m.b.y - sin(angle) * head * 0.8)
                ctx.setStrokeColor(m.color); ctx.setFillColor(m.color)
                ctx.setLineWidth(lw); ctx.setLineCap(.round)
                ctx.move(to: m.a); ctx.addLine(to: base); ctx.strokePath()
                ctx.move(to: m.b)
                ctx.addLine(to: CGPoint(x: m.b.x - cos(angle - spread) * head, y: m.b.y - sin(angle - spread) * head))
                ctx.addLine(to: CGPoint(x: m.b.x - cos(angle + spread) * head, y: m.b.y - sin(angle + spread) * head))
                ctx.closePath(); ctx.fillPath()
            case .box:
                ctx.setStrokeColor(m.color); ctx.setLineWidth(lw)
                ctx.addPath(CGPath(roundedRect: m.rect, cornerWidth: min(lw, m.rect.width / 2), cornerHeight: min(lw, m.rect.height / 2), transform: nil))
                ctx.strokePath()
            case .highlight:
                ctx.setBlendMode(.multiply)
                ctx.setFillColor(NSColor.systemYellow.withAlphaComponent(0.5).cgColor)
                ctx.fill(m.rect)
            case .redact:
                // Solid and flattened into the exported pixels: nothing underneath survives (unlike blur or pixelation).
                ctx.setFillColor(.black)
                ctx.fill(m.rect)
            case .text:
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                NSAttributedString(string: m.text, attributes: textAttributes(color: m.color, size: size)).draw(at: m.a)
                NSGraphicsContext.restoreGraphicsState()
            case .crop:
                break // drawn below, once
            }
            ctx.restoreGState()
        }
        if preview, let crop = marks.last(where: { $0.tool == .crop })?.rect {
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.5))
            ctx.addRect(CGRect(origin: .zero, size: size)); ctx.addRect(crop)
            ctx.fillPath(using: .evenOdd)
            ctx.setStrokeColor(.white); ctx.setLineWidth(lw / 2); ctx.setLineDash(phase: 0, lengths: [lw * 2, lw * 2])
            ctx.stroke(crop)
        }
    }

    static func textAttributes(color: CGColor, size: CGSize) -> [NSAttributedString.Key: Any] {
        // A white outline keeps the text readable on dark and light screenshots alike.
        [.font: NSFont.systemFont(ofSize: lineWidth(for: size) * 6, weight: .bold),
         .foregroundColor: NSColor(cgColor: color) ?? .systemRed, .strokeColor: NSColor.white, .strokeWidth: -2.5]
    }

    /// The flattened result at full resolution, cropped.
    static func render(_ image: CGImage, _ marks: [Mark]) -> CGImage? {
        let size = CGSize(width: image.width, height: image.height)
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        draw(marks, in: ctx, size: size, preview: false)
        guard let flat = ctx.makeImage() else { return nil }
        guard let crop = marks.last(where: { $0.tool == .crop })?.rect.integral else { return flat }
        // CGImage cropping counts from the top; marks count from the bottom.
        return flat.cropping(to: CGRect(x: crop.minX, y: size.height - crop.maxY, width: crop.width, height: crop.height))
    }

    // MARK: - Input

    override func mouseDown(with event: NSEvent) {
        commitText()
        let p = convert(event.locationInWindow, from: nil)
        if tool == .text { return startText(at: p) }
        let ip = toImage(p)
        live = Mark(tool: tool, a: ip, b: ip, color: color.cgColor)
    }

    override func mouseDragged(with event: NSEvent) {
        live?.b = toImage(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let m = live else { return }
        live = nil
        let tiny = m.tool == .arrow ? hypot(m.a.x - m.b.x, m.a.y - m.b.y) < lineWidth * 2 : m.rect.width < 4 || m.rect.height < 4
        if !tiny { marks.append(m) } else { needsDisplay = true }
    }

    override func keyDown(with event: NSEvent) {
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if event.modifierFlags.intersection([.command, .control, .option]).isEmpty, let t = Tool.allCases.first(where: { $0.key == key }) {
            tool = t
        } else if event.keyCode == 36 || event.keyCode == 76 { // Return, Enter
            onDone()
        } else if event.keyCode == 51 && !marks.isEmpty { // Delete
            marks.removeLast()
        } else {
            super.keyDown(with: event)
        }
    }

    private func startText(at p: NSPoint) {
        let fontSize = lineWidth * 6 * scale
        let f = NSTextField(frame: NSRect(x: p.x, y: p.y - fontSize * 0.7, width: max(160, bounds.maxX - p.x - 16), height: fontSize * 1.4))
        f.font = .systemFont(ofSize: fontSize, weight: .bold)
        f.textColor = color
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.placeholderString = "Type, then press Return"
        f.delegate = self
        f.target = self
        f.action = #selector(textReturn)
        addSubview(f)
        window?.makeFirstResponder(f)
        field = f
        fieldPoint = toImage(NSPoint(x: p.x + 2, y: f.frame.minY + fontSize * 0.2))
    }

    @objc private func textReturn() { commitText() }
    func controlTextDidEndEditing(_ obj: Notification) { commitText() }

    func commitText() {
        guard let f = field else { return }
        field = nil
        let text = f.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        f.removeFromSuperview()
        if !text.isEmpty { marks.append(Mark(tool: .text, a: fieldPoint, b: fieldPoint, color: (f.textColor ?? color).cgColor, text: text)) }
        window?.makeFirstResponder(self)
    }
}

/// The edit window: tools along the top, the screenshot below. Done adds an edited copy to the shelf; the original stays.
final class Editor: NSObject, NSWindowDelegate {
    let window: NSWindow
    let canvas: Canvas
    let capture: Capture
    let library: Library
    var onClose: () -> Void = {}
    private let tools = NSSegmentedControl()
    private static let palette: [(NSColor, String)] = [(.systemRed, "Red"), (.systemYellow, "Yellow"), (.systemGreen, "Green"),
                                                       (.systemBlue, "Blue"), (.black, "Black"), (.white, "White")]
    private var finished = false

    init?(capture: Capture, library: Library) {
        guard let image = Library.cgImage(library.url(capture)) else { return nil }
        self.capture = capture
        self.library = library
        canvas = Canvas(image: image)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let screen = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        let size = NSSize(width: min(max(CGFloat(image.width) / scale + 32, 560), screen.width * 0.85),
                          height: min(max(CGFloat(image.height) / scale + 32, 320), screen.height * 0.85 - 52))
        window = NSWindow(contentRect: NSRect(origin: .zero, size: NSSize(width: size.width, height: size.height + 52)),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Edit \(capture.name)"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 560, height: 360)

        tools.segmentCount = Tool.allCases.count
        tools.trackingMode = .selectOne
        for t in Tool.allCases {
            tools.setImage(NSImage(systemSymbolName: t.symbol, accessibilityDescription: t.title), forSegment: t.rawValue)
            tools.setToolTip("\(t.title) (\(t.key.uppercased()))", forSegment: t.rawValue)
            tools.setWidth(36, forSegment: t.rawValue)
        }
        tools.selectedSegment = 0
        tools.target = self
        tools.action = #selector(pickTool)
        tools.setAccessibilityLabel("Tool")
        canvas.onToolChange = { [weak self] t in self?.tools.selectedSegment = t.rawValue }
        canvas.onDone = { [weak self] in self?.done() }

        let colors = NSSegmentedControl()
        colors.segmentCount = Self.palette.count
        for (i, (c, name)) in Self.palette.enumerated() {
            colors.setImage(Self.swatch(c), forSegment: i)
            colors.setToolTip(name, forSegment: i)
            colors.setWidth(26, forSegment: i)
        }
        colors.selectedSegment = 0
        colors.setAccessibilityLabel("Colour")
        colors.target = self
        colors.action = #selector(pickColor(_:))

        let undo = NSButton(title: "Undo", target: self, action: #selector(undoMark))
        undo.keyEquivalent = "z"
        undo.keyEquivalentModifierMask = .command
        let copy = NSButton(title: "Copy", target: self, action: #selector(copyResult))
        let doneButton = NSButton(title: "Done", target: self, action: #selector(done))
        doneButton.bezelColor = .controlAccentColor
        doneButton.toolTip = "Add the edited copy to the shelf and copy it (Return)"

        let bar = NSStackView(views: [tools, colors, NSView(), undo, copy, doneButton])
        bar.orientation = .horizontal
        bar.spacing = 10
        bar.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        bar.setHuggingPriority(.defaultLow, for: .horizontal)

        let root = NSStackView(views: [bar, canvas])
        root.orientation = .vertical
        root.spacing = 0
        root.alignment = .leading
        bar.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        canvas.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        window.contentView = root
        window.center()
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
    }

    private static func swatch(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 14, height: 14), flipped: false) { r in
            let p = NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1))
            color.setFill(); p.fill()
            NSColor.separatorColor.setStroke(); p.stroke()
            return true
        }
    }

    @objc private func pickTool() {
        canvas.commitText()
        canvas.tool = Tool(rawValue: tools.selectedSegment) ?? .arrow
        window.makeFirstResponder(canvas)
    }

    @objc private func pickColor(_ sender: NSSegmentedControl) {
        canvas.color = Self.palette[sender.selectedSegment].0
        window.makeFirstResponder(canvas)
    }

    @objc private func undoMark() {
        canvas.commitText()
        if !canvas.marks.isEmpty { canvas.marks.removeLast() }
    }

    private func result() -> URL? {
        canvas.commitText()
        guard let image = Canvas.render(canvas.image, canvas.marks) else { return nil }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("peel-\(UUID().uuidString).png")
        do { try Library.writePNG(image, to: file); return file } catch { NSAlert(error: error).runModal(); return nil }
    }

    @objc private func copyResult() {
        guard let file = result() else { return }
        Library.copyImage(file)
        try? FileManager.default.removeItem(at: file)
    }

    @objc private func done() {
        guard let file = result() else { return }
        do {
            let edited = try library.add(file, suffix: " edited")
            Library.copyImage(library.url(edited))
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        finished = true
        window.close()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        canvas.commitText()
        guard !finished, !canvas.marks.isEmpty else { return true }
        let alert = NSAlert()
        alert.messageText = "Discard your edits?"
        alert.informativeText = "The original capture stays on the shelf either way."
        alert.addButton(withTitle: "Keep Editing")
        alert.addButton(withTitle: "Discard")
        return alert.runModal() == .alertSecondButtonReturn
    }

    func windowWillClose(_ notification: Notification) { onClose() }
}
