#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/../.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/fsnotes-copy-checks.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
# Use the real concealment routines without linking the whole application.
python3 - "$repo_dir" "$check_dir" <<'PY'
from pathlib import Path
import sys
repo, scratch = map(Path, sys.argv[1:])
source = (repo / 'FSNotesCore/NotesTextProcessor.swift').read_text()
methods = []
for start, end in [('    static func generateConcealedGlyphs(', '    public static func concealSyntax('), ('    static func codeBlockBackgroundRange(', '    private var note:')]:
    methods.append(source[source.index(start):source.index(end)])
stub = (repo / 'Tests/CodeBlockCopy/Stubs.swift').read_text()
editor = (repo / 'FSNotes/View/EditTextView.swift').read_text()
cursor_methods = []
for start, end in [('    override func selectAll(', '    public func hasAttachment('), ('    override func flagsChanged(', '    override func keyDown(')]:
    cursor_methods.append(editor[editor.index(start):editor.index(end)])
(scratch / 'Stubs.swift').write_text(stub.replace('    // TEXT_PROCESSOR_METHODS', '\n'.join(methods)).replace('    // EDITOR_CURSOR_METHODS', '\n'.join(cursor_methods)))
PY
swiftc -module-cache-path "$check_dir/ModuleCache" \
  "$check_dir/Stubs.swift" \
  "$repo_dir/FSNotesCore/CodeBlockDetector.swift" \
  "$repo_dir/FSNotes/LayoutManager.swift" \
  "$repo_dir/FSNotes/MarkdownBlockSelection.swift" \
  "$repo_dir/FSNotes/View/CodeBlockCopyButton.swift" \
  "$repo_dir/Tests/CodeBlockCopy/main.swift" -o "$check_dir/checks"
"$check_dir/checks" "$@"
