---
name: swiftui-feature
description: Scaffold or extend a SwiftUI feature screen in this app (View + ViewModel + tests + tab/navigation wiring). Use when adding a new screen, tab, or feature folder.
---

Follow the existing pattern in `Xpeet/Features/Home/`.

1. Create `Xpeet/Features/<Name>/<Name>ViewModel.swift`:
   - `import Observation`, `@Observable final class <Name>ViewModel`.
   - Async work is `func load() async`; expose `state` as an enum (`idle`, `loading`, `loaded(...)`, `failed(String)`) when there is network/IO.
   - Inject dependencies (e.g. `APIClient`) through `init` with defaults so tests can pass fakes.
2. Create `Xpeet/Features/<Name>/<Name>View.swift`:
   - `@State private var viewModel = <Name>ViewModel()`, `NavigationStack` with `.navigationTitle`, `.task { await viewModel.load() }` if needed.
   - Render every state; no business logic in the View.
   - Add `#Preview`.
3. If it is a tab: add a case to `AppTab` in `Xpeet/App/AppState.swift` and a `.tabItem`/`.tag` in `Xpeet/App/RootView.swift`.
4. Create `XpeetTests/<Name>ViewModelTests.swift` covering each state transition.
5. Run `xcodegen generate`, then `scripts/verify.sh`.
