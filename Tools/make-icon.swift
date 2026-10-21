// Generates Resources/AppIcon.icns: the pink → purple tile with a white music note.
// Usage: swift Tools/make-icon.swift
import AppKit

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let s = CGFloat(size)
    let tile = NSRect(x: s * 0.098, y: s * 0.098, width: s * 0.804, height: s * 0.804)   // macOS icon grid
    let path = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = s * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    shadow.set()
    NSColor.black.setFill(); path.fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    NSGradient(starting: .systemPink, ending: .systemPurple)!.draw(in: path, angle: -45)

    let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.42, weight: .semibold)
    if let sym = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
        let white = NSImage(size: sym.size, flipped: false) { r in
            sym.draw(in: r); NSColor.white.set(); r.fill(using: .sourceIn); return true
        }
        let r = NSRect(x: (s - white.size.width) / 2, y: (s - white.size.height) / 2,
                       width: white.size.width, height: white.size.height)
        white.draw(in: r)
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let set = "build/AppIcon.iconset"
try? fm.removeItem(atPath: set)
try fm.createDirectory(atPath: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: URL(fileURLWithPath: "\(set)/icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: URL(fileURLWithPath: "\(set)/icon_\(base)x\(base)@2x.png"))
}
try fm.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set, "-o", "Resources/AppIcon.icns"]
try p.run(); p.waitUntilExit()
try? fm.removeItem(atPath: set)
print("OK → Resources/AppIcon.icns")
