# Review guide

Used by human reviewers and by Claude (`claude-code-action` on PRs, `/code-review` locally).

## Passes

1. **Bugs**: logic errors, crashes (force unwraps, out-of-range), main-thread violations, retain cycles, unhandled `async` errors, state not updating UI.
2. **Security & privacy**: secrets/API keys in code or plist, user data logged or sent without need, insecure URLs (http), missing Keychain for credentials, new entitlements/permissions.
3. **Compliance with spec/plan**: the change does what `specs/<slug>/spec.md` requires and touches the files `plan.md` lists. Unlisted files or scope creep must be justified in the PR.

## Severity

- **Important**: findings that would break behavior, leak data, crash, or fail App Store review. Must be fixed before merge.
- **Nit**: style, naming, minor simplification. Max 5 nits per review; drop the rest.

## Exclusions

Do not review: `Xpeet.xcodeproj/**` (generated), `*.xcassets/**/Contents.json`, `evals/results/**`.
