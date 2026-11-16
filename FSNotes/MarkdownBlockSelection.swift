import Foundation

/// Content ranges use NSString offsets, matching NSTextView's UTF-16 selections.
enum MarkdownBlockSelection {
    private static let heading = try! NSRegularExpression(pattern: #"^ {0,3}#{1,6}[\t ]+(.*?)(?:[\t ]+#+)?[\t ]*$"#)
    private static let list = try! NSRegularExpression(pattern: #"^[\t ]*(?:[-+*]|[0-9]{1,9}[.)])[\t ]+(?:\[[ xX]\][\t ]+)?(.*)$"#)
    private static let quote = try! NSRegularExpression(pattern: #"^[\t ]*(?:>[\t ]*)+(.*)$"#)
    private static let boundary = try! NSRegularExpression(pattern: #"^[\t ]*(?:`{3,}|~{3,}|[-*_](?:[\t ]*[-*_]){2,})"#)
    private static let underline = try! NSRegularExpression(pattern: #"^ {0,3}(?:=+|-+)[\t ]*$"#)

    static func range(in string: String, selection: NSRange, codeBlocks: [NSRange], isMarkdown: Bool = true) -> NSRange? {
        let text = string as NSString
        guard text.length > 0, selection.location >= 0,
              NSMaxRange(selection) <= text.length,
              selection != NSRange(location: 0, length: text.length) else { return nil }

        let atFinalContentEnd = selection.location == text.length && !string.hasSuffix("\n") && !string.hasSuffix("\r")
        func contains(_ outer: NSRange) -> Bool {
            selection.length == 0
                ? NSLocationInRange(selection.location, outer) || (atFinalContentEnd && NSMaxRange(outer) == text.length)
                : selection.location >= outer.location && NSMaxRange(selection) <= NSMaxRange(outer)
        }
        let blocks = isMarkdown ? codeBlocks.filter { $0.location >= 0 && $0.length > 0 && NSMaxRange($0) <= text.length } : []
        for block in blocks where contains(block) {
            guard let body = CodeBlockDetector.codeBodyRange(in: text.substring(with: block)) else { continue }
            return NSRange(location: block.location + body.location, length: body.length)
        }

        struct Line { let whole: NSRange; let content: NSRange }
        var lines: [Line] = []
        var location = 0
        while location < text.length {
            var end = 0, contentEnd = 0
            text.getLineStart(nil, end: &end, contentsEnd: &contentEnd, for: NSRange(location: location, length: 0))
            lines.append(Line(whole: NSRange(location: location, length: end - location),
                              content: NSRange(location: location, length: contentEnd - location)))
            location = end
        }
        guard let current = lines.firstIndex(where: {
            NSLocationInRange(selection.location, $0.whole) || (atFinalContentEnd && NSMaxRange($0.whole) == text.length)
        }) else { return nil }

        func match(_ regex: NSRegularExpression, _ index: Int) -> NSTextCheckingResult? {
            regex.firstMatch(in: text.substring(with: lines[index].content), range: NSRange(location: 0, length: lines[index].content.length))
        }
        func isPlain(_ index: Int) -> Bool {
            !text.substring(with: lines[index].content).trimmingCharacters(in: .whitespaces).isEmpty &&
                !blocks.contains { NSIntersectionRange($0, lines[index].whole).length > 0 } &&
                (!isMarkdown || [heading, list, quote, boundary, underline].allSatisfy { match($0, index) == nil })
        }
        func captured(_ regex: NSRegularExpression, _ index: Int) -> NSRange? {
            guard let result = match(regex, index) else { return nil }
            let capture = result.range(at: 1)
            return NSRange(location: lines[index].content.location + capture.location, length: capture.length)
        }

        // Setext headings: either the title line or its underline selects title text.
        let titleIndex = match(underline, current) != nil ? current - 1 : current
        if isMarkdown, titleIndex >= 0, titleIndex + 1 < lines.count, isPlain(titleIndex),
           match(underline, titleIndex + 1) != nil,
           contains(NSUnionRange(lines[titleIndex].whole, lines[titleIndex + 1].whole)) {
            return lines[titleIndex].content
        }
        if isMarkdown, contains(lines[current].whole) {
            for syntax in [heading, list, quote] {
                if let content = captured(syntax, current), content.length > 0 { return content }
            }
        }
        guard isPlain(current) else { return nil }
        var first = current, last = current
        while first > 0 && isPlain(first - 1) {
            first -= 1
        }
        while last + 1 < lines.count && isPlain(last + 1) {
            if isMarkdown, last + 2 < lines.count, match(underline, last + 2) != nil { break }
            last += 1
        }
        let whole = NSUnionRange(lines[first].whole, lines[last].whole)
        return contains(whole) ? NSUnionRange(lines[first].content, lines[last].content) : nil
    }
}
