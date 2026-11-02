// Draws Peel's app icon: a screen selection with its corner peeling up.
// Usage: swift scripts/icon.swift out.png   (1024x1024)
import AppKit

let s: CGFloat = 1024
let ctx = CGContext(data: nil, width: Int(s), height: Int(s), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

// Rounded tile on Apple's icon grid (824 pt inside 1024, with room for the shadow).
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.3))
ctx.addPath(tilePath); ctx.setFillColor(rgb(0xFF8A3D)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(tilePath); ctx.clip()
let g = CGGradient(colorsSpace: nil, colors: [rgb(0xFFB25B), rgb(0xFF6A3D)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
ctx.restoreGState()

// The "screenshot": a white sheet whose top-right corner is folded back.
let sheet = CGRect(x: 250, y: 270, width: 524, height: 484), fold: CGFloat = 190
let body = CGMutablePath()
body.move(to: CGPoint(x: sheet.minX, y: sheet.minY))
body.addLine(to: CGPoint(x: sheet.maxX, y: sheet.minY))
body.addLine(to: CGPoint(x: sheet.maxX, y: sheet.maxY - fold))
body.addLine(to: CGPoint(x: sheet.maxX - fold, y: sheet.maxY))
body.addLine(to: CGPoint(x: sheet.minX, y: sheet.maxY))
body.closeSubpath()
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0x7A2E00, 0.35))
ctx.addPath(body); ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath()
ctx.restoreGState()

// Dashed selection marks inside the sheet.
ctx.setStrokeColor(rgb(0xFF7A3D)); ctx.setLineWidth(22); ctx.setLineCap(.round)
ctx.setLineDash(phase: 0, lengths: [44, 40])
ctx.stroke(CGRect(x: sheet.minX + 70, y: sheet.minY + 70, width: 250, height: 200))
ctx.setLineDash(phase: 0, lengths: [])

// The peeled corner, lit from above.
let flap = CGMutablePath()
flap.move(to: CGPoint(x: sheet.maxX, y: sheet.maxY - fold))
flap.addLine(to: CGPoint(x: sheet.maxX - fold, y: sheet.maxY))
flap.addQuadCurve(to: CGPoint(x: sheet.maxX, y: sheet.maxY - fold), control: CGPoint(x: sheet.maxX - fold * 0.85, y: sheet.maxY - fold * 0.85))
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: -8, height: -10), blur: 18, color: rgb(0x7A2E00, 0.4))
ctx.addPath(flap); ctx.setFillColor(rgb(0xFFE3CC)); ctx.fillPath()
ctx.restoreGState()

try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
