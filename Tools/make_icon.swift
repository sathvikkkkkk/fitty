import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Fittr app icon: one open ring (teal → green) with a dot in the gap, on near-black.
// The ring echoes the recovery / strain rings inside the app.
// Usage: swift make_icon.swift <output.png>

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let size = 1024

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
// No alpha channel: App Store icons must be opaque.
let ctx = CGContext(
    data: nil, width: size, height: size,
    bitsPerComponent: 8, bytesPerRow: 0, space: cs,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!

// Palette (matches Theme.teal → Theme.green)
let teal = (r: 0.208, g: 0.816, b: 0.729)   // #35D0BA
let green = (r: 0.000, g: 0.945, b: 0.624)  // #00F19F

func color(_ t: CGFloat) -> CGColor {
    CGColor(
        srgbRed: teal.r + (green.r - teal.r) * t,
        green: teal.g + (green.g - teal.g) * t,
        blue: teal.b + (green.b - teal.b) * t,
        alpha: 1
    )
}

// Background
ctx.setFillColor(CGColor(srgbRed: 0.02, green: 0.02, blue: 0.024, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

let center = CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
let radius: CGFloat = 280
let lineWidth: CGFloat = 96

// The ring is open between 17° and 67° (upper right); it runs counter-clockwise from 67° to 377°.
func rad(_ degrees: CGFloat) -> CGFloat { degrees * .pi / 180 }
let startDeg: CGFloat = 67
let endDeg: CGFloat = 377

// CoreGraphics has no angular gradient: draw many short segments, each with its own colour.
let segments = 1080
ctx.setLineWidth(lineWidth)
ctx.setLineCap(.butt)
for i in 0..<segments {
    let t0 = CGFloat(i) / CGFloat(segments)
    let t1 = CGFloat(i + 1) / CGFloat(segments)
    let a0 = rad(startDeg + (endDeg - startDeg) * t0)
    let a1 = rad(startDeg + (endDeg - startDeg) * min(1, t1 + 0.0015)) // tiny overlap hides seams
    ctx.setStrokeColor(color((t0 + t1) / 2))
    ctx.addArc(center: center, radius: radius, startAngle: a0, endAngle: a1, clockwise: false)
    ctx.strokePath()
}

// Round end caps in the end colours.
func dot(at degrees: CGFloat, r: CGFloat, fill: CGColor) {
    let p = CGPoint(x: center.x + radius * cos(rad(degrees)), y: center.y + radius * sin(rad(degrees)))
    ctx.setFillColor(fill)
    ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
}
dot(at: startDeg, r: lineWidth / 2, fill: color(0))
dot(at: endDeg, r: lineWidth / 2, fill: color(1))

// The dot in the gap (centre of the opening at 42°), a little smaller than the ring stroke.
dot(at: 42, r: 34, fill: color(1))

guard let image = ctx.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("could not create image destination") }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(out)") }
print("wrote \(out)")
