---
name: swiftui-feature
description: Scaffold or extend a SwiftUI feature in this app (View + ViewModel + tests, dependency behind a protocol). Use when adding a feature folder or extending the speedometer screen.
---

Follow the existing pattern in `Xpeet/Features/Speedometer/`.
The app is single-screen by design. A new screen, tab or navigation needs its own accepted intent first; extend `SpeedometerView` otherwise.

1. If the feature needs a system service (location, motion, storage, ...), put it behind a protocol in `Xpeet/Core/<Area>/`, as in `Core/Location/SpeedProvider.swift`:
   - Expose `AsyncStream`s, not delegates or callbacks.
   - Add a production implementation and a `#if DEBUG` fake that previews and tests share.
2. Create or extend `Xpeet/Features/<Name>/<Name>ViewModel.swift`:
   - `import Observation`, `@Observable @MainActor final class <Name>ViewModel`.
   - Inject dependencies through `init` with production defaults (provider, `UserDefaults`, `Locale`, `now: () -> Date`) so tests can pass fakes. Default a `@MainActor` dependency as `provider ?? Real()` inside `init`, not as a default argument.
   - Put logic in synchronous methods (`handle(...)`, `tick()`); `func run() async` only feeds streams into them.
   - Expose `state` as an enum and View-ready strings (display text, status, accessibility label).
3. Create or extend `Xpeet/Features/<Name>/<Name>View.swift`:
   - `@State private var viewModel`, plus `.task(id: scenePhase) { if scenePhase == .active { await viewModel.run() } }` when the feature streams data.
   - Render every state; no business logic in the View. Add accessibility labels and support Dynamic Type.
   - Add `#Preview`s with the fake, one per state.
4. Create or extend `XpeetTests/<Name>ViewModelTests.swift` covering each state transition. Call the synchronous handlers directly; use the fake plus a short polling wait only for `run()`.
5. Run `xcodegen generate`, then `scripts/verify.sh`.
