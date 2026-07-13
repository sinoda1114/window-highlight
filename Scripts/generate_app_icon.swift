import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources", isDirectory: true)
let iconset = resources.appendingPathComponent("WindowHighlight.iconset", isDirectory: true)

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

struct IconOutput {
    let fileName: String
    let size: Int
}

let outputs = [
    IconOutput(fileName: "icon_16x16.png", size: 16),
    IconOutput(fileName: "icon_16x16@2x.png", size: 32),
    IconOutput(fileName: "icon_32x32.png", size: 32),
    IconOutput(fileName: "icon_32x32@2x.png", size: 64),
    IconOutput(fileName: "icon_128x128.png", size: 128),
    IconOutput(fileName: "icon_128x128@2x.png", size: 256),
    IconOutput(fileName: "icon_256x256.png", size: 256),
    IconOutput(fileName: "icon_256x256@2x.png", size: 512),
    IconOutput(fileName: "icon_512x512.png", size: 512),
    IconOutput(fileName: "icon_512x512@2x.png", size: 1024)
]

func drawIcon(size: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let scale = CGFloat(size) / 1024.0
    func r(_ value: CGFloat) -> CGFloat { value * scale }

    let canvas = NSRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size))
    NSColor.clear.setFill()
    canvas.fill()

    let outer = NSBezierPath(
        roundedRect: canvas.insetBy(dx: r(54), dy: r(54)),
        xRadius: r(210),
        yRadius: r(210)
    )
    NSGradient(
        colors: [
            NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.16, alpha: 1),
            NSColor(calibratedRed: 0.17, green: 0.11, blue: 0.30, alpha: 1)
        ]
    )?.draw(in: outer, angle: 315)

    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -r(18))
    shadow.shadowBlurRadius = r(34)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.set()

    let inactiveWindow = NSBezierPath(
        roundedRect: NSRect(x: r(240), y: r(325), width: r(560), height: r(380)),
        xRadius: r(50),
        yRadius: r(50)
    )
    NSColor(calibratedRed: 0.23, green: 0.25, blue: 0.35, alpha: 0.72).setFill()
    inactiveWindow.fill()

    NSGraphicsContext.current?.restoreGraphicsState()
    NSGraphicsContext.current?.saveGraphicsState()

    let activeRect = NSRect(x: r(170), y: r(245), width: r(660), height: r(455))
    let activeWindow = NSBezierPath(roundedRect: activeRect, xRadius: r(62), yRadius: r(62))
    NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.09, alpha: 1).setFill()
    activeWindow.fill()

    let titleBar = NSBezierPath(
        roundedRect: NSRect(x: activeRect.minX, y: activeRect.maxY - r(112), width: activeRect.width, height: r(112)),
        xRadius: r(62),
        yRadius: r(62)
    )
    NSColor(calibratedRed: 0.15, green: 0.16, blue: 0.22, alpha: 1).setFill()
    titleBar.fill()

    for (index, color) in [
        NSColor(calibratedRed: 1.00, green: 0.31, blue: 0.34, alpha: 1),
        NSColor(calibratedRed: 1.00, green: 0.76, blue: 0.22, alpha: 1),
        NSColor(calibratedRed: 0.25, green: 0.82, blue: 0.38, alpha: 1)
    ].enumerated() {
        color.setFill()
        NSBezierPath(
            ovalIn: NSRect(
                x: activeRect.minX + r(58) + CGFloat(index) * r(54),
                y: activeRect.maxY - r(74),
                width: r(28),
                height: r(28)
            )
        ).fill()
    }

    let highlight = NSBezierPath(roundedRect: activeRect.insetBy(dx: r(-30), dy: r(-30)), xRadius: r(82), yRadius: r(82))
    highlight.lineWidth = r(58)
    NSColor(calibratedRed: 1.00, green: 0.00, blue: 0.82, alpha: 1).setStroke()
    highlight.stroke()

    let innerHighlight = NSBezierPath(roundedRect: activeRect.insetBy(dx: r(-10), dy: r(-10)), xRadius: r(70), yRadius: r(70))
    innerHighlight.lineWidth = r(16)
    NSColor(calibratedRed: 0.20, green: 0.78, blue: 1.00, alpha: 1).setStroke()
    innerHighlight.stroke()

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "WindowHighlightIcon", code: 1)
    }

    try png.write(to: url)
}

for output in outputs {
    try writePNG(drawIcon(size: output.size), to: iconset.appendingPathComponent(output.fileName))
}

try writePNG(drawIcon(size: 1024), to: resources.appendingPathComponent("WindowHighlight.png"))
