Agent evals: real tasks with acceptance checks. Grow to 20-50 cases taken from real work.

Case format (`cases/<id>.json`): `id`, `prompt`, optional `setup` (shell, run in the worktree and committed before Claude starts), `checks` (shell commands; all must exit 0).

Run locally: `evals/run.sh` or `evals/run.sh 'fix-*'`. Run them after changing `CLAUDE.md`, `.claude/**` or `REVIEW.md`, then `scripts/check-bands.sh` to compare with past runs. Each run uses your Claude Code plan quota (one `claude -p` session per case).
