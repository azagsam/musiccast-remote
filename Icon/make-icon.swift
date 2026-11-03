// Draws the app icon. Run through make-icon.sh, which packages it as an .icns.
import AppKit
import CoreGraphics
import Foundation

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    let channel = { (shift: UInt32) in CGFloat((hex >> shift) & 0xff) / 255 }
    return CGColor(colorSpace: space, components: [channel(16), channel(8), channel(0), alpha])!
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
}

let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

// Background, using Apple's 824pt icon grid on a 1024pt canvas.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
ctx.addPath(tilePath)
ctx.setFillColor(color(0x18181B))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
ctx.drawLinearGradient(
    gradient([color(0x2A2A2F), color(0x17171A)]),
    start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: []
)
ctx.restoreGState()

// Level bars standing on a shared baseline.
let heights: [CGFloat] = [282, 414, 233, 348]
let width: CGFloat = 82
let gap: CGFloat = 33
let baseline: CGFloat = 312
let total = CGFloat(heights.count) * width + CGFloat(heights.count - 1) * gap
for (index, height) in heights.enumerated() {
    let x = 512 - total / 2 + CGFloat(index) * (width + gap)
    let bar = CGRect(x: x, y: baseline, width: width, height: height)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: bar, cornerWidth: width / 2, cornerHeight: width / 2, transform: nil))
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([color(0x6BA6FF), color(0x2D5FDB)]),
        start: CGPoint(x: 0, y: bar.maxY), end: CGPoint(x: 0, y: bar.minY), options: []
    )
    ctx.restoreGState()
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let png = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
try png.write(to: output)
