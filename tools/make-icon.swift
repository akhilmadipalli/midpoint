// Generates Resources/AppIcon.icns: a trackpad with three finger dots on a blue squircle.
// Usage: swift tools/make-icon.swift   (run from the repo root)
import AppKit

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024   // design on Apple's 1024 grid: 824pt body, 100pt margin

    // Body: squircle with a vertical gradient and soft shadow.
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.shadowBlurRadius = 24 * s
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.black.setFill(); bodyPath.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(srgbRed: 0.36, green: 0.55, blue: 1.0, alpha: 1),
               ending: NSColor(srgbRed: 0.20, green: 0.24, blue: 0.85, alpha: 1))!.draw(in: bodyPath, angle: -90)

    // Trackpad: frosted rounded rectangle.
    let pad = NSRect(x: 232 * s, y: 300 * s, width: 560 * s, height: 424 * s)
    let padPath = NSBezierPath(roundedRect: pad, xRadius: 56 * s, yRadius: 56 * s)
    NSColor.white.withAlphaComponent(0.92).setFill(); padPath.fill()

    // Three fingertips; the middle one highlighted with a "click" ring.
    let centers: [CGFloat] = [362, 512, 662]
    for (i, cx) in centers.enumerated() {
        let r: CGFloat = 52 * s
        let c = NSPoint(x: cx * s, y: 512 * s + (i == 1 ? 28 * s : 0))
        if i == 1 {
            let ring = NSBezierPath(ovalIn: NSRect(x: c.x - r * 1.6, y: c.y - r * 1.6, width: r * 3.2, height: r * 3.2))
            ring.lineWidth = 12 * s
            NSColor(srgbRed: 0.25, green: 0.36, blue: 0.95, alpha: 0.35).setStroke(); ring.stroke()
        }
        NSColor(srgbRed: 0.22, green: 0.30, blue: 0.90, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: "build/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let png = drawIcon(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try! png.write(to: iconset.appendingPathComponent(name))
    }
}
try! fm.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
try! drawIcon(size: 1024).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "Resources/AppIcon.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "wrote Resources/AppIcon.icns and Resources/AppIcon.png" : "iconutil failed")
