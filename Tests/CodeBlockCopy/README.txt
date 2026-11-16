Run on macOS with Xcode command-line tools:

    Tests/CodeBlockCopy/run.sh [optional-preview.png]

The harness compiles the production CodeBlockCopyButton, CodeBlockDetector and
LayoutManager against minimal app dependencies. Concealed-glyph and background
range methods are extracted from production NotesTextProcessor at run time.
Editor mouseMoved, cursorUpdate and modifier handlers are also extracted from
production EditTextView, so cursor regression checks exercise the real routing.
Select All is extracted from the production editor and invoked through the native
AppKit selectAll: action. Checks cover headings, paragraphs, code, lists, quotes,
partial and cross-block selections, document boundaries, Unicode and CRLF.
It checks icon-only controls, tooltips, checkmark feedback, cursor routing, code extraction, the real NSButton action, clipboard output, focus and
selection preservation, stale controls, layout, resize, scrolling and preview.
The original clipboard items are restored after a successful run.
This is an AppKit component test, not a full application UI test.
