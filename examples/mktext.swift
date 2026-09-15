// mktext: render a single line of text to a PNG via CoreText.
// Usage: mktext <out.png> <size:WxH> <font_size> <fg_hex> <bg_hex|none> <x|c> <y|c> <text...>
// 'c' centers on that axis; bg 'none' leaves the background transparent.
// The font auto-shrinks until the line fits (width - 100) px.
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let out = args[1]
let parts = args[2].split(separator: "x").map { Int($0)! }
let (W, H) = (parts[0], parts[1])
var fontSize = CGFloat(Int(args[3])!)
let hex = args[4]
let bghex = args[5]
let px = args[6] == "c" ? -1 : CGFloat(Float(args[6])!)
let py = args[7] == "c" ? -1 : CGFloat(Float(args[7])!)
let text = args[8...].joined(separator: " ")

func channel(_ s : String, _ i : Int) -> CGFloat {
  CGFloat(strtoul(String(s.dropFirst(3 + 2 * i).prefix(2)), nil, 16)) / 255
}
let r = channel(hex, 0), g = channel(hex, 1), b = channel(hex, 2)

func makeLine(_ size : CGFloat) -> CTLine {
  let font = CTFontCreateWithName("PingFang SC" as CFString, size, nil)
  let attr = [kCTFontAttributeName: font,
              kCTForegroundColorAttributeName: CGColor(red: r, green: g, blue: b, alpha: 1)] as CFDictionary
  let attributed = CFAttributedStringCreate(nil, text as CFString, attr)!
  return CTLineCreateWithAttributedString(attributed)
}

var line = makeLine(fontSize)
var bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
let maxWidth = CGFloat(W) - 100
if bounds.width > maxWidth {
  fontSize = fontSize * maxWidth / bounds.width
  line = makeLine(fontSize)
  bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
}

var x = px
if x < 0 { x = (CGFloat(W) - CGFloat(bounds.width)) / 2 }
var y = py
if y < 0 { y = (CGFloat(H) - fontSize) / 2 }

let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
if bghex != "none" {
  let br = channel(bghex, 0), bgg = channel(bghex, 1), bbb = channel(bghex, 2)
  ctx.setFillColor(CGColor(red: br, green: bgg, blue: bbb, alpha: 1))
  ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(W), height: CGFloat(H)))
}
ctx.textPosition = CGPoint(x: x, y: CGFloat(H) - y - fontSize * 0.88)
CTLineDraw(line, ctx)
let img = ctx.makeImage()!

let url = URL(fileURLWithPath: out) as CFURL
let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
