import AppKit
import CoreGraphics
let size = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let colors = [CGColor(red: 0.02, green: 0.40, blue: 0.38, alpha: 1), CGColor(red: 0.07, green: 0.66, blue: 0.56, alpha: 1)]
let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 1024, y: 1024), options: [])
ctx.setFillColor(CGColor(gray: 1, alpha: 0.08))
ctx.fillEllipse(in: CGRect(x: 570, y: 620, width: 540, height: 540))
ctx.setFillColor(CGColor(gray: 1, alpha: 1))
ctx.addPath(CGPath(roundedRect: CGRect(x: 240, y: 205, width: 550, height: 650), cornerWidth: 80, cornerHeight: 80, transform: nil));ctx.fillPath()
ctx.setFillColor(CGColor(red: 0.72, green: 0.93, blue: 0.87, alpha: 1))
ctx.fill(CGRect(x: 240, y: 285, width: 64, height: 490))
ctx.setStrokeColor(CGColor(red: 0.12, green: 0.52, blue: 0.46, alpha: 1))
ctx.setLineCap(.round);ctx.setLineWidth(28)
ctx.move(to: CGPoint(x: 392, y: 377));ctx.addLine(to: CGPoint(x: 650, y: 377));ctx.strokePath()
ctx.move(to: CGPoint(x: 392, y: 462));ctx.addLine(to: CGPoint(x: 570, y: 462));ctx.strokePath()
let leaf = CGMutablePath()
leaf.move(to: CGPoint(x: 460, y: 580));leaf.addCurve(to: CGPoint(x: 662, y: 733), control1: CGPoint(x: 425, y: 724), control2: CGPoint(x: 564, y: 758))
leaf.addCurve(to: CGPoint(x: 460, y: 580), control1: CGPoint(x: 681, y: 595), control2: CGPoint(x: 573, y: 556))
ctx.setFillColor(CGColor(red: 0.07, green: 0.59, blue: 0.47, alpha: 1));ctx.addPath(leaf);ctx.fillPath()
ctx.setStrokeColor(CGColor(red: 0.05, green: 0.43, blue: 0.37, alpha: 1));ctx.setLineWidth(16)
ctx.move(to: CGPoint(x: 445, y: 565));ctx.addQuadCurve(to: CGPoint(x: 614, y: 696), control: CGPoint(x: 512, y: 656));ctx.strokePath()
let image = ctx.makeImage()!
let bitmap = NSBitmapImageRep(cgImage: image)
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
