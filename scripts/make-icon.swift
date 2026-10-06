import AppKit
let folder = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for retina in [false, true] {
        let pixels = size * (retina ? 2 : 1)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let n = CGFloat(pixels)
        MinutesLogo.draw(size: n)
        NSGraphicsContext.restoreGraphicsState()
        let suffix = retina ? "@2x" : ""
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(folder)/icon_\(size)x\(size)\(suffix).png"))
    }
}

// Package PNG representations directly into an ICNS container.
func lengthBytes(_ value: Int) -> Data {
    Data([UInt8((value >> 24) & 255), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)])
}
var body = Data()
for (kind, file) in [("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"),
                     ("icp6", "icon_32x32@2x.png"), ("ic07", "icon_128x128.png"),
                     ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"),
                     ("ic10", "icon_512x512@2x.png")] {
    let data = try Data(contentsOf: URL(fileURLWithPath: "\(folder)/\(file)"))
    body.append(Data(kind.utf8)); body.append(lengthBytes(data.count + 8)); body.append(data)
}
var icon = Data("icns".utf8)
icon.append(lengthBytes(body.count + 8)); icon.append(body)
try icon.write(to: URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "Resources/AppIcon.icns"))
