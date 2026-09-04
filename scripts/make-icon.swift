import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: tmp)
try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

func draw(size s: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(s), pixelsHigh: Int(s), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let inset = s * 0.08
    let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)

    path.addClip()
    let bg = NSGradient(colors: [NSColor(white: 0.16, alpha: 1), NSColor(white: 0.09, alpha: 1)])!
    bg.draw(in: rect, angle: -90)

    let center = CGPoint(x: rect.midX, y: rect.midY)
    let radius = rect.width * 0.30
    let lineWidth = rect.width * 0.13
    let segments: [(CGFloat, NSColor)] = [
        (0.40, NSColor(hue: 0.58, saturation: 0.50, brightness: 0.74, alpha: 1)),
        (0.18, NSColor(hue: 0.11, saturation: 0.62, brightness: 0.84, alpha: 1)),
        (0.14, NSColor(hue: 0.26, saturation: 0.40, brightness: 0.66, alpha: 1)),
        (0.12, NSColor(hue: 0.03, saturation: 0.55, brightness: 0.78, alpha: 1)),
        (0.16, NSColor(white: 1, alpha: 0.14)),
    ]
    var start: CGFloat = 90
    let gap: CGFloat = 4
    ctx.setLineCap(.round)
    for (frac, color) in segments {
        let sweep = 360 * frac
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius, startAngle: start - gap / 2, endAngle: start - sweep + gap / 2, clockwise: true)
        arc.lineWidth = lineWidth
        arc.lineCapStyle = .round
        color.setStroke()
        arc.stroke()
        start -= sweep
    }

    let hl = NSGradient(colors: [NSColor(white: 1, alpha: 0.10), NSColor(white: 1, alpha: 0)])!
    hl.draw(in: NSBezierPath(rect: CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2)), angle: 90)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let sizes: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, size) in sizes {
    let rep = draw(size: size)
    try! rep.representation(using: .png, properties: [:])!.write(to: tmp.appendingPathComponent("\(name).png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", tmp.path, "-o", out]
try! task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "✔ \(out)" : "iconutil failed")
