#!/usr/bin/env bash
# PostToolUse(Edit|Write|MultiEdit): fast, file-scoped SwiftLint on the edited file. Exit 2 feeds violations back to Claude.
input=$(cat)
file=$(jq -r '.tool_input.file_path // empty' <<<"$input")
[[ "$file" == *.swift ]] || exit 0
command -v swiftlint >/dev/null || exit 0
cd "$CLAUDE_PROJECT_DIR"
out=$(swiftlint lint --quiet --strict "$file" 2>&1) || { echo "$out" >&2; exit 2; }
exit 0
