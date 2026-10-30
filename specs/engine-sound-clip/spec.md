# Spec: Play a fun sound when the engine starts

**Intent:** intent/2026-10-20-engine-sound-clip.md  **Status:** approved

This spec adds on-device engine-sound detection through the microphone, and plays a short bundled sound file while the vehicle is stopped.

Notes on the earlier specs:
- It clarifies `specs/speedometer/spec.md` Out of scope "speed-based colours or sounds", gauge R3 and gauge-themes R7 ("no haptics or sounds tied to speed"). This sound is not tied to speed: the only speed input is a gate that silences it once moving (R6).
- Speedometer R20 (foreground only, no `UIBackgroundModes`) stays in force.

Research: the researcher agent's findings, from 2026-10-20, are summarised under Flagged concerns and Data & API.

## Requirements

### Listening
- **R1** Listening runs in the same lifecycle as location (speedometer R20):
  - It starts when the speed screen is active and the microphone is authorised.
  - It stops when the app leaves the active state, and resumes on return.

  There is no background audio mode and no toggle. *(unit: the fake detector is started and stopped with `run()`. build: `project.yml` has no `UIBackgroundModes`)*

- **R2** Microphone permission is requested once, automatically. The request is made after the location permission is no longer "not determined", so the two system prompts never stack. It is never requested again after the user answers. *(unit: request order with fakes. manual: fresh install)*

- **R3** Detection uses Apple's built-in on-device sound classifier. A detection event fires when all of these hold:
  - One of the trigger labels (`engine_starting`, `engine_accelerating_revving`, `motorcycle`) has confidence ≥ 0.6.
  - That happens in 2 consecutive analysis windows.
  - Each window is about 1.5 s, with 50% overlap.

  The labels, the confidence and the window count are named constants. *(unit: the event rule on fake classification results. manual: device test with a real engine)*

- **R4** Audio is analysed in memory only. Nothing is recorded, stored, logged or sent. *(review)*

### Playing
- **R5** On a detection event, the app plays one bundled sound file chosen at random. The choice uses an injectable random source:
  - `ohayo.m4a`
  - `vroom.m4a`

  Each is at most 3 s long. *(unit: the selection uses the injected random source; both files reachable)*

- **R6** No sound plays while the vehicle is moving. Moving means the speedometer's displayed speed is above 0.
  - When the speed is 0, `--` (Acquiring), or Unavailable (e.g. location denied, so movement is unknown), the vehicle counts as stopped. A sound may play.
  - Detection events while moving are dropped, not queued.

  *(unit)*

- **R7** Cooldown:
  - After a sound starts, no other sound plays for 60 s. The 60 s is a named constant measured with the injected clock.
  - Events during the cooldown are dropped.
  - A sound that fails to play does not start the cooldown.

  *(unit)*

- **R8** No self-trigger: detection events that arrive while a sound is playing, or within 0.5 s after it ends, are dropped. *(unit)*

- **R9** Audio session behaviour:
  - Play-and-record.
  - Mixes with other audio, so the user's music keeps playing and is not paused.
  - Plays through the speaker, or a connected Bluetooth or car audio output.
  - The phone's built-in mic stays the input. The app never switches the car into hands-free "call" mode.

  Volume follows the system volume. *(manual: device with music playing, with and without Bluetooth)*

- **R10** Interruptions:
  - A phone call or Siri stops listening. When the interruption ends and the app is active, listening resumes.
  - A change of audio route (e.g. Bluetooth connects) does not crash the app. Listening continues or restarts.

  *(manual)*

### Permission and errors
- **R11** Microphone denied or restricted:
  - The speedometer works exactly as before.
  - When there is no location status to show, a chip shows `mic.slash` and "Microphone off: enable it in Settings to hear engine sounds". The location status chip (gauge R6) takes priority. **Amended** by `specs/break-reminder/spec.md` R10: the mic chip shows only when there is no location status and no break reminder.

  *(unit: chip text/priority. manual)*

