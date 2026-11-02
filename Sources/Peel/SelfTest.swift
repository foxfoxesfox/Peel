import AppKit

/// Text recognition, search, redaction, crop and export on a generated image, in a temporary library.
enum SelfTest {
    static func run() -> Bool {
        var ok = true
        func check(_ pass: Bool, _ what: String) {
            print((pass ? "ok    " : "FAIL  ") + what)
            ok = ok && pass
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("peel-selftest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let library = Library(dir: tmp.appendingPathComponent("lib"))

        // A fake screenshot: two lines of text on white.
        let w = 1200, h = 300
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(.white); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let font = NSFont.systemFont(ofSize: 56, weight: .medium)
        NSAttributedString(string: "Invoice number 48213", attributes: [.font: font]).draw(at: NSPoint(x: 40, y: 180))
        NSAttributedString(string: "Secret key ABCD9876", attributes: [.font: font]).draw(at: NSPoint(x: 40, y: 50))
        NSGraphicsContext.current = nil
        let source = ctx.makeImage()!
        let file = tmp.appendingPathComponent("shot.png")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        try! Library.writePNG(source, to: file)

        let capture = try! library.add(file)
        check(FileManager.default.fileExists(atPath: library.url(capture).path), "capture moved into the library")
        let deadline = Date().addingTimeInterval(60)
        while library.items.first?.text == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        print("      (text ready: \(library.items.first?.text != nil), waited \(Int(60 - deadline.timeIntervalSinceNow))s)")
        let text = library.items.first?.text ?? ""
        check(text.contains("48213"), "text recognised: \(text.replacingOccurrences(of: "\n", with: " | "))")
        check(library.search("invoice 48213").count == 1, "search finds it by two words")
        check(library.search("banana").isEmpty, "search skips captures without the word")
        check(Library(dir: tmp.appendingPathComponent("lib")).items.first?.text == text, "index survives a restart")

        // Redact the second line: its text must be gone from the exported pixels.
        let redact = Mark(tool: .redact, a: CGPoint(x: 20, y: 30), b: CGPoint(x: 1180, y: 130), color: .black)
        let redacted = Canvas.render(source, [redact])!
        let out = tmp.appendingPathComponent("redacted.png")
        try! Library.writePNG(redacted, to: out)
        let after = (try? Library.text(in: out)) ?? ""
        check(!after.contains("9876") && after.contains("48213"), "redaction removes the hidden text only")

        // Crop to the top half.
        let crop = Mark(tool: .crop, a: CGPoint(x: 0, y: 150), b: CGPoint(x: 600, y: 300), color: .black)
        let cropped = Canvas.render(source, [redact, crop])!
        check(cropped.width == 600 && cropped.height == 150, "crop gives 600×150 (got \(cropped.width)×\(cropped.height))")
        let cropFile = tmp.appendingPathComponent("cropped.png")
        try! Library.writePNG(cropped, to: cropFile)
        check(((try? Library.text(in: cropFile)) ?? "").contains("Invoice"), "crop keeps the top half")

        // Save as JPG, twice: the second gets a new name instead of overwriting.
        let saved = tmp.appendingPathComponent("saved")
        let jpg1 = try? Library.export(library.url(capture), to: saved, format: .jpg)
        let jpg2 = try? Library.export(library.url(capture), to: saved, format: .jpg)
        let head = jpg1.flatMap { try? Data(contentsOf: $0).prefix(3) }
        check(head == Data([0xFF, 0xD8, 0xFF]), "save as JPG writes a JPEG")
        check(jpg1 != nil && jpg2 != nil && jpg1 != jpg2, "saving again doesn't overwrite")

        check(Shortcut.capture.title == "⇧⌘2", "default capture shortcut is ⇧⌘2")
        check(Updater.isNewer("1.10", than: "1.9") && !Updater.isNewer("1.0", than: "1.0"), "version comparison")
        check((try? Updater.checkSameSigner(Bundle.main.bundleURL)) != nil, "update signer check accepts this build")
        check((try? Updater.checkSameSigner(URL(fileURLWithPath: "/System/Applications/Calculator.app"))) == nil
              || !Bundle.main.bundlePath.hasSuffix(".app"), "update signer check rejects another developer's app")
        print(ok ? "All checks passed." : "Some checks failed.")
        return ok
    }
}
