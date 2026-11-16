import Cocoa

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
    checks += 1
}

check(CodeBlockDetector.codeBody(in: "```swift\n    print(\"你好 👋\")\n```" ) == "    print(\"你好 👋\")\n", "Unicode, indentation and final newline")
check(CodeBlockDetector.codeBody(in: "```\n\n  value  \n\n```") == "\n  value  \n\n", "Blank lines and trailing spaces")
check(CodeBlockDetector.codeBody(in: "```\n\n```") == "\n", "Empty line")
check(CodeBlockDetector.codeBody(in: "```swift\nlet a = 1") == nil, "Unclosed fence")

let app = NSApplication.shared
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 520), styleMask: [.titled], backing: .buffered, defer: false)
let scroll = NSScrollView(frame: window.contentView!.bounds)
scroll.hasVerticalScroller = true
window.contentView = scroll
let editor = EditTextView(frame: NSRect(x: 0, y: 0, width: 620, height: 520))
editor.isVerticallyResizable = true
editor.isHorizontallyResizable = false
editor.autoresizingMask = [.width]
editor.minSize = NSSize(width: 0, height: 520)
editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
editor.textContainerInset = NSSize(width: 20, height: 12)
editor.font = UserDefaultsManagement.noteFont
scroll.documentView = editor
let manager = LayoutManager()
let container = editor.textContainer!
container.lineFragmentPadding = 10
container.widthTracksTextView = true
let storage = editor.textStorage!
storage.removeLayoutManager(editor.layoutManager!)
manager.addTextContainer(container)
storage.addLayoutManager(manager)
manager.delegate = manager
let processor = TextStorageProcessor()
processor.editor = editor
manager.processor = processor
let note = Note()
editor.note = note
let detector = CodeBlockDetector()

func load(_ text: String, collapsed: Bool = false) {
    storage.setAttributedString(NSAttributedString(string: text, attributes: [.font: UserDefaultsManagement.noteFont]))
    note.codeBlockRangesCache = detector.findCodeBlocks(in: storage)
    if collapsed {
        let ns = text as NSString
        for range in note.codeBlockRangesCache! {
            for pos in [range.location, NSMaxRange(range) - 1] {
                let line = ns.lineRange(for: NSRange(location: pos, length: 0))
                storage.addAttributes([NotesTextProcessor.collapsedCodeFence: true, NotesTextProcessor.concealedSyntaxHidden: true], range: line)
            }
        }
    }
    manager.invalidateLayout(forCharacterRange: NSRange(location: 0, length: storage.length), actualCharacterRange: nil)
    manager.ensureLayout(for: container)
    editor.updateCodeBlockCopyButtons()
}

let fixture = "Code snippets\n\n```swift\n    print(\"Hello, 世界 👋\")\n```\n\n```python\ndef greet(name):\n    return f\"Hello, {name}\"\n```\n"
load(fixture)
check(editor.codeBlockCopyButtons.count == 2, "Two visible buttons")
for (index, range) in note.codeBlockRangesCache!.enumerated() {
    let button = editor.codeBlockCopyButtons[index]
    let bodyIndex = (fixture as NSString).lineRange(for: NSRange(location: range.location, length: 0)).upperBound
    let glyph = manager.glyphIndexForCharacter(at: bodyIndex)
    let line = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y)
    check(button.frame.maxY <= line.minY, "Button must not overlap code")
}
window.makeFirstResponder(editor)
editor.setSelectedRange(NSRange(location: 27, length: 4))
let selection = editor.selectedRange()
let pasteboard = NSPasteboard.general
let saved = pasteboard.pasteboardItems?.map { item -> [NSPasteboard.PasteboardType: Data] in
    var values: [NSPasteboard.PasteboardType: Data] = [:]
    for type in item.types { values[type] = item.data(forType: type) }
    return values
} ?? []
defer {
    pasteboard.clearContents()
    let items = saved.map { values -> NSPasteboardItem in
        let item = NSPasteboardItem()
        for (type, data) in values { item.setData(data, forType: type) }
        return item
    }
    pasteboard.writeObjects(items)
}
let button = editor.codeBlockCopyButtons[0]
check(button.title.isEmpty && button.imagePosition == .imageOnly, "Icon-only copy button")
check(button.toolTip == NSLocalizedString("Copy code", comment: "Code block copy button"), "Copy tooltip")
func mouseEvent(at point: NSPoint) -> NSEvent {
    NSEvent.mouseEvent(with: .mouseMoved, location: editor.convert(point, to: nil),
                       modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                       context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
}
let onButton = mouseEvent(at: NSPoint(x: button.frame.midX, y: button.frame.midY))
for _ in 0..<5 {
    NSCursor.iBeam.set()
    editor.mouseMoved(with: onButton)
    check(NSCursor.current == .pointingHand, "Parent mouse tracking must not overwrite the button cursor")
    NSCursor.iBeam.set()
    editor.cursorUpdate(with: onButton)
    check(NSCursor.current == .pointingHand, "Parent cursor update must not overwrite the button cursor")
}
let outsideButton = mouseEvent(at: NSPoint(x: button.frame.minX - 5, y: button.frame.midY))
check(!editor.updateCodeBlockCopyCursor(with: outsideButton), "Only the button hit area claims the hand cursor")
NSCursor.iBeam.set()
editor.mouseMoved(with: outsideButton)
check(NSCursor.current == .iBeam, "Text retains its editing cursor outside the button")
button.performClick(nil)
check(pasteboard.string(forType: .string) == "    print(\"Hello, 世界 👋\")\n", "Native button copies only live code")
check(editor.selectedRange() == selection && window.firstResponder === editor, "Copy preserves selection and focus")
let checkmark = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
    .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .regular))
