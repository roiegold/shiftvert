// Draws the 1024×1024 app icon PNG: swift scripts/make-icon.swift out.png
import AppKit

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(srgbRed: 0.33, green: 0.40, blue: 1, alpha: 1), NSColor(srgbRed: 0.70, green: 0.30, blue: 0.95, alpha: 1)])!
    .draw(in: tile, angle: -60)

let config = NSImage.SymbolConfiguration(pointSize: 420, weight: .bold).applying(.init(paletteColors: [.white]))
if let symbol = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
    let s = symbol.size
    symbol.draw(in: NSRect(x: 512 - s.width / 2, y: 512 - s.height / 2, width: s.width, height: s.height))
}

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
