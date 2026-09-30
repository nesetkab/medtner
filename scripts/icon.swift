import AppKit

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.1
    let body = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    NSColor(red: 0.067, green: 0.067, blue: 0.067, alpha: 1).setFill()
    NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225).fill()

    let u = body.width / 10
    NSColor(white: 0.55, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: body.minX + u * 1.6, y: body.minY + u * 1.6, width: u * 0.22, height: u * 6.8), xRadius: u * 0.11, yRadius: u * 0.11).fill()
    NSColor(red: 0.84, green: 0.72, blue: 1.0, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: body.minX + u * 1.24, y: body.minY + u * 4.6, width: u * 0.95, height: u * 0.95), xRadius: u * 0.26, yRadius: u * 0.26).fill()
    NSColor(white: 0.85, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: body.minX + u * 3.0, y: body.minY + u * 2.4, width: u * 5.2, height: u * 5.2), xRadius: u * 0.6, yRadius: u * 0.6).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try! render(size).write(to: URL(fileURLWithPath: "\(out)/icon_\(size)x\(size).png"))
    try! render(size * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(size)x\(size)@2x.png"))
}
