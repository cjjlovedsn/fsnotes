import Cocoa

/// A native AppKit control supplies VoiceOver activation without taking the
/// editor's first responder or changing its selection.
final class CodeBlockCopyButton: NSButton {
    var blockRange = NSRange(location: 0, length: 0)
    var source = ""
    weak var note: Note?
    private var feedbackID = UUID()
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovered = false

    static let preferredWidth: CGFloat = 24

    override var acceptsFirstResponder: Bool { false }

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        isBordered = false
        controlSize = .small
        font = .systemFont(ofSize: 11)
        contentTintColor = .secondaryLabelColor
        (cell as? NSButtonCell)?.highlightsBy = []
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        setAccessibilityLabel(NSLocalizedString("Copy code", comment: "Code block copy button"))
        resetFeedback()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        if let area = hoverTrackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
        super.updateTrackingAreas()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled { addCursorRect(visibleRect, cursor: .pointingHand) }
    }

    override func cursorUpdate(with event: NSEvent) {
        if isEnabled { NSCursor.pointingHand.set() }
    }

    override func mouseMoved(with event: NSEvent) {
        if isEnabled { NSCursor.pointingHand.set() }
    }

    override func mouseEntered(with event: NSEvent) {
        if isEnabled { NSCursor.pointingHand.set() }
        isHovered = true
        contentTintColor = .labelColor
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        contentTintColor = .secondaryLabelColor
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHovered || isHighlighted {
            NSColor.labelColor.withAlphaComponent(isHighlighted ? 0.12 : 0.06).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        }
        super.draw(dirtyRect)
    }

    private func setSymbol(_ name: String) {
        image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .regular))
        // Assigning a new image can reset an NSButtonCell's image position.
        imagePosition = .imageOnly
    }

    func resetFeedback() {
        feedbackID = UUID()
        title = ""
        setSymbol("doc.on.doc")
        toolTip = NSLocalizedString("Copy code", comment: "Code block copy button")
    }

    func showCopied() {
        let id = UUID()
        feedbackID = id
        title = ""
        setSymbol("checkmark")
        NSAccessibility.post(element: self, notification: .announcementRequested, userInfo: [
            .announcement: NSLocalizedString("Copied", comment: "Code copied confirmation"),
            .priority: NSAccessibilityPriorityLevel.medium.rawValue
        ])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self, self.feedbackID == id else { return }
            self.resetFeedback()
        }
    }
}

extension EditTextView {
    /// NSTextView also receives tracking and modifier events over child views.
    /// Route these before its text/link cursor logic can restore an I-beam.
    @discardableResult
    func updateCodeBlockCopyCursor(with event: NSEvent) -> Bool {
        guard !isPreviewEnabled() else { return false }
        let point = convert(event.locationInWindow, from: nil)
        guard codeBlockCopyButtons.contains(where: {
            $0.isEnabled && !$0.isHidden && $0.note === note &&
                $0.frame.intersection(visibleRect).contains(point)
        }) else { return false }
        NSCursor.pointingHand.set()
        return true
    }

    func updateCodeBlockCopyButtons() {
        guard !isPreviewEnabled(), let note = note, note.isMarkdown(),
              let storage = textStorage, storage.length > 0,
              let manager = layoutManager as? LayoutManager,
              let container = textContainer else {
            codeBlockCopyButtons.forEach { $0.removeFromSuperview() }
            codeBlockCopyButtons.removeAll()
            return
        }

        let visibleGlyphs = manager.glyphRange(forBoundingRect:
            visibleRect.offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y), in: container)
        let visibleCharacters = manager.characterRange(forGlyphRange: visibleGlyphs, actualGlyphRange: nil)
        let text = storage.string as NSString
        var index = 0
        for range in note.codeBlockRangesCache ?? [] {
            guard NSIntersectionRange(range, visibleCharacters).length > 0,
                  range.location >= 0, NSMaxRange(range) <= storage.length else { continue }
            let block = manager.codeBlockRect(for: range, in: container)
                .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            let width = min(CodeBlockCopyButton.preferredWidth, block.width - 12)
            guard width >= 20 else { continue }
            let frame = NSRect(x: block.maxX - width - 6, y: block.minY + 3,
                               width: width, height: LayoutManager.codeBlockHeaderHeight - 6)
            guard frame.intersects(visibleRect) else { continue }

            if index == codeBlockCopyButtons.count {
                let button = CodeBlockCopyButton()
                button.target = self
                button.action = #selector(copyCodeBlock(_:))
                codeBlockCopyButtons.append(button)
                addSubview(button)
            }
            let button = codeBlockCopyButtons[index]
            let source = text.substring(with: range)
            if button.blockRange != range || button.source != source || button.note !== note {
                button.resetFeedback()
            }
            button.blockRange = range
            button.source = source
            button.note = note
            button.frame = frame
            index += 1
        }
        while codeBlockCopyButtons.count > index {
            codeBlockCopyButtons.removeLast().removeFromSuperview()
        }
    }

    @objc func copyCodeBlock(_ sender: CodeBlockCopyButton) {
        // Validate the displayed control against the live buffer, even if a
        // note switch or edit happened before the next display pass.
        guard !isPreviewEnabled(), sender.note === note,
              let storage = textStorage,
              NSMaxRange(sender.blockRange) <= storage.length,
              (storage.string as NSString).substring(with: sender.blockRange) == sender.source,
              let code = CodeBlockDetector.codeBody(in: sender.source) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setString(code, forType: .string) {
            sender.showCopied()
        }
    }
}
