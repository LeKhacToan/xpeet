#!/usr/bin/env bash
# PreToolUse(Edit|Write|MultiEdit): keep credentials out of diffs.
input=$(cat)
content=$(jq -r '[.tool_input.content, .tool_input.new_string, (.tool_input.edits // [] | .[].new_string)] | map(select(. != null)) | join("\n")' <<<"$input")
[ -z "$content" ] && exit 0
if grep -En -e '-----BEGIN [A-Z ]*PRIVATE KEY-----' \
            -e 'AKIA[0-9A-Z]{16}' \
            -e 'sk-(ant-|live_|proj-)?[A-Za-z0-9_-]{20,}' \
            -e 'gh[pousr]_[A-Za-z0-9]{36}' \
            -e 'AIza[0-9A-Za-z_-]{35}' \
            -e '(api[_-]?key|secret|password|token)["'\'' ]*[:=] *["'\''][^"'\'' ]{12,}' <<<"$content" >&2; then
  echo "Blocked: content looks like a secret. Load it from config/Keychain instead of hardcoding." >&2
  exit 2
fi
exit 0
