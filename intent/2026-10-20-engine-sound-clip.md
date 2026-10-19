# Intent: Play a fun clip when the engine starts

**Owner:** toanlk  **Status:** accepted

## Problem
Starting the car or bike with the app open is a dull moment. Viral videos play a short funny voice clip when the engine fires up, and I want the app to do the same, automatically, with no tapping.

## Proposed outcome
- The app starts listening to the microphone as soon as it is opened and in the foreground. There is no toggle.
- When it hears an engine starting (or revving) while the vehicle is still stationary, it plays one short, funny sound file, picked at random from the ones bundled with the app.
- After a clip plays, it does not play again for 60 s.
- Once the vehicle starts moving (the GPS speed is above "stopped"), no clip plays. Listening resumes only while stopped.
- The clip mixes with whatever music is already playing and does not stop it. It plays through the phone speaker or the connected car/Bluetooth audio.
- A clip never triggers itself: the app ignores what it hears while a clip is playing.
- If microphone access is denied, the speedometer works exactly as today. A small status hint explains how to enable it in Settings.

## Affected users & systems
- Users: me (personal use, sideloaded).
- Screens: the speed screen (`SpeedometerView`), for the mic-denied hint only. No new screens.
- System: a new microphone permission, `NSMicrophoneUsageDescription` in `project.yml`. The wording says audio is analysed on the device and never recorded or sent.
- Spec: this intent adds the first sound to the app. It is not tied to speed: it plays only while stopped, so it does not conflict with the "no sounds tied to speed" rule. The spec should state this explicitly in `specs/speedometer/spec.md` Out of scope.

## Constraints
- iOS 17+, Apple frameworks only: on-device sound classification (SoundAnalysis) plus AVFoundation. No third-party code and no networking. No audio is stored or sent.
- Foreground only:
  - No `UIBackgroundModes`. The existing R20 rule stays.
  - Listening stops when the app leaves the screen.
- Clips must be ones I have rights to: original recordings or CC0 sounds, with a licence note in the repo. No copyrighted meme or anime audio is committed.
- Safety:
  - The clip is short (≤ 3 s) and never plays while moving.
  - There are no repeated triggers within 60 s.
- Battery and performance: the speed number must keep updating smoothly while listening.

## Open questions
- **Permission timing.** "Listening starts with the app" means the mic permission is asked at first launch, alongside location. This is acceptable for personal use, but it goes against App Review 5.1.1's "ask in context" spirit if the app is ever distributed.
- **Sound files.** The MVP uses two placeholder files I generated with macOS text-to-speech (`say`). Both are original and come from no meme:
  - `ohayo.m4a`: "おはよう、おにいちゃん！", 1.6 s.
  - `vroom.m4a`: "Vroom vroom! Let's go!", 2.7 s.

  Apple's terms for distributing system voices are unclear, so they are fine for a personal build only. Replace them with my own recordings or CC0 files before any distribution.
- **Detection threshold.** Which sound labels count, and at what confidence? Proposed: `engine_starting`, `engine_accelerating_revving` and `motorcycle`. Tune on a real vehicle, because the simulator only hears the Mac mic.
- **Car hands-free mic.** How a car's hands-free mic behaves is unverified. The phone's built-in mic is the intended input.
- **Out of scope for the MVP:** importing your own clips, a volume setting, and an on/off toggle.
