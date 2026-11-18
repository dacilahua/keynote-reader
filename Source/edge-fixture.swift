import AppKit
import CoreText
let out = URL(fileURLWithPath: "work/edge.pdf")
var box = CGRect(x:0, y:0, width:1920, height:1080)
let ctx = CGContext(out as CFURL, mediaBox:&box, nil)!
for _ in 1...6 { ctx.beginPDFPage(nil); ctx.setFillColor(NSColor.systemBlue.cgColor); ctx.fill(box); ctx.endPDFPage() }
ctx.closePDF()
let notes = ["", "\n\n", "短注释：中文 😀 e\u{301} & <tag> \\\"", String(repeating:"长段落中文 Unicode 😀 end. ", count:600), "\tTab\r\nCRLF\rCR", "LAST-MARKER"]
try JSONEncoder().encode(notes).write(to: URL(fileURLWithPath:"work/edge.json"))
