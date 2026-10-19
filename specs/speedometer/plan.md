# Plan: Single-screen speedometer

**Spec:** specs/speedometer/spec.md
<!-- Produced in Claude Code plan mode. Update in the same commit when implementation diverges. -->

## Design summary
- `XpeetApp` shows `SpeedometerView` directly. There is no `RootView`, `TabView` or `AppState`, because nothing app-wide is left to share. One screen owns its own `@State` ViewModel.
- `Core/Location` is the only code that imports CoreLocation. It exposes a small `SpeedProvider` protocol, so the ViewModel and its tests never see `CLLocation`.
- `SpeedometerViewModel` is `@Observable @MainActor`. All logic sits in small synchronous handlers that tests call directly and deterministically:
  - `handle(authorization:)`
  - `handle(sample:)`
  - `tick()` (the staleness check)
  - `toggleUnit()`
- `func run() async` only plumbs the provider's streams and a 1-second ticker into those handlers. It sets the idle timer on entry and restores it in a `defer`.
- The View calls `.task(id: scenePhase) { if scenePhase == .active { await viewModel.run() } }`. Leaving the active state cancels the task, which stops location updates and restores the idle timer (R19, R20). Returning restarts it, and `run()` resets the filter (R11).
- Injected dependencies, all with production defaults:
  - `provider: SpeedProvider`
  - `defaults: UserDefaults`
  - `locale: Locale`
  - `now: () -> Date`
  - `setIdleTimerDisabled: (Bool) -> Void`
- Smoothing: an EMA with `smoothingFactor = 0.6` and a filter reset after any Acquiring period. The View animates `.contentTransition(.numericText(value:))` with a short `.smooth` animation (about 0.6 s, under the ~1 s sample interval), so digits roll instead of jumping (R9–R12).
- Thresholds are named constants in the ViewModel:
  - `staleInterval = 5` s
  - `zeroClampMetersPerSecond = 1 / 3.6`
  - `weakAccuracyMetersPerSecond = 2`

## Files that change
- `Xpeet/Core/Location/SpeedProvider.swift` (new): `SpeedSample`, the `LocationAuthorization` enum (`notDetermined`, `authorized`, `denied`, `restricted`, `servicesOff`), and the `SpeedProvider` protocol:
  - `authorizationUpdates() -> AsyncStream<LocationAuthorization>`: yields the current value first, then each change.
  - `speedUpdates() -> AsyncStream<SpeedSample>`
  - `requestAuthorization()`
- `Xpeet/Core/Location/CoreLocationSpeedProvider.swift` (new): `@MainActor`.
  - `speedUpdates()` wraps `CLLocationUpdate.liveUpdates(.automotiveNavigation)`. It skips updates with a nil location and maps the rest to `SpeedSample` (speed, speedAccuracy, isStationary, timestamp).
  - It owns one `CLLocationManager` for `requestWhenInUseAuthorization()` and status.
  - `locationManagerDidChangeAuthorization` is bridged into the authorization `AsyncStream`. This is the only delegate in the app, and it is confined to Core.
  - `CLLocationManager.locationServicesEnabled()` is called off the main actor.
- `Xpeet/Core/Location/FakeSpeedProvider.swift` (new, `#if DEBUG`): it is backed by `AsyncStream.makeStream()` and records `requestAuthorization()` calls. Previews and tests share it.
- `Xpeet/Features/Speedometer/SpeedometerViewModel.swift` (new):
  - The `SpeedUnit` enum (`kmh` / `mph`, persisted raw value).
  - The `state` enum: `acquiring`, `live(weakSignal: Bool)`, `unavailable(reason, canOpenSettings)`.
  - The values the View reads: `displayText`, `unitText`, `statusText`, `accessibilityLabel`, `unitAccessibilityValue`.
- `Xpeet/Features/Speedometer/SpeedometerView.swift` (new):
  - Black background, `.preferredColorScheme(.dark)`.
  - The number uses SF Rounded heavy with `.monospacedDigit()`, `minimumScaleFactor`, and a size taken from `GeometryReader` (the shorter side).
  - The unit label is a `Button` with a 44 pt minimum hit area.
  - The status line uses `@ScaledMetric` and Dynamic Type.
  - "Open Settings" uses `openURL(UIApplication.openSettingsURLString)`.
  - Accessibility: the speed is one combined element with the `.updatesFrequently` trait.
  - `#Preview`s cover Live, Acquiring, Denied, and Live in landscape.
- `Xpeet/App/XpeetApp.swift` (modified): `WindowGroup { SpeedometerView() }`.
- `Xpeet/App/RootView.swift`, `Xpeet/App/AppState.swift` (deleted).
- `Xpeet/Features/Home/HomeView.swift`, `Xpeet/Features/Home/HomeViewModel.swift` (deleted).
- `Xpeet/Features/Settings/SettingsView.swift` (deleted).
- `Xpeet/Core/Networking/APIClient.swift` (deleted).
- `Xpeet/Core/Extensions/Bundle+Version.swift` (deleted): it was only used by Settings, and version display is out of scope.
- `XpeetTests/HomeViewModelTests.swift` (deleted).
- `XpeetTests/SpeedometerViewModelTests.swift` (new): see Proof.
- `project.yml` (modified):
  - `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone: "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"`.
  - Add `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` with the spec's string.
  - No `UIBackgroundModes`.
