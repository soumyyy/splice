// Renders the 1024×1024 app icon: a heartbeat line, cut and re-joined.
// Usage: swift Scripts/make_icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments[1]
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Background: deep near-black with a warm glow from the center.
let space = CGColorSpaceCreateDeviceRGB()
ctx.setFillColor(CGColor(red: 0.05, green: 0.04, blue: 0.06, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
let glow = CGGradient(colorsSpace: space, colors: [
  CGColor(red: 0.55, green: 0.08, blue: 0.10, alpha: 0.55),
  CGColor(red: 0.05, green: 0.04, blue: 0.06, alpha: 0),
] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 512), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 512), endRadius: 560, options: [])

// Heartbeat path in two halves. The right half sits a little lower: the splice.
func strand(_ points: [CGPoint]) -> CGPath {
  let p = CGMutablePath()
  p.move(to: points[0])
  points.dropFirst().forEach { p.addLine(to: $0) }
  return p
}
let left = strand([
  CGPoint(x: 120, y: 500), CGPoint(x: 330, y: 500), CGPoint(x: 390, y: 410),
  CGPoint(x: 470, y: 800), CGPoint(x: 505, y: 500),
])
let right = strand([
  CGPoint(x: 545, y: 470), CGPoint(x: 590, y: 240), CGPoint(x: 660, y: 560),
  CGPoint(x: 710, y: 470), CGPoint(x: 904, y: 470),
])

let lineGradient = CGGradient(colorsSpace: space, colors: [
  CGColor(red: 1.0, green: 0.30, blue: 0.24, alpha: 1),
  CGColor(red: 1.0, green: 0.55, blue: 0.20, alpha: 1),
] as CFArray, locations: [0, 1])!

for path in [left, right] {
  ctx.saveGState()
  ctx.addPath(path)
  ctx.setLineWidth(64)
  ctx.setLineCap(.round)
  ctx.setLineJoin(.round)
  ctx.replacePathWithStrokedPath()
  ctx.clip()
  ctx.drawLinearGradient(lineGradient, start: CGPoint(x: 120, y: 0), end: CGPoint(x: 904, y: 0), options: [])
  ctx.restoreGState()
}

// The cut: a thin white slash between the halves.
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.92))
ctx.setLineWidth(18)
ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: 500, y: 400))
ctx.addLine(to: CGPoint(x: 552, y: 570))
ctx.strokePath()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
