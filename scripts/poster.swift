// Draws Resources/social-preview.png (1280×640): the GitHub social preview / README banner.
// Usage: swift scripts/poster.swift Resources/social-preview.png
import AppKit

let W: CGFloat = 1280, H: CGFloat = 640
let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
func text(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor, at p: CGPoint) {
    NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]).draw(at: p)
}

// Warm background, like the icon.
let bg = CGGradient(colorsSpace: nil, colors: [rgb(0xFFB25B).cgColor, rgb(0xFF6A3D).cgColor] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0), options: [])

// Left: icon, name, tagline.
if let icon = NSImage(contentsOfFile: "Resources/icon-1024.png") {
    icon.draw(in: NSRect(x: 70, y: 330, width: 200, height: 200))
}
text("Peel", 96, .heavy, .white, at: CGPoint(x: 80, y: 205))
text("Screenshots that are easy to take,", 30, .semibold, rgb(0xFFFFFF, 0.95), at: CGPoint(x: 84, y: 160))
text("mark up and find again.", 30, .semibold, rgb(0xFFFFFF, 0.95), at: CGPoint(x: 84, y: 122))
text("⇧⌘2  ·  menu bar  ·  private, offline", 22, .medium, rgb(0x7A2E00, 0.85), at: CGPoint(x: 84, y: 70))

// Right: a shelf panel with a search and three captures.
let panel = NSRect(x: 690, y: 70, width: 520, height: 500)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow(); shadow.shadowBlurRadius = 30; shadow.shadowOffset = NSSize(width: 0, height: -12); shadow.shadowColor = rgb(0x7A2E00, 0.35)
shadow.set()
rgb(0xFBFAF8).setFill(); NSBezierPath(roundedRect: panel, xRadius: 22, yRadius: 22).fill()
NSGraphicsContext.restoreGraphicsState()

let search = NSRect(x: panel.minX + 24, y: panel.maxY - 70, width: panel.width - 48, height: 44)
rgb(0xEDEAE6).setFill(); NSBezierPath(roundedRect: search, xRadius: 12, yRadius: 12).fill()
text("⌕  invoice 4821", 22, .regular, rgb(0x3A3A3C), at: CGPoint(x: search.minX + 16, y: search.minY + 10))

func capture(_ r: NSRect, lines: Int, redact: Bool, arrow: Bool, highlight: Bool) {
    rgb(0xFFFFFF).setFill(); NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).fill()
    rgb(0x000000, 0.08).setStroke(); NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).stroke()
    for i in 0..<lines {
        let line = NSRect(x: r.minX + 18, y: r.maxY - 34 - CGFloat(i) * 26, width: r.width * (i % 2 == 0 ? 0.7 : 0.5), height: 12)
        rgb(0xC9C6C1).setFill(); NSBezierPath(roundedRect: line, xRadius: 6, yRadius: 6).fill()
        if highlight && i == 1 { rgb(0xFFD60A, 0.55).setFill(); NSBezierPath(rect: line.insetBy(dx: -4, dy: -5)).fill() }
        if redact && i == 2 { rgb(0x000000).setFill(); NSBezierPath(rect: line.insetBy(dx: -4, dy: -5)).fill() }
    }
    if arrow {
        let a = NSBezierPath(); a.lineWidth = 6; a.lineCapStyle = .round
        a.move(to: CGPoint(x: r.maxX - 30, y: r.minY + 24)); a.line(to: CGPoint(x: r.maxX - 90, y: r.minY + 74))
        rgb(0xFF3B30).setStroke(); a.stroke()
        let head = NSBezierPath()
        head.move(to: CGPoint(x: r.maxX - 98, y: r.minY + 81)); head.line(to: CGPoint(x: r.maxX - 74, y: r.minY + 76)); head.line(to: CGPoint(x: r.maxX - 90, y: r.minY + 58)); head.close()
        rgb(0xFF3B30).setFill(); head.fill()
    }
}
let tileW = (panel.width - 24 * 2 - 18) / 2
capture(NSRect(x: panel.minX + 24, y: panel.minY + 200, width: tileW, height: 190), lines: 5, redact: true, arrow: true, highlight: true)
capture(NSRect(x: panel.minX + 42 + tileW, y: panel.minY + 200, width: tileW, height: 190), lines: 4, redact: false, arrow: false, highlight: false)
capture(NSRect(x: panel.minX + 24, y: panel.minY + 24, width: panel.width - 48, height: 150), lines: 3, redact: false, arrow: false, highlight: true)
text("Click to copy · Drag into any app · Double-click to edit", 15, .regular, rgb(0x8E8E93), at: CGPoint(x: panel.minX + 70, y: panel.minY + 2))

try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
