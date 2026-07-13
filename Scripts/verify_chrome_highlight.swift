import AppKit
import CoreGraphics
import Foundation
import ImageIO

func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}

func number(_ value: Any?) -> CGFloat? {
    switch value {
    case let value as CGFloat:
        return value
    case let value as Double:
        return CGFloat(value)
    case let value as Int:
        return CGFloat(value)
    case let value as NSNumber:
        return CGFloat(truncating: value)
    default:
        return nil
    }
}

guard let chrome = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.google.Chrome" }) else {
    fail("Google Chrome is not running")
}

chrome.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
Thread.sleep(forTimeInterval: 1.0)

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
guard let chromeWindow = windows.first(where: { info in
    guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
          pid == chrome.processIdentifier,
          let layer = info[kCGWindowLayer as String] as? Int,
          layer == 0,
          let bounds = info[kCGWindowBounds as String] as? [String: Any],
          let width = number(bounds["Width"]),
          let height = number(bounds["Height"])
    else { return false }
    return width > 180 && height > 140
}) else {
    fail("Chrome window not found")
}

guard let bounds = chromeWindow[kCGWindowBounds as String] as? [String: Any],
      let x = number(bounds["X"]).map(Int.init),
      let y = number(bounds["Y"]).map(Int.init),
      let width = number(bounds["Width"]).map(Int.init),
      let height = number(bounds["Height"]).map(Int.init)
else {
    fail("Chrome window bounds unreadable")
}

let screenshotURL = URL(fileURLWithPath: "/tmp/window-highlight-chrome-e2e.png")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
task.arguments = ["-x", screenshotURL.path]
try task.run()
task.waitUntilExit()
if task.terminationStatus != 0 {
    fail("screencapture failed")
}

guard let source = CGImageSourceCreateWithURL(screenshotURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let dataProvider = image.dataProvider,
      let data = dataProvider.data,
      let bytes = CFDataGetBytePtr(data)
else {
    fail("screenshot unreadable")
}

let bytesPerRow = image.bytesPerRow
let bytesPerPixel = image.bitsPerPixel / 8
let imageWidth = image.width
let imageHeight = image.height

func isHighlightPixel(_ px: Int, _ py: Int) -> Bool {
    guard px >= 0, py >= 0, px < imageWidth, py < imageHeight else {
        return false
    }

    let offset = py * bytesPerRow + px * bytesPerPixel
    if offset + 2 >= CFDataGetLength(data) {
        return false
    }

    let r = Int(bytes[offset])
    let g = Int(bytes[offset + 1])
    let b = Int(bytes[offset + 2])
    let magenta = r > 210 && g < 90 && b > 160
    let orange = r > 220 && g > 90 && g < 190 && b < 80
    let cyan = r < 90 && g > 170 && b > 200
    let blue = r < 80 && g < 130 && b > 180
    return magenta || orange || cyan || blue
}

var hits = 0
for px in max(0, x - 32)..<min(imageWidth, x + width + 32) {
    for delta in -16...16 {
        if isHighlightPixel(px, y + delta) { hits += 1 }
        if isHighlightPixel(px, y + height + delta) { hits += 1 }
    }
}
for py in max(0, y - 32)..<min(imageHeight, y + height + 32) {
    for delta in -16...16 {
        if isHighlightPixel(x + delta, py) { hits += 1 }
        if isHighlightPixel(x + width + delta, py) { hits += 1 }
    }
}

print("Chrome frame_top_left=\(x),\(y),\(width)x\(height) highlight_hits=\(hits) screenshot=\(screenshotURL.path)")
if hits < 350 {
    fail("Chrome highlight not detected around active Chrome window")
}
