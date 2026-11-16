//
//  CustomLayoutManager.swift
//  FSNotes
//
//  Created by Oleksandr Hlushchenko on 24.08.2025.
//  Copyright © 2025 Oleksandr Hlushchenko. All rights reserved.
//

import Cocoa

fileprivate extension NSRange {
    /// Clamp range to fit inside given maxRange
    func clamped(to maxRange: NSRange) -> NSRange {
        if maxRange.length == 0 { return NSRange(location: maxRange.location, length: 0) }
        if self.location >= NSMaxRange(maxRange) { return NSRange(location: NSMaxRange(maxRange), length: 0) }
        let start = max(self.location, maxRange.location)
        let end = min(NSMaxRange(self), NSMaxRange(maxRange))
        if end <= start { return NSRange(location: start, length: 0) }
        return NSRange(location: start, length: end - start)
    }
}

class LayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    weak var processor: TextStorageProcessor?
    static let codeBlockHeaderHeight: CGFloat = 26

    // Include the opening fence even when concealed: it provides a dedicated
    // toolbar row, so the copy control never covers editable code.
    func codeBlockRect(for range: NSRange, in container: NSTextContainer) -> NSRect {
        guard let storage = textStorage, range.length > 0,
              range.location >= 0, NSMaxRange(range) <= storage.length else { return .zero }
        let visibleRange = NotesTextProcessor.codeBlockBackgroundRange(in: storage, range: range)
        let opening = (storage.string as NSString).lineRange(for: NSRange(location: range.location, length: 0))
        // Hidden fence glyphs can be attached to the preceding line. Its newline
        // still belongs to the fence's own fragment and anchors the toolbar.
        let start = storage.attribute(NotesTextProcessor.collapsedCodeFence, at: range.location, effectiveRange: nil) as? Bool == true
            ? NSMaxRange(opening) - 1 : range.location
        let decoratedRange = NSRange(location: start, length: NSMaxRange(visibleRange) - start)
        let glyphs = glyphRange(forCharacterRange: decoratedRange, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return .zero }
        let rect = boundingRect(forGlyphRange: glyphs, in: container)
        let inset = max(0, container.lineFragmentPadding - 5)
        return NSRect(x: inset, y: rect.minY,
                      width: max(0, container.size.width - 2 * inset), height: rect.height)
    }
    
    override init() {
        super.init()
        
        self.allowsNonContiguousLayout = true
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        self.allowsNonContiguousLayout = true
    }
    
    func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties: UnsafePointer<NSLayoutManager.GlyphProperty>, characterIndexes: UnsafePointer<Int>,
                       font: NSFont, forGlyphRange glyphRange: NSRange) -> Int {
        return NotesTextProcessor.generateConcealedGlyphs(layoutManager, glyphs: glyphs, properties: properties,
                                                        characterIndexes: characterIndexes, font: font, glyphRange: glyphRange)
    }

    public var lineHeightMultiple: CGFloat = CGFloat(UserDefaultsManagement.lineHeightMultiple)

    private var defaultFont: NSFont {
        return self.firstTextView?.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
    }

    private func font(for glyphRange: NSRange) -> NSFont {
        guard let textStorage = self.textStorage else {
            return defaultFont
        }
        
        let characterRange = self.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let storageRange = NSRange(location: 0, length: textStorage.length)
        let safeCharRange = characterRange.clamped(to: storageRange)
        guard safeCharRange.length > 0 else {
            return defaultFont
        }
        
        var tallestFont: NSFont?
        var tallestHeight: CGFloat = 0
        textStorage.enumerateAttributes(in: safeCharRange) { attributes, _, _ in
            guard attributes[NotesTextProcessor.concealedSyntaxHidden] as? Bool != true,
                  let font = attributes[.font] as? NSFont else { return }
            let height = self.defaultLineHeight(for: font)
            if height > tallestHeight {
                tallestFont = font
                tallestHeight = height
            }
        }
        return tallestFont ?? defaultFont
    }
    
    private func hasAttachment(in glyphRange: NSRange) -> (hasAttachment: Bool, maxAttachmentHeight: CGFloat) {
        guard let textStorage = self.textStorage else {
            return (false, 0)
        }
        
        let characterRange = self.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let storageRange = NSRange(location: 0, length: textStorage.length)
        let safeCharRange = characterRange.clamped(to: storageRange)
        if safeCharRange.length == 0 {
            return (false, 0)
        }
        
        var maxHeight: CGFloat = 0
        var hasAttachment = false
        
        textStorage.enumerateAttribute(.attachment, in: safeCharRange, options: []) { value, _, _ in
            if let attachment = value as? NSTextAttachment {
                hasAttachment = true
                let attachmentBounds = attachment.bounds
                maxHeight = max(maxHeight, attachmentBounds.height)
            }
        }
        
        return (hasAttachment, maxHeight)
    }

    public func lineHeight(for font: NSFont) -> CGFloat {
        let fontLineHeight = self.defaultLineHeight(for: font)
        let lineHeight = fontLineHeight * lineHeightMultiple
        return lineHeight
    }

    private func isInCodeBlock(characterIndex: Int) -> Bool {
        guard let textStorage = self.textStorage else {
            return false
        }
        
        let ns = textStorage.string as NSString
        let storageFullRange = NSRange(location: 0, length: ns.length)

        if characterIndex < 0 || characterIndex >= NSMaxRange(storageFullRange) {
            return false
        }
        
        guard let codeBlocks = processor?.editor?.note?.codeBlockRangesCache else { return false }
        return codeBlocks.contains { NSLocationInRange(characterIndex, $0) }
    }
    
    // MARK: - Drawing
    
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        drawCodeBlockBackground(forGlyphRange: glyphsToShow, at: origin)

        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }
    
    override func fillBackgroundRectArray(_ rectArray: UnsafePointer<NSRect>, count rectCount: Int, forCharacterRange charRange: NSRange, color: NSColor) {
        let storageLength = self.textStorage?.length ?? 0
        let storageFullRange = NSRange(location: 0, length: storageLength)
        let safeCharRange = charRange.clamped(to: storageFullRange)
        if color == NSColor.selectedTextBackgroundColor ||
           color == NSColor.unemphasizedSelectedTextBackgroundColor ||
           !isInCodeBlock(characterIndex: safeCharRange.location) {
            super.fillBackgroundRectArray(rectArray, count: rectCount, forCharacterRange: charRange, color: color)
        }
    }
    
    private func drawCodeBlockBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        guard let allCodeBlocks = processor?.editor?.note?.codeBlockRangesCache else { return }
        guard let textContainer = self.textContainers.first else { return }
        
        let visibleCharRange = self.characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let relevantCodeBlocks = allCodeBlocks.filter { codeBlock in
            NSIntersectionRange(codeBlock, visibleCharRange).length > 0
        }
        
        guard !relevantCodeBlocks.isEmpty else { return }
        
        context.saveGState()
        
        let backgroundColor = NotesTextProcessor.getHighlighter().options.style.backgroundColor.cgColor
        let borderColor = NSColor.lightGray.cgColor
        
        for codeBlockRange in relevantCodeBlocks {  // ← теперь только релевантные блоки!
            // The box extends beyond AppKit's selection background. Hide its
            // decoration while selected so the side padding cannot stick out.
            if firstTextView?.selectedRanges.contains(where: {
                NSIntersectionRange($0.rangeValue, codeBlockRange).length > 0
            }) == true {
                continue
            }

            let blockRect = codeBlockRect(for: codeBlockRange, in: textContainer)
            if blockRect.isEmpty { continue }
            let paddedRect = blockRect.offsetBy(dx: origin.x, dy: origin.y)
            
            // Round borders
            let radius: CGFloat = 5.0
            let path = CGPath(roundedRect: paddedRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            
            context.setFillColor(backgroundColor)
            context.addPath(path)
            context.fillPath()
            
            // Border 1px
            context.addPath(path)
            context.setStrokeColor(borderColor)
            context.setLineWidth(1.0)
            context.strokePath()
        }
        
        context.restoreGState()
    }

    public func layoutManager(
            _ layoutManager: NSLayoutManager,
            shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
            lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
            baselineOffset: UnsafeMutablePointer<CGFloat>,
            in textContainer: NSTextContainer,
            forGlyphRange glyphRange: NSRange) -> Bool {

        let characters = characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let isOpeningFence = processor?.editor?.note?.codeBlockRangesCache?.contains { range in
            guard let storage = textStorage, range.location < storage.length else { return false }
            let opening = (storage.string as NSString).lineRange(for: NSRange(location: range.location, length: 0))
            return NSLocationInRange(NSMaxRange(opening) - 1, characters)
        } == true
        if let textStorage = textStorage, characters.location < textStorage.length,
           textStorage.attribute(NotesTextProcessor.collapsedCodeFence, at: characters.location, effectiveRange: nil) as? Bool == true {
            // Keep collapsed fences positive but on whole-point boundaries.
            // A 0.1-point fragment shifts every following line off the pixel
            // grid, leaving selection edge pixels outside partial redraws.
            let height: CGFloat = isOpeningFence ? Self.codeBlockHeaderHeight : 1
            lineFragmentRect.pointee.size.height = height
            lineFragmentUsedRect.pointee.size.height = height
            baselineOffset.pointee = 1
            return true
        }

        // Get the font for the current range of glyphs
        let currentFont = font(for: glyphRange)
        let fontLineHeight = layoutManager.defaultLineHeight(for: currentFont)
        let standardLineHeight = fontLineHeight * lineHeightMultiple
        
        let attachmentInfo = hasAttachment(in: glyphRange)
        
        var finalLineHeight: CGFloat
        var baselineNudge: CGFloat
        
        if attachmentInfo.hasAttachment && attachmentInfo.maxAttachmentHeight > 0 {
            if attachmentInfo.maxAttachmentHeight > standardLineHeight {
                finalLineHeight = attachmentInfo.maxAttachmentHeight
                baselineNudge = 0
            } else {
                finalLineHeight = standardLineHeight
                let extraSpace = finalLineHeight - fontLineHeight
                baselineNudge = extraSpace * 0.5
            }
        } else {
            finalLineHeight = standardLineHeight
            let extraSpace = finalLineHeight - fontLineHeight
            baselineNudge = extraSpace * 0.5
        }

        var rect = lineFragmentRect.pointee
        let style = textStorage?.attribute(.paragraphStyle, at: characters.location, effectiveRange: nil) as? NSParagraphStyle
        // Null glyphs from the next heading may belong to this line's glyph range.
        // Their fonts must not determine the line's height or baseline.
        rect.size.height = ceil(max(finalLineHeight, fontLineHeight + (style?.lineSpacing ?? 0)))
        if isOpeningFence {
            rect.size.height += Self.codeBlockHeaderHeight
        }

        var usedRect = lineFragmentUsedRect.pointee
        usedRect.size.height = rect.size.height

        lineFragmentRect.pointee = rect
        lineFragmentUsedRect.pointee = usedRect
        baselineOffset.pointee = attachmentInfo.hasAttachment
            ? baselineOffset.pointee + baselineNudge
            : layoutManager.defaultBaselineOffset(for: currentFont) + baselineNudge
        if isOpeningFence {
            baselineOffset.pointee += Self.codeBlockHeaderHeight
        }

        return true
    }
    
    func refreshLayoutSoftly() {
        invalidateLayout(forCharacterRange: NSRange(location: 0, length: textStorage?.length ?? 0),
                                actualCharacterRange: nil)
                
        textContainers.forEach { container in
            container.textView?.needsDisplay = true
        }
    }
    
    override func setExtraLineFragmentRect(
        _ fragmentRect: NSRect,
        usedRect: NSRect,
        textContainer container: NSTextContainer) {
        
        var fontToUse: NSFont

        if let textStorage = self.textStorage, textStorage.length > 0 {
            let lastIndex = textStorage.length - 1
            let attributes = textStorage.attributes(at: lastIndex, effectiveRange: nil)
            let nsString = textStorage.string as NSString
            let lastCharIsNewline = nsString.character(at: lastIndex) == 0x0A // '\n'

            if !lastCharIsNewline, let font = attributes[.font] as? NSFont {
                fontToUse = font
            } else {
                fontToUse = UserDefaultsManagement.noteFont
            }
        } else {
            fontToUse = UserDefaultsManagement.noteFont
        }
        
        let lineHeight = self.lineHeight(for: fontToUse)
        
        var fragmentRect = fragmentRect
        fragmentRect.size.height = ceil(lineHeight)
        var usedRect = usedRect
        usedRect.size.height = ceil(lineHeight)

        super.setExtraLineFragmentRect(fragmentRect,
            usedRect: usedRect,
            textContainer: container)
    }
}
