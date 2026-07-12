// Renders the Porthole icon FOREGROUND layer (porthole only, transparent
// background) for the Icon Composer (.icon) format. The squircle background
// becomes the .icon fill gradient; glass/specular comes from the system.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let outputPath = CommandLine.arguments[1]

func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [r, g, b, a])!
}

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: stops.map(\.1) as CFArray,
        locations: stops.map(\.0)
    )!
}

let ctx = CGContext(
    data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
ctx.interpolationQuality = .high

let center = CGPoint(x: 512, y: 512)

// --- Glass: sky + sea seen through the porthole ---
let glassRadius: CGFloat = 236
let horizon: CGFloat = 535
ctx.saveGState()
ctx.addEllipse(in: CGRect(
    x: center.x - glassRadius, y: center.y - glassRadius,
    width: glassRadius * 2, height: glassRadius * 2
))
ctx.clip()
ctx.drawLinearGradient(
    gradient([(0.0, srgb(0.45, 0.74, 0.93)), (1.0, srgb(0.78, 0.91, 0.98))]),
    start: CGPoint(x: 512, y: horizon), end: CGPoint(x: 512, y: center.y + glassRadius), options: []
)
ctx.drawRadialGradient(
    gradient([(0.0, srgb(1.0, 0.96, 0.80, 0.95)), (0.35, srgb(1.0, 0.93, 0.66, 0.55)), (1.0, srgb(1.0, 0.93, 0.66, 0.0))]),
    startCenter: CGPoint(x: 610, y: 645), startRadius: 0,
    endCenter: CGPoint(x: 610, y: 645), endRadius: 95, options: []
)
ctx.setFillColor(srgb(1.0, 0.99, 0.93))
ctx.fillEllipse(in: CGRect(x: 610 - 30, y: 645 - 30, width: 60, height: 60))
ctx.drawLinearGradient(
    gradient([(0.0, srgb(0.05, 0.32, 0.51)), (1.0, srgb(0.16, 0.55, 0.80))]),
    start: CGPoint(x: 512, y: center.y - glassRadius), end: CGPoint(x: 512, y: horizon), options: []
)
func waveBand(baseY: CGFloat, amplitude: CGFloat, wavelength: CGFloat, phase: CGFloat, color: CGColor) {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 240, y: baseY))
    var x: CGFloat = 240
    while x <= 790 {
        let y = baseY + amplitude * sin((x + phase) / wavelength * 2 * .pi)
        path.addLine(to: CGPoint(x: x, y: y))
        x += 8
    }
    path.addLine(to: CGPoint(x: 790, y: baseY - 46))
    path.addLine(to: CGPoint(x: 240, y: baseY - 46))
    path.closeSubpath()
    ctx.addPath(path)
    ctx.setFillColor(color)
    ctx.fillPath()
}
waveBand(baseY: 512, amplitude: 7, wavelength: 150, phase: 40, color: srgb(0.42, 0.72, 0.90, 0.35))
waveBand(baseY: 462, amplitude: 10, wavelength: 130, phase: 105, color: srgb(0.35, 0.66, 0.86, 0.5))
waveBand(baseY: 404, amplitude: 13, wavelength: 115, phase: 0, color: srgb(0.28, 0.60, 0.82, 0.65))
// Sailboat
ctx.setFillColor(srgb(0.18, 0.23, 0.28))
let hull = CGMutablePath()
hull.move(to: CGPoint(x: 388, y: 540))
hull.addLine(to: CGPoint(x: 472, y: 540))
hull.addLine(to: CGPoint(x: 456, y: 518))
hull.addLine(to: CGPoint(x: 404, y: 518))
hull.closeSubpath()
ctx.addPath(hull)
ctx.fillPath()
ctx.setFillColor(srgb(0.99, 0.99, 0.97))
let sail = CGMutablePath()
sail.move(to: CGPoint(x: 428, y: 548))
sail.addLine(to: CGPoint(x: 428, y: 640))
sail.addLine(to: CGPoint(x: 372, y: 548))
sail.closeSubpath()
ctx.addPath(sail)
ctx.fillPath()
let jib = CGMutablePath()
jib.move(to: CGPoint(x: 440, y: 548))
jib.addLine(to: CGPoint(x: 440, y: 620))
jib.addLine(to: CGPoint(x: 482, y: 548))
jib.closeSubpath()
ctx.addPath(jib)
ctx.fillPath()
// Recessed rim shadow at the glass edge (kept: reads as depth at all sizes).
ctx.setStrokeColor(srgb(0.0, 0.08, 0.15, 0.45))
ctx.setLineWidth(26)
ctx.strokeEllipse(in: CGRect(
    x: center.x - glassRadius - 2, y: center.y - glassRadius - 2,
    width: (glassRadius + 2) * 2, height: (glassRadius + 2) * 2
))
ctx.restoreGState()