- **R12** If listening cannot start (no input device, the classifier fails, or the engine errors), the feature silently stays off for that session. The speedometer is unaffected and no error is shown. *(unit with a failing fake detector)*

### Accessibility
- **R13** The mic chip follows the existing chip rules:
  - Its icon is hidden from VoiceOver and its text is read.
  - Dynamic Type follows speedometer R22.

  A sound is decorative audio. VoiceOver speech and the sound may overlap, which is accepted. *(manual)*

## User flows & UI

**First launch.**
1. The location prompt appears. The user answers it.
2. The microphone prompt appears.
3. If allowed, listening starts and iOS shows the orange mic indicator.

**Stopped, engine starts.**
1. About 1–3 s after the engine sound, a random sound plays. Music keeps playing underneath.
2. For the next 60 s, nothing else plays.

**Moving.** Engine noise is ignored. Once stopped again (displayed speed 0) and the 60 s cooldown has passed, a rev or start can trigger a sound again.

| State | Listening | Sound may play | UI |
|---|---|---|---|
| Mic not determined | no | no | none (the prompt is pending) |
| Mic authorised, stopped, cooldown over | yes | yes | none |
| Mic authorised, moving | yes | no | none |
| Mic authorised, in cooldown or playing | yes | no | none |
| Mic denied or restricted | no | no | mic chip, unless a location chip or the break reminder is showing |
| Listening failed (R12) | no | no | none |
| App in background | no | no | none |

There is no in-app "listening" indicator beyond the system mic indicator.

## Data & API
- **`Core/Audio/`** is the only code that imports AVFoundation or SoundAnalysis, mirroring `Core/Location`.
  - **`SoundTriggerDetector`** (`@MainActor` protocol). It provides:
    - `authorizationUpdates() -> AsyncStream<MicAuthorization>`
    - `requestAuthorization()`
    - `events() -> AsyncStream<SoundTriggerEvent>`, where cancelling the stream stops the audio engine
    - `pause()` / `resume()`

    `SoundTriggerEvent` holds the label, the confidence and the timestamp.
  - **`SoundAnalysisTriggerDetector`** (production):
    - `AVAudioEngine` input tap, feeding `SNAudioStreamAnalyzer` with `SNClassifySoundRequest(classifierIdentifier: .version1)`.
    - Analysis runs on a serial queue, never the main thread. Results are bridged into the `AsyncStream`.
  - **`SoundPlayer`** protocol: `play(_ file: SoundFile) async throws`. It has an `AVAudioPlayer` implementation.
  - **Fakes**: `FakeSoundTriggerDetector` and `FakeSoundPlayer`, behind `#if DEBUG`.
  - **Permission**: `AVAudioApplication.requestRecordPermission()` (iOS 17).
- **Logic:** an `@Observable @MainActor` ViewModel with synchronous handlers. It applies:
  - R2 ordering
  - R3 consecutive windows
  - R6 moving gate
  - R7 cooldown
  - R8 playback gate
  - R11 chip

  Its inputs are injected (detector, player, clock, random source), all with production defaults. It reads "moving" from `SpeedometerViewModel.displayedSpeed`. The plan decides whether this is a new `Features/EngineSound/EngineSoundViewModel` fed by the speedometer, or part of `SpeedometerViewModel`.
- **Resources:** `Xpeet/Resources/Sounds/ohayo.m4a`, `vroom.m4a`, plus `Xpeet/Resources/Sounds/SOUNDS-LICENSE.txt`. The licence file records the provenance (macOS `say` text-to-speech, voices Flo ja-JP / Boing, generated 2026-10-20, placeholder for a personal build only).
- **Info.plist:** add `INFOPLIST_KEY_NSMicrophoneUsageDescription` in `project.yml` (target settings, next to the location string): "Xpeet listens for engine sounds to play a fun clip. Audio is analysed on your device and never recorded or sent anywhere."
- **Persistence:** none.

## Non-functional
- **Performance:**
  - The speed number keeps updating at sample rate while listening.
  - Analysis stays off the main thread.
  - Battery cost (mic plus classifier at about 1 analysis per 0.75 s) is to be measured once on a device with the Xcode energy gauge.
