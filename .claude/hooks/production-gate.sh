#!/usr/bin/env bash
# PreToolUse(Bash): production releases require a named release authorization.
# Approve a release by starting Claude with: RELEASE_AUTHORIZATION="<approver>:<version>" claude
input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")

if grep -Eq '(fastlane|bundle exec fastlane)[[:space:]]+[^|;&]*(release|deliver|upload_to_app_store|pilot|beta)|xcrun[[:space:]]+altool[^|;&]*--upload|xcrun[[:space:]]+notarytool|asc[[:space:]]+.*submit' <<<"$cmd"; then
  if [ -z "${RELEASE_AUTHORIZATION:-}" ]; then
    echo "Blocked: App Store/TestFlight upload needs RELEASE_AUTHORIZATION=<approver>:<version>. Ask a human to approve the release." >&2
    exit 2
  fi
fi

if grep -Eq 'git[[:space:]]+push[^|;&]*(--force|-f([[:space:]]|$)|[[:space:]](origin[[:space:]]+)?(main|master)([[:space:]]|$))' <<<"$cmd"; then
  echo "Blocked: no force-push or direct push to main. Push a branch and open a PR." >&2
  exit 2
fi
exit 0
