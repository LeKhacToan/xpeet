# AI-native SDLC in Xpeet

How this repo applies [The AI-native SDLC playbook](https://claude.com/resources/articles/the-ai-native-sdlc-playbook). Each stage leaves a file in git, so the next stage (human or Claude) starts from it.
Everything runs locally in Claude Code: there is no hosted CI and nothing calls Claude unattended.

## One-time setup

```sh
brew install xcodegen swiftlint
git config core.hooksPath .githooks   # pre-push runs scripts/verify.sh
```

| Stage | Artifact | How |
|---|---|---|
| 1. Plan | `intent/<date>-<slug>.md` | Copy `intent/TEMPLATE.md`. Product owner reviews the PR and sets `Status: accepted`. |
| 2. Design | `specs/<slug>/spec.md` | In Claude Code: "use intent-to-spec on intent/...". Unknowns (APIs, libraries, App Store rules) go to the `researcher` agent first. Resolve **Flagged concerns** before approving. |
| 3. Build | `specs/<slug>/plan.md`, code | `claude --worktree <slug>`, then plan mode + `plan-from-spec` skill. Commit the plan, then implement. 2-3 parallel worktrees max. |
| 4. Test | `scripts/verify.sh`, `evals/` | Claude must run `verify.sh` before saying done; the `pre-push` git hook runs it again. Run the `verifier` subagent before the PR. Bugs go through `bugfix-tdd` (failing test first). Run `evals/run.sh` after changing `CLAUDE.md`/`.claude/**`. |
| 5. Deploy | `REVIEW.md` | Before merge: ask Claude to "use the reviewer agent" (or `/code-review`), which follows `REVIEW.md`. App Store/TestFlight uploads are blocked by `production-gate.sh` unless `RELEASE_AUTHORIZATION` is set. |
| 6. Maintain | `bands.yaml` | After each eval run: `scripts/check-bands.sh`. Eval pass-rate drop 1σ log, 2σ read-only diagnosis, 3σ Claude writes a draft intent, which re-enters stage 1. |

## What lives where

```
CLAUDE.md                  project memory: commands, conventions, known mistakes (< 1 page)
REVIEW.md                  review passes, severity, nit cap, exclusions
intent/                    stage 1 proto-specs
specs/<slug>/              spec.md + plan.md per change (_template/ for copies)
bands.yaml                 stage 6 monitored metric (local eval pass rate)
scripts/                   build.sh test.sh lint.sh verify.sh check-bands.sh
evals/                     cases/*.json, run.sh, check.sh
.claude/settings.json      permissions + hooks
.claude/hooks/             protect-paths, secret-scan, lint-file, production-gate
.claude/skills/            intent-to-spec, plan-from-spec, bugfix-tdd, swiftui-feature
.claude/agents/            researcher, verifier, reviewer
.githooks/pre-push         runs scripts/verify.sh before every push (local CI)
docs/managed-settings.example.json   org-level policy template (deployed by admin, not this repo)
```

## Guardrails (hooks)

- `protect-paths.sh`: no edits to `Xpeet.xcodeproj/**` (generated) or credential files; no edits to `XpeetTests/**` while `.claude/bugfix.lock` exists.
- `secret-scan.sh`: blocks writes containing private keys, API tokens, hardcoded passwords.
- `lint-file.sh`: SwiftLint on each edited `.swift` file; violations are fed back to Claude.
- `production-gate.sh`: blocks `fastlane release/beta/pilot/deliver`, `altool --upload`, force-push and direct push to `main`.

## Keeping it healthy

- Same mistake twice: add one line to "Known mistakes" in `CLAUDE.md`.
- Every real task that went wrong is a candidate eval case in `evals/cases/`. Target 20-50.
- After changing `CLAUDE.md`, `.claude/**` or `REVIEW.md`, run `evals/run.sh` then `scripts/check-bands.sh`; don't merge a regression.
