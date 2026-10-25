#!/usr/bin/env bash
# Runs every eval case in an isolated git worktree: optional setup -> claude -p <prompt> -> evals/check.sh.
# Usage: evals/run.sh [case-glob]   e.g. evals/run.sh 'fix-*'
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
results="$root/evals/results/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$results"
pass=0; total=0

for case_file in "$root"/evals/cases/${1:-*}.json; do
  id=$(jq -r .id "$case_file")
  wt=$(mktemp -d)/"$id"
  git -C "$root" worktree add -q --detach "$wt" HEAD
  ( cd "$wt"
    setup=$(jq -r '.setup // empty' "$case_file")
    [ -n "$setup" ] && bash -c "$setup" && git commit -qam "eval setup" --no-verify
    # Headless: no background tasks, otherwise Claude ends the turn while xcodebuild is still running.
    # Sandbox off: Simulator tests hang inside the Bash sandbox, and a stuck agent starts rewriting scripts/ to work
    # around it. Instead it may not edit scripts/ or evals/ (deny rules hold even in an untrusted worktree).
    # Each case is capped at CASE_TIMEOUT seconds (default 30 min) so one stuck agent can't stall the whole run.
    perl -e 'alarm shift; exec @ARGV' "${CASE_TIMEOUT:-1800}" \
      env CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1 \
      claude -p "$(jq -r .prompt "$case_file") Run every command in the foreground and finish only after scripts/verify.sh completes." \
      --settings '{"sandbox":{"enabled":false}}' \
      --permission-mode acceptEdits \
      --allowedTools "Read,Edit,Write,Glob,Grep,Bash(scripts/*),Bash(xcodegen:*),Bash(git:*),Bash(touch:*),Bash(rm .claude/bugfix.lock)" \
      --disallowedTools "Edit(./scripts/**),Write(./scripts/**),Edit(./evals/**),Write(./evals/**)" \
      --output-format json > "$results/$id.json" 2>&1
    status=$?
    [ "$status" -eq 142 ] && echo "$id: timed out after ${CASE_TIMEOUT:-1800} s"
  )
  total=$((total + 1))
  echo "$id"
  if "$root/evals/check.sh" "$case_file" "$wt" | tee "$results/$id.checks"; then pass=$((pass + 1)); fi
  git -C "$root" worktree remove --force "$wt"
done

echo "evals: $pass/$total passed" | tee "$results/summary.txt"
[ "$pass" -eq "$total" ]
