# Spec: Single-screen speedometer

**Intent:** intent/2026-10-19-speedometer.md  **Status:** approved

## Requirements

### Screen and navigation
- **R1** The app launches straight into one speed screen. There is no `TabView`, no navigation stack and no other screen. The Home and Settings features are removed. *(manual: launch the app; build: no `TabView` in `Xpeet/`)* **Amended** by `specs/gauge-themes/spec.md` R9–R10: one modal face-picker sheet is allowed.
- **R2** The screen always uses the dark appearance with a black background, whatever the system setting is. *(manual, preview)* **Superseded** by `specs/speedometer-gauge/spec.md` R4 (dark gradient background).
- **R3** The app supports portrait, landscape left and landscape right on iPhone. In every orientation the speed number is fully visible and never truncated or clipped, up to 3-digit speeds (e.g. "199"). *(manual: rotate in the simulator; previews in both orientations)*

### Speed reading
- **R4** Speed comes from device location updates configured for automotive navigation, at the highest rate the system provides. The ViewModel reads speed only through a `SpeedProvider` abstraction, never CoreLocation types directly. *(unit: ViewModel tests use a fake provider)* **Amended** by `specs/speed-accuracy/spec.md` R1–R2: fixes carry position and course, and device motion is read through `MotionProvider`.
- **R5** A sample whose speed or speed accuracy is negative counts as invalid. Invalid samples never change the displayed number. *(unit)* **Amended** by `specs/speed-accuracy/spec.md` R13: a fix with no Doppler speed may use position-derived speed (off by default).
- **R6** If there is no valid sample yet, or the last valid sample is more than 5 seconds old, the screen shows "--" and the "Searching for GPS…" status (state **Acquiring**). Exception: if the last valid sample was stationary, the screen keeps showing 0, because iOS pauses updates while the device is not moving. A moving sample that is already more than 5 seconds old when it arrives (e.g. a cached fix at launch) is ignored. *(unit, with an injected clock)* **Amended** by `specs/speed-accuracy/spec.md` R17–R18: a gap starts after 1.5 s without a fix and is flagged as weak signal; the 5 s limit stays for the GPS-only reading.
- **R7** If the provider reports the device as stationary, or the filtered speed is below 1 km/h (0.28 m/s), the displayed speed is exactly 0. *(unit)*
- **R8** The displayed value is the filtered speed rounded to the nearest whole unit (km/h or mph). It is never negative. *(unit)* **Amended** by `specs/speed-accuracy/spec.md` R15: 0.6-unit hysteresis.

### Smoothness
- **R9** Each new valid sample passes through a jitter filter before display: an exponential moving average with smoothing factor α, where α is a named constant (initial value 0.6). *(unit: for a known input sequence, the output equals the hand-computed EMA)* **Superseded** by `specs/speed-accuracy/spec.md` R4–R5 (Kalman filter weighted by speed accuracy).
- **R10** The filter must not lag real driving. After a step change in true speed (e.g. 0 → 60 km/h, or 60 → 0 for hard braking), the displayed value is within 5% of the step size (e.g. within 3 km/h for a 60 km/h step) of the new speed no later than the 4th valid sample after the change. At ~1 Hz that is about 4 seconds. With α = 0.6 the remaining error after 4 samples is 0.4⁴ ≈ 2.6%. *(unit)* **Superseded** by `specs/speed-accuracy/spec.md` R5, R27.
- **R11** The filter resets when updates resume after an Acquiring period, so a stale value is never blended into a new fix. *(unit)* **Superseded** by `specs/speed-accuracy/spec.md` R19.
- **R12** When the displayed number changes, it animates digit by digit (numeric content transition) instead of jumping. Digits use a monospaced form so the layout does not shift as the value changes. *(manual: simulator Freeway Drive)* **Amended** by `specs/speed-accuracy/spec.md` R16: at most 0.1 s, linear.

### Units
- **R13** Supported units are km/h and mph. The default on first launch is mph if the device locale's measurement system is US or UK, and km/h otherwise. *(unit: injected `Locale`)*
- **R14** One control on the screen switches between km/h and mph. Tapping the unit label is the control, and it needs at least a 44×44 pt hit area. The displayed number converts immediately, with no reset of the filter. *(unit + manual)*
- **R15** The selected unit is saved locally and restored on the next launch. A saved choice takes priority over the locale default. *(unit: injected `UserDefaults` suite)*

### Permission and errors
- **R16** On first launch, with permission not determined, the app requests When In Use location permission. It never requests Always. *(manual: fresh simulator install)*
- **R17** If permission is denied or restricted, or Location Services is off, the screen shows "--" with a short message saying why ("Location access is off" / "Location Services is off"). For the denied case it also shows an "Open Settings" button that opens the app's page in iOS Settings. This is state **Unavailable**. *(unit: state mapping; manual: the button)*
- **R18** If permission is granted later (e.g. the user returns from Settings), the screen moves to Acquiring and then Live with no restart. *(unit: fake provider authorization change)*

