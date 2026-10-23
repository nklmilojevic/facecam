// Renders the 1024×1024 app icon PNG: swift scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"

// Catppuccin Mocha
func rgb(_ hex: UInt32) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
let crust = rgb(0x11111B), base = rgb(0x1E1E2E), surface0 = rgb(0x313244), surface1 = rgb(0x45475A)
let overlay0 = rgb(0x6C7086), mauve = rgb(0xCBA6F7), blue = rgb(0x89B4FA), lavender = rgb(0xB4BEFE)
let green = rgb(0xA6E3A1), text = rgb(0xCDD6F4)

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func linear(_ colors: [CGColor], from: CGPoint, to: CGPoint) {
    let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(gradient, start: from, end: to, options: [])
}

func radial(_ colors: [CGColor], center: CGPoint, radius: CGFloat) {
    let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

func clipped(_ path: CGPath, _ draw: () -> Void) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    draw()
    ctx.restoreGState()
}

func circle(_ center: CGPoint, _ radius: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2),
           transform: nil)
}

// macOS icon grid: 824pt tile centred in 1024 with a continuous-corner radius of ~185.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.45))
ctx.addPath(tilePath)
ctx.setFillColor(base)
ctx.fillPath()
ctx.restoreGState()
clipped(tilePath) {
    linear([surface0, base, crust], from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 100))
}

// Camera body: a wide pill, as on a monitor-mounted webcam.
let body = CGRect(x: 196, y: 372, width: 632, height: 300)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 150, cornerHeight: 150, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.5))
ctx.addPath(bodyPath)
ctx.setFillColor(surface1)
ctx.fillPath()
ctx.restoreGState()
clipped(bodyPath) {
    linear([surface1, surface0], from: CGPoint(x: 512, y: 672), to: CGPoint(x: 512, y: 372))
}

// Mount stem and clip.
let stem = CGPath(roundedRect: CGRect(x: 472, y: 262, width: 80, height: 120), cornerWidth: 24, cornerHeight: 24,
                  transform: nil)
ctx.addPath(stem)
ctx.setFillColor(surface0)
ctx.fillPath()
let foot = CGPath(roundedRect: CGRect(x: 372, y: 228, width: 280, height: 56), cornerWidth: 28, cornerHeight: 28,
                  transform: nil)
ctx.addPath(foot)
ctx.setFillColor(surface1)
ctx.fillPath()

// Lens: bezel, mauve→blue ring, dark glass, highlight.
let lensCenter = CGPoint(x: 512, y: 522)
ctx.addPath(circle(lensCenter, 128))
ctx.setFillColor(crust)
ctx.fillPath()
clipped(circle(lensCenter, 112)) {
    linear([mauve, blue], from: CGPoint(x: 400, y: 634), to: CGPoint(x: 624, y: 410))
}
clipped(circle(lensCenter, 84)) {
    radial([surface0, crust], center: CGPoint(x: 494, y: 540), radius: 84)
}
clipped(circle(lensCenter, 40)) {
    radial([lavender.copy(alpha: 0.9)!, blue.copy(alpha: 0.35)!, crust], center: lensCenter, radius: 40)
}
ctx.addPath(circle(CGPoint(x: 478, y: 560), 18))
ctx.setFillColor(text.copy(alpha: 0.85)!)
ctx.fillPath()

// Status LED with glow.
let led = CGPoint(x: 720, y: 600)
clipped(circle(led, 34)) {
    radial([green.copy(alpha: 0.55)!, green.copy(alpha: 0)!], center: led, radius: 34)
}
ctx.addPath(circle(led, 14))
ctx.setFillColor(green)
ctx.fillPath()

// Subtle mic grille dots on the left.
for i in 0..<3 {
    ctx.addPath(circle(CGPoint(x: 280 + CGFloat(i) * 30, y: 522), 7))
}
ctx.setFillColor(overlay0)
ctx.fillPath()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