check(button.image?.tiffRepresentation == checkmark?.tiffRepresentation && button.image != nil,
      "Copy success changes the icon to a checkmark")
check(button.title.isEmpty, "Success feedback stays icon-only")

let second = editor.codeBlockCopyButtons[1]
second.performClick(nil)
check(pasteboard.string(forType: .string) == "def greet(name):\n    return f\"Hello, {name}\"\n", "Each button copies its own block")
storage.replaceCharacters(in: NSRange(location: 27, length: 1), with: "X")
pasteboard.clearContents()
pasteboard.setString("sentinel", forType: .string)
button.performClick(nil)
check(pasteboard.string(forType: .string) == "sentinel", "Reject stale text before repaint")
load(fixture)
// A queued control from the previous note must never copy stale content.
editor.note = Note()
pasteboard.clearContents()
pasteboard.setString("sentinel", forType: .string)
button.performClick(nil)
check(pasteboard.string(forType: .string) == "sentinel", "Reject stale note button")
editor.note = note
load(fixture, collapsed: true)
check(editor.codeBlockCopyButtons.count == 2, "Buttons remain with concealed fences")
for (index, range) in note.codeBlockRangesCache!.enumerated() {
    let bodyIndex = (fixture as NSString).lineRange(for: NSRange(location: range.location, length: 0)).upperBound
    let line = manager.lineFragmentRect(forGlyphAt: manager.glyphIndexForCharacter(at: bodyIndex), effectiveRange: nil)
    check(editor.codeBlockCopyButtons[index].frame.maxY <= line.minY + editor.textContainerOrigin.y, "Concealed toolbar does not overlap code")
}
for range in note.codeBlockRangesCache! {
    let opening = (fixture as NSString).lineRange(for: NSRange(location: range.location, length: 0))
    let newline = NSMaxRange(opening) - 1
    let header = manager.lineFragmentRect(forGlyphAt: manager.glyphIndexForCharacter(at: newline), effectiveRange: nil)
    check(header.height == LayoutManager.codeBlockHeaderHeight, "Concealed header has exactly one toolbar row")
}
let oldX = editor.codeBlockCopyButtons[0].frame.minX
editor.setFrameSize(NSSize(width: 440, height: 520))
manager.ensureLayout(for: container)
editor.updateCodeBlockCopyButtons()
check(editor.codeBlockCopyButtons[0].frame.minX < oldX, "Button follows window resize")
load("Intro\n\n" + fixture)
check(editor.codeBlockCopyButtons[0].blockRange.location == note.codeBlockRangesCache![0].location, "Button follows inserted text")
let longNote = (0..<30).map { "Section \($0)\n\n```swift\nprint(\($0))\n```\n\n" }.joined()
load(longNote, collapsed: true)
editor.setFrameSize(NSSize(width: 440, height: manager.usedRect(for: container).maxY + 30))
editor.scroll(NSPoint(x: 0, y: 650))
editor.updateCodeBlockCopyButtons()
check(!editor.codeBlockCopyButtons.isEmpty, "Buttons appear after scrolling")
check(editor.codeBlockCopyButtons.allSatisfy { $0.frame.intersects(editor.visibleRect) }, "Only visible headers have controls")
check(editor.codeBlockCopyButtons[0].blockRange.location > 0, "Scrolled controls point at later blocks")
editor.scroll(.zero)
editor.setFrameSize(NSSize(width: 440, height: 520))
editor.preview = true
editor.updateCodeBlockCopyButtons()
check(editor.codeBlockCopyButtons.isEmpty, "No editor controls in preview")
editor.preview = false
load("A note without any code")
check(editor.codeBlockCopyButtons.isEmpty, "Remove deleted blocks")
let blocksFixture = "# 一级标题 👋\n\n## 二级标题 ##\n\n普通段落第一行\n同一段落第二行\n\n- 列表条目\n- [ ] 待办事项\n\n> 引用文字\n\n另一种标题\n======\n\n```swift\n    print(\"你好\")\n```\n\n最后一段"
let blockText = blocksFixture as NSString
let document = NSRange(location: 0, length: blockText.length)
func selectAllAction() {
    check(NSApp.sendAction(#selector(NSTextView.selectAll(_:)), to: editor, from: nil), "Native Select All action is handled")
}
for (position, expected) in [
    ("一级标题", "一级标题 👋"),
    ("二级标题", "二级标题"),
    ("第一行", "普通段落第一行\n同一段落第二行"),
    ("第二行", "普通段落第一行\n同一段落第二行"),
    ("列表条目", "列表条目"),
    ("待办事项", "待办事项"),
    ("引用文字", "引用文字"),
    ("======", "另一种标题"),
    ("print", "    print(\"你好\")\n"),
    ("最后", "最后一段")
] {
    load(blocksFixture)
    editor.setSelectedRange(NSRange(location: blockText.range(of: position).location, length: 0))
    selectAllAction()
    check(editor.selectedRange() == blockText.range(of: expected), "First Select All selects only the current block content: \(position)")
    selectAllAction()
    check(editor.selectedRange() == document, "Second Select All selects document")
    selectAllAction()
    check(editor.selectedRange() == document, "Further Select All preserves document selection")
}
editor.setSelectedRange(NSRange(location: blockText.range(of: "二级标题").location + 1, length: 2))
selectAllAction()
check(editor.selectedRange() == blockText.range(of: "二级标题"), "A partial title selection expands to its title")
editor.setSelectedRange(NSRange(location: blockText.range(of: "最后").location, length: 0))
selectAllAction()
check(editor.selectedRange() == blockText.range(of: "最后一段"), "Moving the caret resets the selection stage")
editor.setSelectedRange(NSRange(location: 2, length: blockText.range(of: "二级标题").location))
selectAllAction()
check(editor.selectedRange() == document, "A selection spanning blocks selects the document")
editor.setSelectedRange(NSRange(location: blockText.range(of: "\n\n").location + 1, length: 0))
selectAllAction()
check(editor.selectedRange() == document, "Blank line falls back to document selection")
editor.preview = true
editor.setSelectedRange(NSRange(location: 2, length: 0))
selectAllAction()
check(editor.selectedRange() == document, "Preview retains native Select All")
editor.preview = false
editor.setSelectedRange(NSRange(location: blockText.length, length: 0))
selectAllAction()
check(editor.selectedRange() == blockText.range(of: "最后一段"), "Caret at end of document selects the final block")
load("前文\n\n# 纯文本标题\n第二行")
note.markdown = false
editor.setSelectedRange(NSRange(location: (editor.string as NSString).range(of: "纯文本").location, length: 0))
selectAllAction()
check((editor.string as NSString).substring(with: editor.selectedRange()) == "# 纯文本标题\n第二行", "Plain text retains literal Markdown-looking markers")
note.markdown = true
load("前文\r\n\r\n## Windows 标题\r\n\r\n最后一段")
editor.setSelectedRange(NSRange(location: (editor.string as NSString).range(of: "Windows").location, length: 0))
selectAllAction()
check((editor.string as NSString).substring(with: editor.selectedRange()) == "Windows 标题", "Heading selection supports CRLF")
load("前文\n\n```swift\nlet value = 1\n```")
editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
selectAllAction()
check((editor.string as NSString).substring(with: editor.selectedRange()) == "let value = 1\n", "Caret after final closing fence selects code")
load("")
selectAllAction()
check(editor.selectedRange() == NSRange(location: 0, length: 0), "Empty document selection is safe")
load(fixture, collapsed: true)
// Render real AppKit layout and controls for visual review.
editor.appearance = NSAppearance(named: .aqua)
if CommandLine.arguments.count > 1, let bitmap = editor.bitmapImageRepForCachingDisplay(in: editor.bounds) {
    editor.cacheDisplay(in: editor.bounds, to: bitmap)
    try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
print("Passed \(checks) copy and AppKit layout checks")
