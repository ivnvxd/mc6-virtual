// Renders packaging/icon/AppIcon.svg and AppIcon-small.svg into Resources/AppIcon.icns: swift scripts/make-icon.swift
// NSImage draws the SVG files, and iconutil packs the PNGs. Sizes of 32 px and less use the small drawing.
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let set = FileManager.default.temporaryDirectory.appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let source = root.appending(path: pixels <= 32 ? "packaging/icon/AppIcon-small.svg" : "packaging/icon/AppIcon.svg")
        guard let image = NSImage(contentsOf: source) else { fatalError("Cannot read \(source.path)") }
        let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        let png = NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
        try png.write(to: set.appending(path: "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", "-o", root.appending(path: "Resources/AppIcon.icns").path, set.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote Resources/AppIcon.icns")
