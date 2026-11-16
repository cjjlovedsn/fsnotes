#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/../.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/install-hint-checks.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
swiftc -module-cache-path "$scratch/ModuleCache" \
    "$repo_dir/FSNotes/ApplicationInstallHint.swift" \
    "$repo_dir/Tests/ApplicationInstallHint/main.swift" -o "$scratch/checks"
"$scratch/checks" "$@"