- `evals/cases/fix-plural-message.json`, `add-settings-version-row.json`, `new-feature-with-tests.json` (deleted), replaced by three new cases (R24):
  - `evals/cases/fix-zero-clamp.json` (new, bug fix): `setup` uses `sed` to break the zero clamp. The prompt reports "at a standstill the speedometer shows 1 instead of 0". Checks: the stationary/zero-clamp test still exists in `SpeedometerViewModelTests.swift`, and `scripts/test.sh` passes.
  - `evals/cases/rename-weak-signal-status.json` (new, small change): the prompt asks to change the "Weak GPS signal" status text to "Low GPS accuracy". Checks: `grep -q 'Low GPS accuracy' Xpeet/Features/Speedometer/SpeedometerViewModel.swift`, `! grep -rq 'Weak GPS signal' Xpeet`, and `scripts/verify.sh` passes.
  - `evals/cases/add-max-speed.json` (new, tested feature): the prompt asks for a session max-speed readout (`maxSpeedText` on the ViewModel, shown small under the unit) with unit tests. Checks: `grep -q maxSpeedText` on the ViewModel, `grep -q -i maxSpeed XpeetTests/SpeedometerViewModelTests.swift`, `! grep -rq ObservableObject Xpeet`, and `scripts/verify.sh` passes.
- `CLAUDE.md` (modified, R25): the Architecture section describes `XpeetApp -> SpeedometerView` and the `Core/Location` `SpeedProvider` + fake pattern; the `RootView (TabView)`, `AppState` and `APIClient` lines are removed.
- `.claude/skills/swiftui-feature/SKILL.md` (modified, R25):
  - It now follows the `Features/Speedometer` pattern: inject protocols with defaults, synchronous handlers plus `run()`, and a DEBUG fake for previews and tests.
  - The tab wiring step is removed.
  - It says a new screen needs its own intent, because the app is single-screen by design.
- `.claude/skills/plan-from-spec/SKILL.md`, `.claude/skills/intent-to-spec/SKILL.md` (modified): they replace the `APIClient` and `AppState` examples with `SpeedProvider` and `SpeedometerViewModel`. This is a small extension of R25 so the skills don't point at deleted types.

## Order of work
Each step ends with `xcodegen generate` (when files were added or removed) and `scripts/verify.sh` green.

1. Commit `plan.md`.
2. **Core/Location types**: add `SpeedProvider.swift` and `FakeSpeedProvider.swift`. Build green; existing Home tests still pass.
3. **ViewModel, test-first**: write `SpeedometerViewModelTests.swift` against the fake, then `SpeedometerViewModel.swift`, until every test in Proof passes. No UI yet.
4. **CoreLocationSpeedProvider**: add the real provider. Build green; this file has no unit tests (see Risks).
5. **View and app wiring**:
   - Add `SpeedometerView.swift` with previews and point `XpeetApp` at it.
   - Delete Home, Settings, RootView, AppState, APIClient, Bundle+Version and HomeViewModelTests.
   - Update `project.yml` with the orientations and the usage string.
   - Run `xcodegen generate`, then `scripts/verify.sh`.
6. **Manual checks** in the iPhone 15 simulator, iOS 27.1 (see Proof):
   - Fresh install permission prompt and deny/allow.
   - Features > Location > Freeway Drive for live speed and digit animation.
   - Location > None for Acquiring.
   - Rotation, largest Dynamic Type, VoiceOver with Accessibility Inspector, and the background/foreground cycle.
7. **Repo tooling**:
   - Rewrite the eval cases.
   - Update `CLAUDE.md` and the three skills.
   - Dry-check each new case with `evals/check.sh` against the finished tree, where the checks should pass, and against the post-setup tree, where they should fail.
   - Run `evals/run.sh`, then `scripts/check-bands.sh`.
8. `scripts/verify.sh`, the `verifier` agent, then the `reviewer` agent against REVIEW.md, then the PR.

## Risks
- **iOS 17 permission flow**: on iOS 17, `liveUpdates` does not prompt by itself. This is a researcher inference based on WWDC23/24, so the provider always calls `requestWhenInUseAuthorization()` explicitly when the status is `.notDetermined`. The owner accepted that there is no iOS 17 device or simulator to test on; it is tested on iOS 27.1 only.
- **Choice of location API** (researcher option A1 over A2): `CLLocationUpdate.liveUpdates` fits async/await and needs no delegate for samples. The trade-off is a small delegate bridge kept only for authorization, because iOS 17 lacks the `CLServiceSession` and diagnostic properties, which are iOS 18+. No `#available(iOS 18)` branches are added, to keep one code path.
- **Threading**:
  - `CLLocationManager` must be created on a thread with a run loop, so the provider is `@MainActor`.
  - `locationServicesEnabled()` blocks and triggers a main-thread warning, so it runs in a detached task.
  - Swift 5 language mode: expect a few Sendable warnings around `AsyncStream` continuations. They must not become errors, and lint must stay OK.
