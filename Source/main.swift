import AppKit
import PDFKit
import CoreText
import UniformTypeIdentifiers
import ImageIO

struct ReaderError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
enum Quality: Int { case screen, small, original
    var edge: Int { self == .small ? 1200 : 1600 }
    var jpeg: Double { self == .small ? 0.60 : 0.76 }
}
struct Options { var fontSize: CGFloat = 13; var fixedA4 = false; var quality: Quality = .screen }
// Only slide artwork is downsampled; presenter notes remain searchable vector text.
func screenImage(_ slide: CGPDFPage, quality: Quality) throws -> CGImage? {
    if quality == .original { return nil }
    let box = slide.getBoxRect(.cropBox)
    let rotated = abs(slide.rotationAngle) % 180 != 0
    let w = rotated ? box.height : box.width, h = rotated ? box.width : box.height
    guard w > 0, h > 0 else { throw ReaderError(message: "幻灯片尺寸无效。") }
    let scale = CGFloat(quality.edge) / max(w, h)
    let pw = max(1, Int((w * scale).rounded())), ph = max(1, Int((h * scale).rounded()))
    guard let bitmap = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw ReaderError(message: "无法分配压缩图像内存。") }
    let rect = CGRect(x: 0, y: 0, width: pw, height: ph)
    bitmap.setFillColor(NSColor.white.cgColor); bitmap.fill(rect)
    bitmap.interpolationQuality = .high
    bitmap.concatenate(slide.getDrawingTransform(.cropBox, rect: rect, rotate: 0, preserveAspectRatio: true))
    bitmap.drawPDFPage(slide)
    guard let image = bitmap.makeImage() else { throw ReaderError(message: "无法生成幻灯片预览。") }
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { throw ReaderError(message: "无法压缩幻灯片。") }
    CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality.jpeg] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { throw ReaderError(message: "图像编码失败。") }
    // Simple vector slides can be smaller and sharper than JPEG: retain them.
    let vector = NSMutableData()
    var media = box
    if let consumer = CGDataConsumer(data: vector), let ctx = CGContext(consumer: consumer, mediaBox: &media, nil) {
        ctx.beginPDFPage(nil); ctx.drawPDFPage(slide); ctx.endPDFPage(); ctx.closePDF()
        if vector.length <= data.length { return nil }
    }
    guard let provider = CGDataProvider(data: data), let jpeg = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { throw ReaderError(message: "无法读取压缩后的幻灯片。") }
    return jpeg
}
func quoted(_ value: String) -> String {
    "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
}
func script(_ source: String) throws -> NSAppleEventDescriptor {
    var error: NSDictionary?
    guard let s = NSAppleScript(source: source) else { throw ReaderError(message: "无法创建 Keynote 自动化脚本。") }
    let result = s.executeAndReturnError(&error)
    if let error = error {
        let code = error[NSAppleScript.errorNumber] as? Int ?? 0
        if code == -1743 { throw ReaderError(message: "请到系统设置 → 隐私与安全性 → 自动化，允许 Keynote Reader 控制 Keynote，然后重试。") }
        throw ReaderError(message: "Keynote 返回错误（\(code)）：\(error[NSAppleScript.errorMessage] ?? error)。若文稿有密码、缺少字体或弹出提示，请先在 Keynote 中处理后重试。")
    }
    return result
}
func keynotePath() throws -> String {
    for id in ["com.apple.Keynote", "com.apple.iWork.Keynote"] {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return url.path }
    }
    for path in ["/Applications/Keynote Creator Studio.app", "/Applications/Keynote.app"] {
        if FileManager.default.fileExists(atPath: path) { return path }
    }
    throw ReaderError(message: "未找到 Keynote。请先安装并打开一次 Apple Keynote，再导出。")
}
func exportKeynote(_ input: URL, to target: URL, options: Options) throws -> Int {
    let appPath = try keynotePath()
    let fm = FileManager.default
    let temp = fm.temporaryDirectory.appendingPathComponent("KeynoteReader-" + UUID().uuidString, isDirectory: true)
    try fm.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: temp) }
    let copy = temp.appendingPathComponent("WorkingCopy.key")
    try fm.copyItem(at: input, to: copy)
    let slidesURL = temp.appendingPathComponent("slides.pdf")
    // Filter notes with the same skipped-slide rule as the PDF export.
    // Notes are returned as an Apple event list, never parsed by delimiters or OCR.
    let result = try script("""
    with timeout of 600 seconds
        tell application \(quoted(appPath))
            set docRef to open POSIX file \(quoted(copy.path))
            try
                set noteList to {}
                repeat with slideRef in slides of docRef
                    if skipped of slideRef is false then
                        set end of noteList to (presenter notes of slideRef as text)
                    end if
                end repeat
                if (count of noteList) is 0 then error "所有幻灯片均已跳过，没有可导出的内容。" number -2700
                export docRef to POSIX file \(quoted(slidesURL.path)) as PDF with properties {export style:IndividualSlides, all stages:false, skipped slides:false, borders:false, slide numbers:false, include comments:false, PDF image quality:Best}
                close docRef saving no
                return noteList
            on error errText number errNum
                try
                    close docRef saving no
                end try
                error errText number errNum
            end try
        end tell
    end timeout
    """)
    let notes = (0..<result.numberOfItems).map { result.atIndex($0 + 1)?.stringValue ?? "" }
    guard let pdf = CGPDFDocument(slidesURL as CFURL), pdf.numberOfPages > 0 else {
        throw ReaderError(message: "Keynote 没有生成有效的幻灯片 PDF。")
    }
    guard pdf.numberOfPages == notes.count else {
        throw ReaderError(message: "幻灯片与注释数量不一致（\(pdf.numberOfPages) / \(notes.count)），已停止导出以避免错页。")
    }
    let staged = temp.appendingPathComponent("result.pdf")
    let count = try compose(pdf, notes: notes, title: input.deletingPathExtension().lastPathComponent, to: staged, options: options)
    // Atomic replacement; leave existing destination intact if composition fails.
    try Data(contentsOf: staged).write(to: target, options: .atomic)
    return count
}
func attributed(_ text: String, size: CGFloat, color: NSColor = .black) -> NSAttributedString {
    let style = NSMutableParagraphStyle()
    style.lineSpacing = 4
    style.paragraphSpacing = 7
    style.lineBreakMode = .byWordWrapping
    return NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: color, .paragraphStyle: style])
}
func drawText(_ text: NSAttributedString, rect: CGRect, in context: CGContext) {
    let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(text), CFRange(location: 0, length: text.length), CGPath(rect: rect, transform: nil), nil)
    context.textMatrix = .identity
    CTFrameDraw(frame, context)
}
@discardableResult
func compose(_ source: CGPDFDocument, notes: [String], title: String, to output: URL, options: Options) throws -> Int {
    guard source.numberOfPages == notes.count else { throw ReaderError(message: "页数不匹配。") }
    guard let consumer = CGDataConsumer(url: output as CFURL), let context = CGContext(consumer: consumer, mediaBox: nil, [kCGPDFContextTitle as String: title, kCGPDFContextCreator as String: "Keynote Reader"] as CFDictionary) else { throw ReaderError(message: "无法写入 PDF。") }
    let width: CGFloat = 595.28, maxHeight: CGFloat = 841.89, margin: CGFloat = 30
    let imageWidth = width - margin * 2
    let textWidth = width - 92 // Slightly narrower than image for comfortable reading.
    var outputPages = 0
    for index in 0..<source.numberOfPages {
        guard let slide = source.page(at: index + 1) else { throw ReaderError(message: "无法读取幻灯片。") }
        let box = slide.getBoxRect(.cropBox)
        let rotated = abs(slide.rotationAngle) % 180 != 0
        let ratio = rotated ? box.width / box.height : box.height / box.width
        let imageHeight = min(imageWidth * ratio, 500)
        let actualWidth = imageHeight / ratio
        let compressed = try screenImage(slide, quality: options.quality)
        let raw = notes[index].replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let text = attributed(raw, size: options.fontSize)
        let setter = CTFramesetterCreateWithAttributedString(text)
        var offset = 0, first = true
        repeat {
            let top: CGFloat = first ? (52 + imageHeight + (text.length > 0 ? 24 : 0)) : 62
            let available = maxHeight - top - 38
            let remaining = CFRange(location: offset, length: text.length - offset)
            var fit = CFRange()
            let suggested = CTFramesetterSuggestFrameSizeWithConstraints(setter, remaining, nil, CGSize(width: textWidth, height: available), &fit)
            let textHeight = text.length > offset ? min(available, ceil(suggested.height) + 3) : 0
            let height = options.fixedA4 ? maxHeight : min(maxHeight, max(140, top + textHeight + 38))
            var media = CGRect(x: 0, y: 0, width: width, height: height)
            let mediaData = Data(bytes: &media, count: MemoryLayout<CGRect>.size)
            context.beginPDFPage([kCGPDFContextMediaBox as String: mediaData] as CFDictionary)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(media)
            let label = "\(index + 1) / \(source.numberOfPages)" + (first ? "" : "  ·  注释续页")
            drawText(attributed(label, size: 10, color: .darkGray), rect: CGRect(x: margin, y: height - 39, width: imageWidth, height: 20), in: context)
            if first {
                let rect = CGRect(x: (width - actualWidth) / 2, y: height - 52 - imageHeight, width: actualWidth, height: imageHeight)
                context.saveGState()
                context.clip(to: rect)
                if let compressed = compressed {
                    context.interpolationQuality = .high
                    context.draw(compressed, in: rect)
                } else {
                    context.concatenate(slide.getDrawingTransform(.cropBox, rect: rect, rotate: 0, preserveAspectRatio: true))
                    context.drawPDFPage(slide)
                }
                context.restoreGState()
            }
            if offset < text.length {
                let rect = CGRect(x: 46, y: 38, width: textWidth, height: height - top - 38)
                let frame = CTFramesetterCreateFrame(setter, CFRange(location: offset, length: 0), CGPath(rect: rect, transform: nil), nil)
                let visible = CTFrameGetVisibleStringRange(frame)
                guard visible.length > 0 else {
                    context.endPDFPage(); context.closePDF()
                    throw ReaderError(message: "注释分页失败，请尝试较小字号。")
                }
                context.textMatrix = .identity
                CTFrameDraw(frame, context)
                offset += visible.length
            }
            outputPages += 1
            drawText(attributed("Keynote Reader  ·  \(outputPages)", size: 8, color: .gray), rect: CGRect(x: margin, y: 10, width: imageWidth, height: 16), in: context)
            context.endPDFPage()
            first = false
        } while offset < text.length
    }
    context.closePDF()
    return outputPages
}

