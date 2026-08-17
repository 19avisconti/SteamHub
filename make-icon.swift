// Generates AppIcon.icns from chud.png.
//
//   ./make-icon.sh
//
// The source art is a line drawing that doesn't fill its own canvas, so this crops to the
// drawn area first, then centres it on the standard macOS rounded tile. Without the crop
// the face ends up as a small mark floating in white space.
import AppKit

let root = FileManager.default.currentDirectoryPath
let sourcePath = "\(root)/chud.png"
let outDir = "\(root)/AppIcon.iconset"

guard let source = NSImage(contentsOfFile: sourcePath),
      let sourceCG = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("error: cannot read \(sourcePath)\n".utf8))
    exit(1)
}

// MARK: - Trim to the drawn area

func inkBounds(_ cg: CGImage) -> CGRect {
    let w = cg.width, h = cg.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(.white)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

    var minX = w, minY = h, maxX = 0, maxY = 0
    for y in 0..<h {
        for x in 0..<w {
            let i = (y * w + x) * 4
            let lum = (Int(buf[i]) * 30 + Int(buf[i + 1]) * 59 + Int(buf[i + 2]) * 11) / 100
            if lum < 200 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
    }
    guard minX <= maxX else { return CGRect(x: 0, y: 0, width: w, height: h) }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

let ink = inkBounds(sourceCG)
let art = sourceCG.cropping(to: ink) ?? sourceCG
print("source \(sourceCG.width)x\(sourceCG.height), ink \(Int(ink.width))x\(Int(ink.height)) at \(Int(ink.minX)),\(Int(ink.minY))")

// MARK: - Render one icon

/// Apple's macOS icon grid: on a 1024 canvas the rounded tile is 824 wide with a 185.4
/// corner radius, leaving a 100pt margin the system uses for its own shadow.
let tileRatio: CGFloat = 824.0 / 1024.0
let radiusRatio: CGFloat = 185.4 / 824.0
/// How much of the tile the artwork spans. Enough to read at 32pt without touching corners.
let artRatio: CGFloat = 0.78

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.interpolationQuality = .high

    let tile = (s * tileRatio).rounded()
    let origin = ((s - tile) / 2).rounded()
    let tileRect = CGRect(x: origin, y: origin, width: tile, height: tile)
    let path = CGPath(roundedRect: tileRect,
                      cornerWidth: tile * radiusRatio, cornerHeight: tile * radiusRatio,
                      transform: nil)

    ctx.addPath(path)
    ctx.setFillColor(.white)
    ctx.fillPath()

    // Clip the art to the tile so nothing bleeds past the rounded corners.
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()

    let box = tile * artRatio
    let scale = min(box / ink.width, box / ink.height)
    let aw = ink.width * scale, ah = ink.height * scale
    ctx.draw(art, in: CGRect(x: tileRect.midX - aw / 2, y: tileRect.midY - ah / 2,
                             width: aw, height: ah))
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// MARK: - Write the iconset

try? FileManager.default.removeItem(atPath: outDir)
try! FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

for (base, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
                      (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
    try! render(size: base * scale).write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}
print("wrote \(outDir)")