// --- Metallic ring ---
let ringOuter: CGFloat = 312
let ringInner: CGFloat = 240
ctx.saveGState()
let annulus = CGMutablePath()
annulus.addEllipse(in: CGRect(x: center.x - ringOuter, y: center.y - ringOuter, width: ringOuter * 2, height: ringOuter * 2))
annulus.addEllipse(in: CGRect(x: center.x - ringInner, y: center.y - ringInner, width: ringInner * 2, height: ringInner * 2))
ctx.addPath(annulus)
ctx.clip(using: .evenOdd)
ctx.drawLinearGradient(
    gradient([
        (0.0, srgb(0.97, 0.98, 1.0)),
        (0.28, srgb(0.80, 0.84, 0.89)),
        (0.55, srgb(0.55, 0.61, 0.68)),
        (0.78, srgb(0.74, 0.79, 0.85)),
        (1.0, srgb(0.50, 0.56, 0.63)),
    ]),
    start: CGPoint(x: 300, y: 824), end: CGPoint(x: 724, y: 200), options: []
)
ctx.restoreGState()
ctx.setStrokeColor(srgb(0.20, 0.25, 0.31, 0.9))
ctx.setLineWidth(6)
ctx.strokeEllipse(in: CGRect(x: center.x - ringOuter, y: center.y - ringOuter, width: ringOuter * 2, height: ringOuter * 2))
ctx.setStrokeColor(srgb(0.24, 0.30, 0.36, 0.9))
ctx.setLineWidth(5)
ctx.strokeEllipse(in: CGRect(x: center.x - ringInner, y: center.y - ringInner, width: ringInner * 2, height: ringInner * 2))
ctx.setStrokeColor(srgb(1, 1, 1, 0.35))
ctx.setLineWidth(3)
ctx.strokeEllipse(in: CGRect(x: center.x - ringOuter + 7, y: center.y - ringOuter + 7, width: (ringOuter - 7) * 2, height: (ringOuter - 7) * 2))

// --- Bolts ---
let boltOrbit: CGFloat = 276
let boltRadius: CGFloat = 17
for i in 0..<8 {
    let angle = CGFloat(i) * .pi / 4 + .pi / 8
    let bx = center.x + boltOrbit * cos(angle)
    let by = center.y + boltOrbit * sin(angle)
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: bx - boltRadius, y: by - boltRadius, width: boltRadius * 2, height: boltRadius * 2))
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([(0.0, srgb(0.92, 0.94, 0.97)), (1.0, srgb(0.42, 0.48, 0.55))]),
        start: CGPoint(x: bx - boltRadius, y: by + boltRadius),
        end: CGPoint(x: bx + boltRadius, y: by - boltRadius), options: []
    )
    ctx.restoreGState()
    ctx.setStrokeColor(srgb(0.25, 0.30, 0.36, 0.85))
    ctx.setLineWidth(3)
    ctx.strokeEllipse(in: CGRect(x: bx - boltRadius, y: by - boltRadius, width: boltRadius * 2, height: boltRadius * 2))
}

let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outputPath) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("failed to write foreground") }
print("wrote \(outputPath)")
