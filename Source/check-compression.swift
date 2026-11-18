import PDFKit
import Foundation
let original = try Data(contentsOf: URL(fileURLWithPath:"work/compression-original.pdf")).count
let screen = try Data(contentsOf: URL(fileURLWithPath:"work/compression-screen.pdf")).count
let small = try Data(contentsOf: URL(fileURLWithPath:"work/compression-small.pdf")).count
assert(screen < original / 4)
assert(small < screen)
for name in ["original", "screen", "small"] {
 let doc = PDFDocument(url: URL(fileURLWithPath:"work/compression-\(name).pdf"))!
 assert(doc.pageCount == 1)
 let text = (doc.string ?? "").filter { !$0.isWhitespace }
 assert(text.contains("这段演讲者注释保留为矢量文字。"))
 assert(text.contains("阅读版压缩测试：图片变小，讲稿完整。"))
}
print("PASS compression: original \(original), screen \(screen), small \(small) bytes; notes searchable")
