---
name: bugfix-tdd
description: Fix a bug test-first. Use whenever the user reports a bug, crash, or regression, or asks to fix incorrect behavior.
---

1. Reproduce: find the code path and state the root cause hypothesis in one sentence.
2. Write a failing XCTest in `XpeetTests/` that captures the bug (name it `test_<behavior>_<condition>`). Run `scripts/test.sh` and confirm it fails for the right reason.
3. Commit the failing test alone: `test: reproduce <bug>`.
4. Lock the tests: `touch .claude/bugfix.lock`. Edits under `XpeetTests/` are now blocked by a hook, so the fix must be in the code.
5. Fix the code with the smallest change that makes the test pass. Run `scripts/verify.sh`.
6. Remove the lock: `rm .claude/bugfix.lock`. Commit the fix: `fix: <bug>`.
7. If the same kind of mistake has now happened twice, propose a one-line entry for "Known mistakes" in `CLAUDE.md`.
