// Original Pocket Band AI artwork. Regenerate PNG and editable SVG from the same paths:
// swift Scripts/generate-app-icon.swift
import AppKit

struct Palette {
    let name, background, pages, fold, pocket, face, seam: String
}
let palettes = [
    Palette(name: "Light", background: "B4EFFF", pages: "FFFFFF", fold: "DAF5FC", pocket: "007FA3", face: "FFFFFF", seam: "57CAE4"),
    Palette(name: "Dark", background: "122F3C", pages: "F3FBFD", fold: "C6EAF3", pocket: "5FD2EC", face: "12323F", seam: "2491AE"),
    Palette(name: "Tinted", background: "E5E5E5", pages: "FFFFFF", fold: "D0D0D0", pocket: "454545", face: "FFFFFF", seam: "959595")
]
func color(_ hex: String) -> CGColor {
    let value = UInt32(hex, radix: 16)!
    return CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [
        CGFloat((value >> 16) & 255) / 255, CGFloat((value >> 8) & 255) / 255,
        CGFloat(value & 255) / 255, 1
    ])!
}
func svgPath(_ path: CGPath) -> String {
    var result = ""
    path.applyWithBlock { element in
        let p = element.pointee.points
        switch element.pointee.type {
        case .moveToPoint: result += "M\(p[0].x) \(p[0].y) "
        case .addLineToPoint: result += "L\(p[0].x) \(p[0].y) "
        case .addQuadCurveToPoint: result += "Q\(p[0].x) \(p[0].y) \(p[1].x) \(p[1].y) "
        case .addCurveToPoint: result += "C\(p[0].x) \(p[0].y) \(p[1].x) \(p[1].y) \(p[2].x) \(p[2].y) "
        case .closeSubpath: result += "Z "
        @unknown default: break
        }
    }
    return result
}
for palette in palettes {
    let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
                            bytesPerRow: 4096, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.translateBy(x: 0, y: 1024); context.scaleBy(x: 1, y: -1)
    var elements = ["<rect width=\"1024\" height=\"1024\" fill=\"#\(palette.background)\"/>"]
    context.setFillColor(color(palette.background)); context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    func fill(_ path: CGPath, _ hex: String) {
        context.addPath(path); context.setFillColor(color(hex)); context.fillPath()
        elements.append("<path d=\"\(svgPath(path))\" fill=\"#\(hex)\"/>")
    }
    func stroke(_ path: CGPath, _ hex: String, _ width: CGFloat) {
        context.addPath(path); context.setStrokeColor(color(hex)); context.setLineWidth(width)
        context.setLineCap(.round); context.setLineJoin(.round); context.strokePath()
        elements.append("<path d=\"\(svgPath(path))\" fill=\"none\" stroke=\"#\(hex)\" stroke-width=\"\(width)\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>")
    }
    // Two open pages: a soft center fold, readable even at home-screen size.
    let left = CGMutablePath()
    left.move(to: CGPoint(x: 512, y: 278))
    left.addCurve(to: CGPoint(x: 238, y: 218), control1: CGPoint(x: 432, y: 216), control2: CGPoint(x: 334, y: 192))
    left.addQuadCurve(to: CGPoint(x: 218, y: 247), control: CGPoint(x: 218, y: 222))
    left.addLine(to: CGPoint(x: 218, y: 570)); left.addLine(to: CGPoint(x: 512, y: 626)); left.closeSubpath()
    fill(left, palette.pages)
    var mirror = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 1024, ty: 0)
    fill(left.copy(using: &mirror)!, palette.pages)
    let fold = CGMutablePath(); fold.move(to: CGPoint(x: 512, y: 282)); fold.addLine(to: CGPoint(x: 512, y: 510))
    stroke(fold, palette.fold, 14)
    // A pocket wraps the lower pages. No SF Symbol is used in this brand mark.
    let pocket = CGMutablePath()
    pocket.move(to: CGPoint(x: 200, y: 413))
    pocket.addQuadCurve(to: CGPoint(x: 234, y: 384), control: CGPoint(x: 200, y: 376))
    pocket.addQuadCurve(to: CGPoint(x: 512, y: 458), control: CGPoint(x: 392, y: 402))
    pocket.addQuadCurve(to: CGPoint(x: 790, y: 384), control: CGPoint(x: 632, y: 402))
    pocket.addQuadCurve(to: CGPoint(x: 824, y: 413), control: CGPoint(x: 824, y: 376))
    pocket.addLine(to: CGPoint(x: 824, y: 677))
    pocket.addQuadCurve(to: CGPoint(x: 772, y: 754), control: CGPoint(x: 824, y: 727))
    pocket.addLine(to: CGPoint(x: 552, y: 844))
    pocket.addQuadCurve(to: CGPoint(x: 472, y: 844), control: CGPoint(x: 512, y: 860))
    pocket.addLine(to: CGPoint(x: 252, y: 754))
    pocket.addQuadCurve(to: CGPoint(x: 200, y: 677), control: CGPoint(x: 200, y: 727)); pocket.closeSubpath()
    fill(pocket, palette.pocket)
    for x in [CGFloat(398), CGFloat(596)] {
        fill(CGPath(roundedRect: CGRect(x: x, y: 548, width: 30, height: 48), cornerWidth: 15, cornerHeight: 15, transform: nil), palette.face)
    }
    let smile = CGMutablePath(); smile.move(to: CGPoint(x: 459, y: 641))
    smile.addCurve(to: CGPoint(x: 565, y: 641), control1: CGPoint(x: 486, y: 675), control2: CGPoint(x: 538, y: 675))
    stroke(smile, palette.face, 18)
    let seam = CGMutablePath(); seam.move(to: CGPoint(x: 279, y: 710)); seam.addLine(to: CGPoint(x: 492, y: 796))
    seam.addQuadCurve(to: CGPoint(x: 532, y: 796), control: CGPoint(x: 512, y: 804)); seam.addLine(to: CGPoint(x: 745, y: 710))
    stroke(seam, palette.seam, 9)
    let image = NSBitmapImageRep(cgImage: context.makeImage()!)
    try image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-\(palette.name).png"))
    let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1024\" height=\"1024\" viewBox=\"0 0 1024 1024\">" + elements.joined() + "</svg>"
    try svg.write(toFile: "Documentation/Brand/AppIcon-\(palette.name).svg", atomically: true, encoding: .utf8)
}
