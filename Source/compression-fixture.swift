import AppKit
import CoreText
// Dense, high-resolution synthetic artwork with small text and fine lines.
let w = 3200, h = 1800
let ctx = CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
let ptr = ctx.data!.assumingMemoryBound(to:UInt8.self)
var seed: UInt32 = 42
for y in 0..<h { for x in 0..<w {
 seed = 1664525 &* seed &+ 1013904223
 let noise = Int((seed >> 24) & 31)
 let p = y * ctx.bytesPerRow + x * 4
 ptr[p] = UInt8(min(255, 25 + x * 150 / w + noise)); ptr[p+1] = UInt8(min(255,50 + y * 155 / h + noise)); ptr[p+2] = UInt8(175 + noise); ptr[p+3] = 255
}}
let raster = ctx.makeImage()!
var media = CGRect(x:0,y:0,width:1920,height:1080)
let pdf = CGContext(URL(fileURLWithPath:"work/compression-input.pdf") as CFURL,mediaBox:&media,nil)!
pdf.beginPDFPage(nil); pdf.draw(raster,in:media)
pdf.setFillColor(NSColor.white.cgColor); pdf.fill(CGRect(x:90,y:100,width:1740,height:480))
let lines = ["屏幕阅读清晰度测试 · Keynote Reader", "手机与电脑阅读，注释仍可选择和复制。", "小字号测试：中文 English 0123456789", "细节：图表线条、渐变、照片纹理"]
for (i,t) in lines.enumerated() {
 let size:CGFloat = [60,40,24,32][i]
 let a = NSAttributedString(string:t,attributes:[.font:NSFont.systemFont(ofSize:size),.foregroundColor:NSColor.black])
 pdf.textPosition = CGPoint(x:140,y:500-CGFloat(i)*100); CTLineDraw(CTLineCreateWithAttributedString(a),pdf)
}
pdf.endPDFPage(); pdf.closePDF()
try JSONEncoder().encode(["这段演讲者注释保留为矢量文字。中文 English 😀 1234567890。\n阅读版压缩测试：图片变小，讲稿完整。"]).write(to:URL(fileURLWithPath:"work/compression-notes.json"))