final class DropView: NSView {
    var onDrop: ((URL) -> Void)?
    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL]) }
    required init?(coder: NSCoder) { fatalError() }
    func file(_ sender: NSDraggingInfo) -> URL? {
        (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?.first(where: { $0.pathExtension.lowercased() == "key" })
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { file(sender) == nil ? [] : .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = file(sender) else { return false }; onDrop?(url); return true
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var status: NSTextField!
    var fileLabel: NSTextField!
    var choose: NSButton!
    var export: NSButton!
    var size: NSPopUpButton!
    var quality: NSPopUpButton!
    var layout: NSSegmentedControl!
    var progress: NSProgressIndicator!
    var selected: URL?
    var busy = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu(); let item = NSMenuItem(); menu.addItem(item)
        let appMenu = NSMenu(); appMenu.addItem(withTitle: "生成测试文稿并导出…", action: #selector(testExport), keyEquivalent: "t"); appMenu.addItem(withTitle: "退出 Keynote Reader", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); item.submenu = appMenu; NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 450), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Keynote Reader · 文稿阅读版"
        let root = DropView(frame: window.contentView!.bounds); window.contentView = root
        root.onDrop = { [weak self] in self?.select($0) }
        func label(_ text: String, _ y: CGFloat, _ font: CGFloat, _ color: NSColor = .labelColor) -> NSTextField {
            let v = NSTextField(wrappingLabelWithString: text); v.font = .systemFont(ofSize: font); v.textColor = color; v.frame = NSRect(x: 36, y: y, width: 548, height: 42); root.addSubview(v); return v
        }
        _ = label("让幻灯片和讲稿，一起好读。", 365, 25)
        _ = label("拖入 .key 文件，自动导出大图、清晰文字的 PDF。", 326, 14, .secondaryLabelColor)
        fileLabel = label("将 Keynote 文稿拖到此窗口", 260, 17)
        choose = NSButton(title: "选择 Keynote…", target: self, action: #selector(pick)); choose.frame = NSRect(x: 36, y: 220, width: 160, height: 32); root.addSubview(choose)
        let hint = label("自动排除跳过的幻灯片 · 演讲者注释按纯文本重排", 198, 11, .secondaryLabelColor); hint.frame.size.height = 18
        layout = NSSegmentedControl(labels: ["紧凑阅读 · 少留白", "固定 A4 · 适合打印"], trackingMode: .selectOne, target: nil, action: nil)
        layout.selectedSegment = 0; layout.frame = NSRect(x: 36, y: 168, width: 380, height: 30); root.addSubview(layout)
        size = NSPopUpButton(frame: NSRect(x: 440, y: 168, width: 144, height: 30)); size.addItems(withTitles: ["注释 11 磅", "注释 13 磅", "注释 15 磅", "注释 18 磅"]); size.selectItem(at: 1); root.addSubview(size)
        quality = NSPopUpButton(frame: NSRect(x: 36, y: 126, width: 420, height: 30))
        quality.addItems(withTitles: ["屏幕清晰 · 推荐，文件更小", "更小文件 · 适合手机分享", "原画质 · 适合放大查看"]); root.addSubview(quality)
        export = NSButton(title: "导出阅读版 PDF…", target: self, action: #selector(save)); export.bezelStyle = .rounded; export.frame = NSRect(x: 36, y: 78, width: 200, height: 36); export.isEnabled = false; root.addSubview(export)
        progress = NSProgressIndicator(frame: NSRect(x: 255, y: 87, width: 20, height: 20)); progress.style = .spinning; progress.isDisplayedWhenStopped = false; root.addSubview(progress)
        status = label("本地处理 · 需安装 Keynote · 首次使用需允许自动化", 15, 12, .secondaryLabelColor)
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        if let pending = selected { select(pending) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !busy }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if busy { status.stringValue = "正在导出，请完成后再退出。"; return .terminateCancel }; return .terminateNow
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if let name = filenames.first { select(URL(fileURLWithPath: name)) }; sender.reply(toOpenOrPrint: .success)
    }
    func select(_ url: URL) {
        guard !busy else { return }
        guard url.pathExtension.lowercased() == "key" else { return }
        selected = url; fileLabel?.stringValue = url.lastPathComponent; export?.isEnabled = true
    }
    @objc func testExport() {
        guard !busy else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.pdf]; panel.nameFieldStringValue = "跳过页测试-阅读版.pdf"
        panel.beginSheetModal(for: window) { result in
            guard result == .OK, let target = panel.url else { return }
            do {
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ReaderFixture-" + UUID().uuidString)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let key = folder.appendingPathComponent("测试文稿.key")
                guard let resource = Bundle.main.url(forResource: "fixture", withExtension: "applescript") else { throw ReaderError(message: "测试资源缺失") }
                let raw = try String(contentsOf: resource, encoding: .utf8)
                let source = raw.replacingOccurrences(of: "on run argv", with: "").replacingOccurrences(of: "end run", with: "").replacingOccurrences(of: "(item 1 of argv)", with: quoted(key.path)).replacingOccurrences(of: "\"/Applications/Keynote Creator Studio.app\"", with: quoted(try keynotePath()))
                _ = try script(source)
                self.select(key)
                self.run(key, to: target)
            } catch {
                self.status.stringValue = error.localizedDescription
            }
        }
    }
    @objc func pick() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "key") ?? .data]; panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { if $0 == .OK, let url = panel.url { self.select(url) } }
    }
    @objc func save() {
        guard let input = selected, !busy else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.pdf]; panel.nameFieldStringValue = input.deletingPathExtension().lastPathComponent + "-阅读版.pdf"
        panel.beginSheetModal(for: window) { result in
            guard result == .OK, let target = panel.url else { return }
            self.run(input, to: target)
        }
    }
    func run(_ input: URL, to output: URL) {
        let options = Options(fontSize: [11, 13, 15, 18][size.indexOfSelectedItem], fixedA4: layout.selectedSegment == 1, quality: Quality(rawValue: quality.indexOfSelectedItem) ?? .screen)
        busy = true; window.standardWindowButton(.closeButton)?.isEnabled = false; choose.isEnabled = false; export.isEnabled = false; layout.isEnabled = false; size.isEnabled = false; quality.isEnabled = false
        progress.startAnimation(nil); status.stringValue = "正在读取 Keynote 并排版…首次运行请允许自动化。大型文稿可能需要几分钟。"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try exportKeynote(input, to: output, options: options) }
            DispatchQueue.main.async {
                self.busy = false; self.window.standardWindowButton(.closeButton)?.isEnabled = true; self.choose.isEnabled = true; self.export.isEnabled = true; self.layout.isEnabled = true; self.size.isEnabled = true; self.quality.isEnabled = true; self.progress.stopAnimation(nil)
                switch result {
                case .success(let count):
                    let bytes = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    self.status.stringValue = "已导出 \(count) 页 · \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)) · PDF 已保存。"
                    NSWorkspace.shared.activateFileViewerSelecting([output])
                case .failure(let error):
                    self.status.stringValue = "导出未完成，可处理提示后重试。"
                    let alert = NSAlert(); alert.messageText = "无法完成导出"; alert.informativeText = error.localizedDescription; alert.beginSheetModal(for: self.window)
                }
            }
        }
    }
}

// CLI shares the exact exporter and compositor used by the application.
let args = CommandLine.arguments
if args.count >= 4 && args[1] == "--export" {
    do {
        let count = try exportKeynote(URL(fileURLWithPath: args[2]), to: URL(fileURLWithPath: args[3]), options: Options(quality: args.contains("--original") ? .original : (args.contains("--small") ? .small : .screen)))
        print("Exported \(count) pages")
    } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
} else if args.count >= 5 && args[1] == "--compose" {
    do {
        guard let pdf = CGPDFDocument(URL(fileURLWithPath: args[2]) as CFURL) else { throw ReaderError(message: "Invalid PDF") }
        let notes = try JSONDecoder().decode([String].self, from: Data(contentsOf: URL(fileURLWithPath: args[3])))
        let count = try compose(pdf, notes: notes, title: "排版测试", to: URL(fileURLWithPath: args[4]), options: Options(fixedA4: args.contains("--a4"), quality: args.contains("--original") ? .original : (args.contains("--small") ? .small : .screen)))
        print("Composed \(count) pages")
    } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate(); app.delegate = delegate; app.run()
}
