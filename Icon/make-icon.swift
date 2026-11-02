// Draws the app icon. Run through make-icon.sh, which packages it as an .icns.
import AppKit
import CoreGraphics
import Foundation

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [red, green, blue, alpha])!
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
}

func circle(_ ctx: CGContext, center: CGPoint, radius: CGFloat) {
    ctx.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
}

let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
let center = CGPoint(x: 512, y: 512)

// Background, using Apple's 824pt icon grid on a 1024pt canvas.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0, 0, 0, 0.35))
ctx.addPath(tilePath)
ctx.setFillColor(color(0.1, 0.11, 0.13))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
ctx.drawLinearGradient(
    gradient([color(0.2, 0.22, 0.26), color(0.06, 0.07, 0.09)]),
    start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: []
)
ctx.restoreGState()

// Level marks sweep clockwise over 270 degrees, lit to about 60 percent.
let marks = 25
let lit = 15
let startAngle = CGFloat.pi * 1.25
let sweep = CGFloat.pi * 1.5
for mark in 0..<marks {
    let angle = startAngle - sweep * CGFloat(mark) / CGFloat(marks - 1)
    let point = CGPoint(x: center.x + cos(angle) * 318, y: center.y + sin(angle) * 318)
    let isLit = mark < lit
    ctx.saveGState()
    if isLit {
        ctx.setShadow(offset: .zero, blur: 22, color: color(0.2, 0.85, 0.95, 0.9))
    }
    ctx.setFillColor(isLit ? color(0.3, 0.9, 0.98) : color(1, 1, 1, 0.16))
    circle(ctx, center: point, radius: isLit ? 19 : 15)
    ctx.fillPath()
    ctx.restoreGState()
}

// Knob body.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 44, color: color(0, 0, 0, 0.7))
circle(ctx, center: center, radius: 232)
ctx.setFillColor(color(0.3, 0.32, 0.35))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
circle(ctx, center: center, radius: 232)
ctx.clip()
ctx.drawLinearGradient(
    gradient([color(0.62, 0.65, 0.69), color(0.24, 0.26, 0.29)]),
    start: CGPoint(x: 512, y: 744), end: CGPoint(x: 512, y: 280), options: []
)
ctx.restoreGState()

ctx.saveGState()
circle(ctx, center: center, radius: 204)
ctx.clip()
ctx.drawLinearGradient(
    gradient([color(0.27, 0.29, 0.32), color(0.44, 0.47, 0.51)]),
    start: CGPoint(x: 512, y: 716), end: CGPoint(x: 512, y: 308), options: []
)
ctx.restoreGState()

// Indicator, pointing at the last lit mark.
let pointer = startAngle - sweep * CGFloat(lit - 1) / CGFloat(marks - 1)
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 18, color: color(0.2, 0.85, 0.95, 0.9))
ctx.setStrokeColor(color(0.45, 0.94, 1))
ctx.setLineWidth(30)
ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: center.x + cos(pointer) * 96, y: center.y + sin(pointer) * 96))
ctx.addLine(to: CGPoint(x: center.x + cos(pointer) * 176, y: center.y + sin(pointer) * 176))
ctx.strokePath()
ctx.restoreGState()

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let png = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
try png.write(to: output)
