import AppKit

/// Renders the app logo onto a macOS Big Sur-style squircle tile and writes
/// a 1024x1024 master PNG. Usage: swift scripts/MakeIcon.swift <logo.png> <master.png>
let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write(Data("usage: MakeIcon.swift <logo.png> <master.png>\n".utf8))
    exit(1)
}
guard let logo = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write(Data("cannot read \(args[1])\n".utf8))
    exit(1)
}

let canvas: CGFloat = 1024
let tile: CGFloat = 824      // Apple icon grid: 824pt tile on a 1024pt canvas
let radius: CGFloat = 185.4  // Big Sur squircle corner radius at this size

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let inset = (canvas - tile) / 2
let tileRect = NSRect(x: inset, y: inset, width: tile, height: tile)
let squircle = NSBezierPath(roundedRect: tileRect, xRadius: radius, yRadius: radius)
NSColor.white.setFill()
squircle.fill()
squircle.addClip()
logo.draw(in: tileRect, from: .zero, operation: .sourceOver, fraction: 1)

NSGraphicsContext.current?.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

let png = rep.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: args[2]))