### Lifecycle
- **R19** While the speed screen is visible and the app is active, the screen does not auto-lock. When the app leaves the active state, the idle timer is restored to its normal behaviour. *(manual; unit if the idle-timer switch is behind an injected closure)*
- **R20** Location updates run only while the app is in the foreground. They stop when the app goes to the background and resume on return. There is no background location mode. *(manual: the location arrow disappears in the background; `project.yml` has no `UIBackgroundModes`)*

### Accessibility
- **R21** VoiceOver reads the speed as one element, e.g. "54 kilometers per hour" or "No GPS signal", and the element has the "updates frequently" trait. The unit control has the label "Unit" and a value of "kilometers per hour" or "miles per hour", plus the hint "Double-tap to switch". *(manual: Accessibility Inspector; unit for the label strings)*
- **R22** The speed number is a fixed hero size, scaled down only to fit the screen. The unit label, status text and button follow Dynamic Type up to accessibility sizes without overlapping the number. *(manual: largest Dynamic Type size in both orientations)*
- **R23** Text contrast against the background is at least 7:1 for the number and 4.5:1 for secondary text. *(manual)*

### Repo tooling
- **R24** The eval cases in `evals/cases/` are rewritten so they target the speedometer code instead of Home, Settings and tabs. There are still at least three cases: one bug fix, one small change, one new tested feature. All checks pass on `main` once this ships. *(run `evals/run.sh`, then `scripts/check-bands.sh`)*
- **R25** The CLAUDE.md Architecture section and `.claude/skills/swiftui-feature/SKILL.md` describe the single-screen structure (no `TabView`, no `APIClient`, the `Core/Location` provider pattern) instead of the Home and tab pattern. *(review)*

## User flows & UI

**Launch.** The app opens on the speed screen. On first launch iOS shows the When In Use prompt above the screen, which is in the Acquiring state.

**Layout.** Black background with three elements:
1. **Speed number** at the centre. SF Rounded, heavy weight, as large as fits (about 50% of the shorter screen side), white, monospaced digits.
2. **Unit label** ("km/h" / "mph") directly below the number in a smaller rounded font and a secondary grey. It is the unit toggle.
3. **Status line**, small and secondary, at the bottom edge. It shows only when there is something to say.

In landscape the number and unit stay centred. The number scales to the screen height, and the status line stays at the bottom. There are no other buttons, icons, gauges or colours. One accent colour is used only for the "Open Settings" button.

> **Superseded:** the layout and colours are now defined by `specs/speedometer-gauge/spec.md` (arc gauge, unit pill, status chip, brand colour).

| State | Number | Status line | Extra |
|---|---|---|---|
| **Acquiring** (loading): no fix yet, fix older than 5 s, or permission just granted | `--` | "Searching for GPS…" | none |
| **Live** (success) | filtered speed, e.g. `54` | hidden | none |
| **Live, weak signal** (degraded): valid sample but speed accuracy > 2 m/s (~7 km/h). **Superseded** by `specs/speed-accuracy/spec.md` R20: estimate σ > 0.5 m/s, or a gap | filtered speed | "Weak GPS signal" | none |
| **Unavailable** (error): denied, restricted or Location Services off | `--` | reason text (R17) | "Open Settings" button when denied |

There is no empty state. "No fix yet" is the Acquiring state.

**Unit switch.** Tap the unit label. The number and label change at once and the choice is saved.

**Accessibility.** See R21–R23. The speed element does not announce every update by itself; VoiceOver reads the current value when focused.

## Data & API

No network. `APIClient` and `Core/Networking/` are removed because nothing uses them.

- **`SpeedSample`** (value type in `Core/Location`): `metersPerSecond: Double`, `accuracy: Double` (m/s, negative = invalid), `isStationary: Bool`, `timestamp: Date`.
- **`SpeedProvider`** (protocol in `Core/Location`): an async stream of samples, the current authorization state (`notDetermined`, `authorized`, `denied`, `restricted`, `servicesOff`) with changes over time, and `requestAuthorization()`.
- **`CoreLocationSpeedProvider`**: the production implementation. It wraps `CLLocationUpdate.liveUpdates(.automotiveNavigation)` and maps each update to `SpeedSample`. It owns a `CLLocationManager` only for the When In Use request and authorization status.
- **`SpeedometerViewModel`** (`@Observable`, `@MainActor`): its init takes the provider, `UserDefaults`, `Locale` and a clock (`() -> Date`), all with production defaults. It exposes `state`, `displayText`, `unit`, `toggleUnit()` and `func run() async`. `run()` is called from the View's `.task` and cancelled automatically when the view disappears or the app backgrounds.
- **Persistence:** one `UserDefaults` key, `speedUnit` (`"kmh"` / `"mph"`). Nothing else is stored.
- **Conversion:** use `Measurement<UnitSpeed>` from `.metersPerSecond` to `.kilometersPerHour` or `.milesPerHour`.
- **Offline:** fully offline by design. GPS needs no network.

