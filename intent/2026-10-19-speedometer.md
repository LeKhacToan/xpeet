# Intent: Single-screen speedometer

**Owner:** toanlk  **Status:** accepted

## Problem
I want to see my current speed at a glance while driving, on a phone mounted in the car.
The car's own speedometer is not always easy to read, and generic speedometer apps are cluttered, full of ads, or need many taps.
Xpeet is still a template (Home tap counter, Settings tab) and does nothing useful yet.

## Proposed outcome
- Opening the app shows one screen: the current speed as a very large number with its unit. There are no tabs and no other screens.
- The number updates continuously while driving and is readable at arm's length in a single glance, day or night.
- When there is no GPS fix the screen says so clearly (for example "--" plus a short status), instead of showing a wrong number.
- One control switches between km/h and mph. The choice is remembered across launches. The first launch defaults to the device's region.
- The screen stays awake while the app is open. Nothing is needed while driving beyond looking at it.
- The layout works in both portrait and landscape, so it fits any phone mount.
- The look is modern and minimal: a dark background, high contrast, and nothing on screen that isn't needed.

## Affected users & systems
- Users: me (personal use, sideloaded via Xcode, not distributed on the App Store).
- Screens: replaces the Home and Settings tabs with a single speed screen; the TabView goes away.
- Systems: device location (When In Use permission only), local storage for the unit preference. No backend, no networking, no analytics.
- Repo tooling: the eval cases in `evals/cases/` (they target Home, Settings and the tabs), the CLAUDE.md Architecture line and the `swiftui-feature` skill all describe the old template and must be rewritten for the new app.

## Constraints
- iOS 17+, SwiftUI, no third-party dependencies (per CLAUDE.md).
- Location is used only while the app is in the foreground. It does not track in the background or when the screen is locked.
- Location and speed data never leave the device.
- No App Store submission, so no privacy-policy link or store metadata is needed.
- Must not encourage speeding: no speed-based alerts or colors in this version.

## Decisions
- Permission prompt: the owner confirms the When In Use prompt works with the location-updates API on the target devices. No extra fallback flow is needed.
- Smoothness: the speed display should be as smooth as achievable. Use the highest location update rate available, filter out GPS jitter, and animate between values so the number never jumps. It still has to track real acceleration and braking without noticeable lag.

## Open questions
- Out of scope for now, maybe later: arc gauge, HUD mirror mode, trip max/average, CarPlay.
