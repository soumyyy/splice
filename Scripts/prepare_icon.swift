// Turns a rounded-tile icon image into a square, opaque 1024×1024 app icon.
// It crops to the light tile, paints the rounded corners with the tile colour
// (iOS applies its own corner mask), and scales up.
// Usage: swiftc -O Scripts/prepare_icon.swift -o prepare_icon && ./prepare_icon <input.png> <output.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
  fatalError("usage: prepare_icon <input.png> <output.png>")
}

let space = CGColorSpaceCreateDeviceRGB()
let rgba = CGImageAlphaInfo.premultipliedLast.rawValue

/// Draws an image into an RGBA8 buffer so pixels can be read as bytes.
func pixels(of image: CGImage, width: Int, height: Int) -> (CGContext, UnsafeMutablePointer<UInt8>) {
  let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: space, bitmapInfo: rgba)!
  ctx.interpolationQuality = .high
  ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
  return (ctx, ctx.data!.assumingMemoryBound(to: UInt8.self))
}

let w = image.width, h = image.height
let (sourceContext, src) = pixels(of: image, width: w, height: h)
func luminance(_ p: UnsafeMutablePointer<UInt8>, _ i: Int) -> Double {
  (0.299 * Double(p[i]) + 0.587 * Double(p[i + 1]) + 0.114 * Double(p[i + 2])) / 255
}

// Bounding box of the light tile (buffer rows run top to bottom).
var minX = w, minY = h, maxX = 0, maxY = 0
for y in 0..<h { for x in 0..<w where luminance(src, (y * w + x) * 4) > 0.8 {
  minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
} }
let side = max(maxX - minX, maxY - minY) + 1
let tileIndex = ((minY + 6) * w + (minX + maxX) / 2) * 4
let tile = (src[tileIndex], src[tileIndex + 1], src[tileIndex + 2])

// Copy the tile, then flood-fill from the edges: dark pixels connected to the outside
// are the rounded corners, so they become tile colour. Artwork inside is never reached.
let cropCtx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                        space: space, bitmapInfo: rgba)!
let crop = cropCtx.data!.assumingMemoryBound(to: UInt8.self)
for y in 0..<side { for x in 0..<side {
  let s = (min(h - 1, minY + y) * w + min(w - 1, minX + x)) * 4
  let d = (y * side + x) * 4
  (crop[d], crop[d + 1], crop[d + 2], crop[d + 3]) = (src[s], src[s + 1], src[s + 2], 255)
} }
var visited = [Bool](repeating: false, count: side * side)
var stack: [(Int, Int)] = []
for i in 0..<side { stack += [(i, 0), (i, side - 1), (0, i), (side - 1, i)] }
while let (x, y) = stack.popLast() {
  guard x >= 0, y >= 0, x < side, y < side, !visited[y * side + x] else { continue }
  visited[y * side + x] = true
  let d = (y * side + x) * 4
  guard luminance(crop, d) < 0.9 else { continue }
  (crop[d], crop[d + 1], crop[d + 2]) = tile
  stack += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
}

// Scale to 1024 without alpha.
let size = 1024
let out = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
out.interpolationQuality = .high
out.draw(cropCtx.makeImage()!, in: CGRect(x: 0, y: 0, width: size, height: size))

let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, out.makeImage()!, nil)
CGImageDestinationFinalize(dest)
withExtendedLifetime(sourceContext) {}
print("tile at \(minX),\(minY), \(side)px -> \(size)px")
