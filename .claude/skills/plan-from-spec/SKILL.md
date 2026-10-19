---
name: plan-from-spec
description: Write specs/<slug>/plan.md for an approved spec before any code is written. Use when starting implementation of a spec, or when the user asks for an implementation plan.
---

Work in plan mode; do not edit source files.

1. Read `specs/<slug>/spec.md`. If it has open flagged concerns, list them and ask whether to proceed.
2. Explore the code the spec touches. Reuse existing types (`APIClient`, `AppState`, existing Features) instead of adding parallel ones. When choosing between technical options, ask the `researcher` agent and record the choice under Risks.
3. Fill `specs/<slug>/plan.md` from `specs/_template/plan.md`:
   - **Files that change**: every file, marked new/modified. New features follow `Xpeet/Features/<Name>/<Name>View.swift` + `<Name>ViewModel.swift` and `XpeetTests/<Name>ViewModelTests.swift`. Include `project.yml` if targets/settings change.
   - **Order of work**: small steps, each leaving the build green. Tests for a ViewModel come with or before it.
   - **Risks**: API limits, threading, migration, App Store review, anything uncertain.
   - **Proof**: map each requirement R<n> to a named test or a manual check.
4. Present the plan for approval. After approval, commit it before implementing.
5. While implementing: if you deviate from the plan, update `plan.md` in the same commit.
