import AppKit
import ImageIO
import UniformTypeIdentifiers
import Vision

struct PeelError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// One screenshot on the shelf. `name` is its file name in the library folder, e.g. "Peel 2026-11-02 at 13.45.12.png".
struct Capture: Codable, Identifiable, Equatable {
    let name: String
    let date: Date
    var text: String? // recognised text; nil until text recognition has run
    var id: String { name }
}

/// Every capture, newest first, kept as PNG files plus an index.json in Peel's own folder.
/// Captures older than Prefs.keepDays go to the Trash (never deleted outright), so nothing is lost by surprise.
final class Library: ObservableObject {
    static let shared = Library()

    @Published private(set) var items: [Capture] = []
    let dir: URL
    private var index: URL { dir.appendingPathComponent("index.json") }

    /// PEEL_LIBRARY overrides the folder (the self-test uses a temporary one).
    init(dir: URL? = nil) {
        self.dir = dir ?? ProcessInfo.processInfo.environment["PEEL_LIBRARY"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Peel/Captures")
        try? FileManager.default.createDirectory(at: self.dir, withIntermediateDirectories: true)
        let saved = (try? Data(contentsOf: index)).flatMap { try? JSONDecoder().decode([Capture].self, from: $0) } ?? []
        items = saved.filter { FileManager.default.fileExists(atPath: url($0).path) }
        items.filter { $0.text == nil }.forEach(recognize) // e.g. Peel quit before it finished
    }

    func url(_ capture: Capture) -> URL { dir.appendingPathComponent(capture.name) }

    /// Moves a new PNG into the library and starts reading its text.
    @discardableResult
    func add(_ file: URL, date: Date = Date(), suffix: String = "") throws -> Capture {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let base = "Peel \(f.string(from: date))\(suffix)"
        var name = base + ".png", n = 2
        while FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path) { name = "\(base) \(n).png"; n += 1 }
        try FileManager.default.moveItem(at: file, to: dir.appendingPathComponent(name))
        let capture = Capture(name: name, date: date, text: nil)
        items.insert(capture, at: 0)
        save()
        recognize(capture)
        return capture
    }

    /// Removes it from the shelf and moves the file to the Trash (Finder's Put Back can restore the file).
    func remove(_ capture: Capture) {
        try? FileManager.default.trashItem(at: url(capture), resultingItemURL: nil)
        items.removeAll { $0 == capture }
        save()
    }

    func prune(keepDays: Int) {
        guard keepDays > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(keepDays) * 86400)
        items.filter { $0.date < cutoff }.forEach(remove)
    }

    /// Every word must appear in the capture's text (any order, any case).
    func search(_ query: String) -> [Capture] {
        let words = query.lowercased().split(separator: " ")
        guard !words.isEmpty else { return items }
        return items.filter { c in
            let text = (c.text ?? "").lowercased()
            return words.allSatisfy { text.contains($0) }
        }
    }

    private func save() {
        try? JSONEncoder().encode(items).write(to: index, options: .atomic)
    }

    private func recognize(_ capture: Capture) {
        let file = url(capture)
        DispatchQueue.global(qos: .utility).async {
            // One retry: the first request after launch can come back empty while Vision loads its model.
            var text = (try? Self.text(in: file)) ?? ""
            if text.isEmpty {
                Thread.sleep(forTimeInterval: 1)
                text = (try? Self.text(in: file)) ?? ""
            }
            DispatchQueue.main.async {
                guard let i = self.items.firstIndex(where: { $0.name == capture.name }) else { return }
                self.items[i].text = text
                self.save()
            }
        }
    }

    /// On-device text recognition (Vision). Nothing leaves the Mac.
    static func text(in file: URL) throws -> String {
        guard let image = cgImage(file) else { throw PeelError("Couldn't read \(file.lastPathComponent).") }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    // MARK: - Files and clipboard

    static func cgImage(_ file: URL) -> CGImage? {
        CGImageSourceCreateWithURL(file as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    }

    /// A small preview for the shelf, without decoding the full-size image.
    static func thumbnail(_ file: URL, maxPixels: Int = 480) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(file as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                     kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                                                                     kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
        else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    /// PNG and TIFF, so it pastes into chat apps, mail, Preview and documents alike.
    static func copyImage(_ file: URL) {
        guard let png = try? Data(contentsOf: file) else { return }
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        if let tiff = NSImage(data: png)?.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item])
    }

    static func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// A copy in the user's save folder (PNG or JPG); the library keeps its own. Returns the new file.
    static func export(_ file: URL, to folder: URL, format: SaveFormat) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = file.deletingPathExtension().lastPathComponent
        var out = folder.appendingPathComponent(base).appendingPathExtension(format.rawValue), n = 2
        while FileManager.default.fileExists(atPath: out.path) {
            out = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(format.rawValue); n += 1
        }
        if format == .png { try FileManager.default.copyItem(at: file, to: out); return out }
        guard let image = cgImage(file),
              let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw PeelError("Couldn't make a JPG of \(file.lastPathComponent).") }
        CGImageDestinationAddImage(dest, flattened(image), [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw PeelError("Couldn't write \(out.lastPathComponent).") }
        return out
    }

    /// JPG has no transparency (window shadows): put the image on white first.
    static func flattened(_ image: CGImage) -> CGImage {
        let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(.white)
        ctx.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage() ?? image
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw PeelError("Couldn't save the image.")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw PeelError("Couldn't save the image.") }
    }
}