## Non-functional
- **Privacy:**
  - Location is used only in memory to compute the current speed. It is never stored, logged or sent anywhere. **Exception** (`specs/speed-accuracy/spec.md` R22): Debug builds launched with `-XpeetRecordDrives YES` record drives to the phone.
  - Add `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` in `project.yml` with this string: "Xpeet uses your location only to show your current speed. It never leaves your device."
  - No ATT, no analytics, no third-party code.
- **Performance:**
  - Show the first Live value within one sample of the first valid fix. There is no extra warm-up delay beyond R9's filter.
  - The view does nothing per frame. It redraws only on a new sample. **Exception** (`specs/speed-mascot/spec.md` R9): the mascot blinks every 3–6 s. **Exception** (`specs/speed-accuracy/spec.md` R14): with fusion on, the shown value refreshes about 10 times a second.
  - Battery cost is that of foreground GPS. Updates stop in the background (R20).
- **Localization:** English UI strings for v1, written in a String Catalog-friendly form (`String(localized:)`/`Text("…")`). Number formatting uses the current locale.
- **Orientation:** `project.yml` adds `UIInterfaceOrientationLandscapeLeft` and `UIInterfaceOrientationLandscapeRight` to the iPhone orientations.

## Out of scope
- Background or locked-screen speed tracking, CarPlay, Live Activities and widgets.
- ~~Arc gauge~~ (now in `specs/speedometer-gauge/spec.md`), ~~needle gauge~~ (now in `specs/gauge-themes/spec.md`), HUD mirror mode, trip statistics (max, average, distance, time).
- Speed-limit data, over-speed alerts, speed-based colours or sounds (the engine-start sound in `specs/engine-sound-clip/spec.md` is not speed-based: it only plays while stopped). **Exception** (`specs/speed-mascot/spec.md`): the mascot's expression follows speed; gauge colours still never do.
- Privacy-policy link, App Store metadata, privacy nutrition label (not distributed).
- Settings screen (except the face picker sheet in `specs/gauge-themes/spec.md`), app version display, onboarding screens.
- Units other than km/h and mph (e.g. knots, m/s).
- Fallback permission flows for iOS 17 beyond the system When In Use prompt (owner decision, see Open questions).

## Flagged concerns
- **Privacy, new permission:** this adds When In Use location and its Info.plist usage string (see Non-functional). REVIEW.md treats a new permission as a security/privacy review item. The owner (toanlk) has accepted it in the intent.
- **Privacy manifest:** `UserDefaults` is a required-reason API (`NSPrivacyAccessedAPICategoryUserDefaults`, reason CA92.1). A privacy manifest is only enforced for App Store or TestFlight distribution, so it is not needed for a personal sideloaded build. If the app is ever distributed, add `PrivacyInfo.xcprivacy` and confirm XcodeGen bundles it.
- **App Store Review Guidelines 1.4.4 / 1.4.5 (driving safety):** not binding because the app is not distributed. The spec still follows them: no speed-based colour or alerts, and no interaction needed while driving.
- **Repo tooling and CLAUDE.md:** R24 and R25 change `CLAUDE.md`, `.claude/skills/**` and `evals/cases/**`. Per docs/ai-sdlc.md, the owner must approve these and re-run `evals/run.sh` + `scripts/check-bands.sh`. The owner asked for the eval rewrite. Band history from older runs will not match the new cases, so a new baseline is expected.
- **Unverified locally:** only an iOS 27.1 simulator is installed, so iOS 17 behaviour of `liveUpdates` and the permission prompt is not tested here. The owner accepts this risk (Decisions in the intent).

## Open questions
Carried from the intent:
- *Does the When In Use prompt work on iOS 17 with the location-updates API?* **Answered (owner):** yes, assume it works. No fallback flow.
- *How much smoothing is acceptable?* **Answered (owner):** as smooth as achievable while still tracking real driving. This spec turns that into R9–R12: EMA α = 0.6, within 5% of the step by the 4th sample after a step, and animated digits. α may be tuned during build as long as R10 still passes.
- *Arc gauge, HUD mirror mode, trip max/average, CarPlay?* **Still open, deferred:** listed under Out of scope for a later intent.

Raised by this spec:
- *Thresholds:* 5 s stale timeout (R6), 1 km/h zero clamp (R7), 2 m/s weak-signal accuracy (Live, weak signal state). These are the spec's defaults and can be changed in review.