- **The real provider is untested**: `CoreLocationSpeedProvider` is a thin mapping layer with no unit tests, because CoreLocation can't be faked without another abstraction. The simulator Freeway Drive check covers it.
- **GPS limits**: speed arrives at about 1 Hz and is noisy at low speed, and there is no API to raise the rate beyond `.automotiveNavigation`. The perceived smoothness comes from the EMA plus the digit animation. α may be tuned during manual checks as long as the R10 tests still pass; any change to α is written back into this plan and the spec.
- **Simulator caveat**: a fixed custom location reports speed −1, which shows as Acquiring. Only the Freeway Drive / City Run presets produce speed.
- **Deleting template code**: the three old eval cases break as soon as step 5 lands and are replaced in step 7, in the same PR. `scripts/verify.sh` does not run evals, so CI is not affected in between.
- **Eval cost and bands**:
  - `evals/run.sh` uses one `claude -p` session per case from the plan quota.
  - The pass-rate history in `evals/results/` refers to the old cases. `check-bands.sh` needs 3 runs to form a baseline, so a new baseline starts here.
  - Changing `CLAUDE.md` and `.claude/**` needs the owner's approval. The owner requested it in the intent.
- **App Store**: not distributed, so the privacy manifest, privacy policy and review guidelines are not blocking (see the spec's Flagged concerns).

## Proof
Unit tests are in `XpeetTests/SpeedometerViewModelTests.swift`, written against `FakeSpeedProvider`, a fixed `Locale`, a throwaway `UserDefaults(suiteName:)` and a controllable `now`.

| Req | Proof |
|---|---|
| R1 | Manual: the app launches to the speed screen. `! grep -rq TabView Xpeet` |
| R2 | Manual and previews: black background in both light and dark system modes |
| R3 | Manual: rotate to portrait, landscape left and landscape right with "199" shown (Freeway Drive or a preview with a fake value); no clipping. Landscape `#Preview` |
| R4 | `testRunFeedsSamplesFromProvider`. `! grep -rq "import CoreLocation" Xpeet/Features` |
| R5 | `testNegativeSpeedIsIgnored`, `testNegativeAccuracyIsIgnored` |
| R6 | `testShowsDashesBeforeFirstFix`, `testBecomesAcquiringWhenFixOlderThanFiveSeconds` |
| R7 | `testStationaryShowsZero`, `testSpeedBelowOneKmhShowsZero` |
| R8 | `testDisplayRoundsToWholeUnit`, `testDisplayIsNeverNegative` |
| R9 | `testSmoothingMatchesExponentialMovingAverage` |
| R10 | `testStepUpIsWithinFivePercentByFourthSample`, `testHardBrakeIsWithinFivePercentByFourthSample` |
| R11 | `testFilterResetsAfterAcquiring` |
| R12 | Manual: Freeway Drive, digits roll and the layout does not shift |
| R13 | `testDefaultUnitIsMphForUSAndUK`, `testDefaultUnitIsKmhForMetric` |
| R14 | `testToggleUnitConvertsWithoutResettingFilter`. Manual: tap target ≥ 44 pt (Accessibility Inspector) |
| R15 | `testUnitPersistsAcrossInstances`, `testSavedUnitOverridesLocale` |
| R16 | `testRequestsAuthorizationWhenNotDetermined`. Manual: the fresh-install prompt offers When In Use, never Always |
| R17 | `testDeniedShowsUnavailableWithSettingsButton`, `testRestrictedShowsUnavailableWithoutSettingsButton`, `testServicesOffShowsUnavailable`. Manual: "Open Settings" opens the app's Settings page |
| R18 | `testGrantingPermissionMovesToAcquiringThenLive` |
| R19 | `testRunDisablesIdleTimerAndRestoresOnCancel` |
| R20 | Manual: the location indicator goes away after backgrounding and updates resume on return. `! grep -q UIBackgroundModes project.yml` |
| Weak-signal state | `testWeakSignalWhenAccuracyAboveTwoMetersPerSecond` |
| R21 | `testAccessibilityLabelLive`, `testAccessibilityLabelNoSignal`, `testUnitAccessibilityValue`. Manual: VoiceOver in Accessibility Inspector |
| R22 | Manual: largest accessibility text size, portrait and landscape, no overlap |
| R23 | Manual: white #FFFFFF on black (21:1). Secondary grey chosen ≥ 4.5:1 and checked with Accessibility Inspector's contrast tool |
| R24 | `evals/check.sh` dry-check per case, `evals/run.sh` 3/3, `scripts/check-bands.sh` output |
| R25 | Reviewer pass: `grep -n -E "TabView\|APIClient\|AppState\|Features/Home" CLAUDE.md .claude/skills` returns nothing |

`scripts/verify.sh` ends with `lint: OK` and `** TEST SUCCEEDED **`.
