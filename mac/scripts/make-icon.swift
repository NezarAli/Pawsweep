// Draws Pawsweep's icon (an amber paw on a dark, terminal-colored tile) into an
// .iconset folder for `iconutil`. Its own artwork: Mole's logo is Mole's trademark.
// Usage: swift make-icon.swift <output.iconset>

import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    let size = CGFloat(pixels)
    // Apple's icon grid: an 824/1024 tile, centered.
    let inset = size * 100 / 1024
    let tile = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = size * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.008)
    shadow.set()
    color(0x1B1C1F).setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: color(0x34363C), ending: color(0x16171A))!.draw(in: tilePath, angle: -90)

    // The paw, in tile coordinates (0...1, origin bottom-left).
    func rect(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: tile.minX + (cx - w / 2) * tile.width, y: tile.minY + (cy - h / 2) * tile.height,
               width: w * tile.width, height: h * tile.height)
    }
    func oval(_ r: NSRect, rotation degrees: CGFloat) -> NSBezierPath {
        let path = NSBezierPath(ovalIn: NSRect(x: -r.width / 2, y: -r.height / 2, width: r.width, height: r.height))
        var transform = AffineTransform(translationByX: r.midX, byY: r.midY)
        transform.rotate(byDegrees: degrees)
        path.transform(using: transform)
        return path
    }

    let paw = NSBezierPath()
    // Main pad: a soft rounded triangle.
    let pad = rect(0.5, 0.37, 0.44, 0.34)
    let padPath = NSBezierPath()
    padPath.move(to: NSPoint(x: pad.midX, y: pad.maxY))
    padPath.curve(to: NSPoint(x: pad.maxX, y: pad.minY + pad.height * 0.28),
                  controlPoint1: NSPoint(x: pad.midX + pad.width * 0.30, y: pad.maxY),
                  controlPoint2: NSPoint(x: pad.maxX, y: pad.minY + pad.height * 0.62))
    padPath.curve(to: NSPoint(x: pad.midX, y: pad.minY + pad.height * 0.04),
                  controlPoint1: NSPoint(x: pad.maxX, y: pad.minY - pad.height * 0.02),
                  controlPoint2: NSPoint(x: pad.midX + pad.width * 0.22, y: pad.minY + pad.height * 0.04))
    padPath.curve(to: NSPoint(x: pad.minX, y: pad.minY + pad.height * 0.28),
                  controlPoint1: NSPoint(x: pad.midX - pad.width * 0.22, y: pad.minY + pad.height * 0.04),
                  controlPoint2: NSPoint(x: pad.minX, y: pad.minY - pad.height * 0.02))
    padPath.curve(to: NSPoint(x: pad.midX, y: pad.maxY),
                  controlPoint1: NSPoint(x: pad.minX, y: pad.minY + pad.height * 0.62),
                  controlPoint2: NSPoint(x: pad.midX - pad.width * 0.30, y: pad.maxY))
    padPath.close()
    paw.append(padPath)
    // Four toes, fanned.
    paw.append(oval(rect(0.255, 0.585, 0.135, 0.175), rotation: 28))
    paw.append(oval(rect(0.405, 0.705, 0.145, 0.19), rotation: 9))
    paw.append(oval(rect(0.595, 0.705, 0.145, 0.19), rotation: -9))
    paw.append(oval(rect(0.745, 0.585, 0.135, 0.175), rotation: -28))

    NSGradient(starting: color(0xFFC46B), ending: color(0xF0892E))!.draw(in: paw, angle: -90)

    NSGraphicsContext.current?.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try render(pixels: points * scale).write(to: output.appendingPathComponent(name))
    }
}