- **Privacy:**
  - A new microphone permission (see Flagged concerns).
  - Audio is in memory only: no recording, no storage, no network (R4).
  - No analytics.
- **Localization:** the new strings are written with `String(localized:)`:
  - the mic chip text
  - the usage description, in the String Catalog-friendly plist key
- **Compatibility:** iOS 17 APIs only. SoundAnalysis and AVFAudio are system frameworks, so there is no third-party code.

## Out of scope
- Importing your own sound files, a volume setting, choosing which sound plays, and an on/off toggle.
- Background or screen-off listening, and CarPlay.
- A custom-trained (Create ML) classifier, and a manual sensitivity setting.
- Copyrighted meme or anime audio in the repo.
- Showing detection confidence or a "listening" indicator in the app.

## Flagged concerns
- **Privacy: new permission (owner review per REVIEW.md):**
  - The microphone permission and usage string are added.
  - The prompt is shown automatically at first launch rather than on a user action (R2). That goes against App Review 5.1.1's "request in context" guidance. It is accepted for a personal sideloaded build, but must be revisited before any distribution, with an opt-in toggle.
  - If the app is distributed, the privacy nutrition label is "Data Not Collected" for audio (on-device only).
- **IP and licensing:**
  - The two sound files are generated with macOS text-to-speech. Apple's licence terms for redistributing system voices in an app are unclear, so they are placeholders for a personal build only (recorded in `SOUNDS-LICENSE.txt`).
  - Replace them with your own recordings, or verified CC0 files, before distribution.
  - No meme audio.
- **Driving safety (App Review 1.4.4/1.4.5, not binding):**
  - A sound never plays while moving (R6).
  - Each sound is ≤ 3 s, with a 60 s cooldown (R7).
  - It mixes with music rather than interrupting it.
- **Detection accuracy is unverified:**
  - Apple publishes no per-class accuracy.
  - The researcher confirmed the trigger labels exist in `.version1` on macOS. The iOS label list is assumed to be the same, but this is not verified on a device.
  - Thresholds (R3) need tuning in a real car or on a real bike. The simulator only hears the Mac mic.
  - In-cabin music may cause misses or false triggers.
- **UX limit:** the app must already be open and active before the engine starts (R1). In practice, revving may trigger more often than ignition.
- **Car hands-free mic:** behaviour is unverified. The spec keeps the built-in mic as input by not enabling the hands-free Bluetooth profile (R9).
- **CLAUDE.md Architecture:** a new `Core/Audio/` folder, which becomes the only importer of AVFoundation and SoundAnalysis. This needs a one-line CLAUDE.md update: owner approval plus an eval re-run (docs/ai-sdlc.md).
- **Unverified locally:** only an iOS 27.1 simulator is installed. Neither iOS 17 behaviour nor real-device audio routing is tested here.

## Open questions
Carried from the intent:
- *Permission timing?* **Answered (owner):** listening starts with the app, so the mic prompt comes at first launch, after location (R2). This is flagged for distribution.
- *Which sounds, one or several?* **Answered (owner):** two TTS placeholder files, chosen at random (R5).
- *Detection labels and confidence?* **Answered (this spec, defaults):** R3. To be tuned on a device.
- *Car hands-free mic?* **Still open:** built-in mic intended (R9). To be verified on a device.
- *Import, volume setting, toggle?* **Deferred**, see Out of scope.
- *Trigger only at app start vs. revving?* **Answered (owner):** listening runs while the app is open and active. A start or rev while stopped triggers it.
- *Cooldown?* **Answered (owner):** 60 s (R7).
- *Mute while moving?* **Answered (owner):** yes, no sound once the vehicle moves (R6).

Raised by this spec:
- *Should the mic-denied chip be permanent?* Since there is no toggle, a user who deliberately denies the mic sees the chip whenever there is no location status. Proposed: keep it for the MVP. The owner may choose to hide it instead.
