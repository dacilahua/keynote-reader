import AppKit
import PDFKit
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let doc = PDFDocument(url: url)!
var all = ""
for i in 0..<doc.pageCount {
 let page = doc.page(at:i)!
 let bounds = page.bounds(for: .mediaBox)
 print("page \(i+1): \(bounds.width) x \(bounds.height)")
 all += page.string ?? ""
 let img = page.thumbnail(of: NSSize(width: bounds.width * 1.5, height: bounds.height * 1.5), for: .mediaBox)
 let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
 try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "work/page-\(i+1).png"))
}
try all.write(toFile: "work/extracted.txt", atomically: true, encoding: .utf8)
assert(all.contains("END-OF-LONG-NOTES-完"))
for i in 1...55 { assert(all.components(separatedBy: "第\(i)段：").count == 2, "Missing or duplicated paragraph \(i)") }
assert(!all.contains("HIDDEN-"))
assert((doc.page(at:0)?.string ?? "").contains("这是从 Keynote"))
assert((doc.page(at:1)?.string ?? "").contains("第1段："))
assert(doc.pageCount == 5)
print("PASS: 55 paragraphs, terminal marker, 5 pages; hidden slides excluded")
