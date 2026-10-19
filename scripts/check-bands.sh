#!/usr/bin/env bash
# Evaluates bands.yaml against local eval history. Needs at least 3 eval runs to form a baseline.
set -euo pipefail
cd "$(dirname "$0")/.."
cfg() { sed -nE "s/^[[:space:]]*$1:[[:space:]]*([^[:space:]#]+).*/\1/p" bands.yaml | head -1; }
n=$(cfg baseline_runs)
results="${EVAL_RESULTS:-evals/results}"

rates=$(for f in $(ls -d "$results"/*/ 2>/dev/null | sort | tail -$((n + 1))); do
  sed -nE 's/^evals: ([0-9]+)\/([0-9]+).*/\1 \2/p' "$f/summary.txt" 2>/dev/null | awk '$2 > 0 { print $1 / $2 }' || true
done)
[ "$(grep -c . <<<"$rates" || true)" -lt 3 ] && { echo "bands: not enough eval history yet (need 3 runs)"; exit 0; }

read -r latest mean sd z < <(awk '{ r[NR] = $1 } END {
  for (i = 1; i < NR; i++) s += r[i]; m = s / (NR - 1)
  for (i = 1; i < NR; i++) v += (r[i] - m) ^ 2; sd = sqrt(v / (NR - 1))
  print r[NR], m, sd, (sd > 0 ? (m - r[NR]) / sd : (r[NR] < m ? 99 : 0)) }' <<<"$rates")
echo "eval_pass_rate: latest=$latest baseline=$mean sd=$sd drop=${z}σ"

ge() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a >= b) }'; }
latest_dir=$(ls -d "$results"/*/ | sort | tail -1)
if ge "$z" "$(cfg propose)"; then
  claude -p "Eval pass rate dropped ${z}σ (latest $latest vs baseline $mean). Compare $latest_dir*.checks with earlier runs in evals/results/ and git log -- CLAUDE.md .claude REVIEW.md. Write findings as intent/$(date +%Y-%m-%d)-eval-regression.md from intent/TEMPLATE.md (Status: draft)." \
    --permission-mode acceptEdits --allowedTools "Read,Write,Grep,Glob,Bash(git log:*),Bash(git diff:*)"
elif ge "$z" "$(cfg diagnose)"; then
  claude -p "Eval pass rate dropped ${z}σ (latest $latest vs baseline $mean). Read-only: compare $latest_dir*.checks with earlier runs and recent changes to CLAUDE.md/.claude/. Report the likely cause in under 10 lines." \
    --allowedTools "Read,Grep,Glob,Bash(git log:*),Bash(git diff:*)"
elif ge "$z" "$(cfg log)"; then
  echo "bands: 1σ drift logged, no action"
fi
