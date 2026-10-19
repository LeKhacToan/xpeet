---
name: intent-to-spec
description: Turn an accepted intent/*.md into specs/<slug>/spec.md. Use when the user asks to write, draft, or generate a spec from an intent, or when an intent was just accepted.
---

1. Read the intent file and confirm `**Status:** accepted`. If it is still draft, stop and say so.
2. Read `CLAUDE.md` and the code areas the intent names under "Affected users & systems" so the spec fits the existing architecture (App/Core/Features, `SpeedProvider`-style protocols in Core, `@Observable` ViewModels). If the spec depends on facts you do not know (Apple APIs, packages, App Store or privacy rules), delegate them to the `researcher` agent and cite its findings.
3. Derive `<slug>` from the intent filename without the date prefix. Copy `specs/_template/spec.md` to `specs/<slug>/spec.md` and fill every section.
   - Requirements are numbered (R1, R2, ...) and each one is testable by a unit test or a manual check.
   - Cover every UI state: loading, empty, error, success. Include accessibility.
   - Do not design beyond the intent; anything extra goes to "Out of scope".
4. Under "Flagged concerns", list anything touching privacy (new data collected, Info.plist usage strings, tracking/ATT), security, payments/subscriptions, or App Store Review Guidelines. These go to their owners before engineering starts.
5. Carry every open question from the intent forward, answered or still open.
6. Report the spec path and the flagged concerns. Do not write code.
