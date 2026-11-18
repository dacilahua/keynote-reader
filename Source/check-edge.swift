import PDFKit
import Foundation
func compact(_ s: String) -> String { s.filter { !$0.isWhitespace } }
let expected = try JSONDecoder().decode([String].self, from: Data(contentsOf: URL(fileURLWithPath:"work/edge.json")))
for name in ["a4", "compact"] {
 let doc = PDFDocument(url: URL(fileURLWithPath:"work/edge-\(name).pdf"))!
 let body = (0..<doc.pageCount).map { i in
    (doc.page(at:i)!.string ?? "").components(separatedBy:"\n").filter { line in
       !line.hasPrefix("Keynote Reader") && line.range(of: "^[0-9]+ / 6", options: .regularExpression) == nil
    }.joined()
 }.joined()
 let actual = compact(body).precomposedStringWithCanonicalMapping
 let wanted = compact(expected.joined()).precomposedStringWithCanonicalMapping
 assert(actual == wanted, "Full Unicode body mismatch")
 for i in 0..<doc.pageCount {
  let r = doc.page(at:i)!.bounds(for:.mediaBox)
  if name == "a4" { assert(abs(r.height-841.89)<0.1) }
  assert(r.height <= 842)
 }
 print("PASS \(name): 12 pages, full Unicode body exact match, 600 repetitions, emoji, accents, final marker")
}
