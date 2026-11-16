// Minimal app dependencies; the copy control, detector and layout manager are production sources.
import Cocoa
typealias PlatformFont = NSFont
class Note {
    var codeBlockRangesCache: [NSRange]?
    var markdown = true
    func isMarkdown() -> Bool { markdown }
}
class TextStorageProcessor { weak var editor: EditTextView? }
class UserDefaultsManagement {
    static var codeBlockHighlight = true
    static let clickableLinks = false
    static let lineHeightMultiple = 1.2
    static let noteFont = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
}
extension NSAttributedString.Key {
    static let tag = NSAttributedString.Key("tag")
}
class EditorViewController {
    var vcNonSelectedLabel: NSView?
    var vcEditor: EditTextView?
}
class NotesTextProcessor {
    static let concealedSyntaxHidden = NSAttributedString.Key("concealedSyntaxHidden")
    static let collapsedCodeFence = NSAttributedString.Key("collapsedCodeFence")
    struct Style { let backgroundColor = NSColor.controlBackgroundColor }
    struct Options { let style = Style() }
    struct Highlighter { let options = Options() }
    static func getHighlighter() -> Highlighter { Highlighter() }
    // TEXT_PROCESSOR_METHODS

}
class EditTextView: NSTextView {
    var editorViewController: EditorViewController?
    var note: Note?
    var preview = false
    var codeBlockCopyButtons: [CodeBlockCopyButton] = []
    func isPreviewEnabled() -> Bool { preview }
    func isTodo(_ index: Int) -> Bool { false }
    func hasAttachment(at index: Int) -> Bool { false }
    // EDITOR_CURSOR_METHODS
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        updateCodeBlockCopyButtons()
    }
}
