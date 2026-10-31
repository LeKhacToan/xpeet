import Foundation

/// The "Engine sounds" Focus filter's effect on engine sound (specs/engine-clip-toggle R16-R18). The stored switch
/// is never changed by it.
extension SpeedometerViewModel {
    /// True while a Focus has "Turn off engine sounds" on. The sheet shows the switch off and disabled (R18).
    var engineSoundsOffByFocus: Bool { focusOverride == true }

    /// Engine sound runs with the switch on and no Focus override. An override not yet known counts as one (R17).
    var engineSoundsEffective: Bool { engineSoundsOn && focusOverride == false }

    /// A value from the filter: a run's first value, or a `perform()` (R16, R17).
    func handle(focusOverride override: Bool) {
        // The Focus ended: listening resumes, but a mic prompt waits for the next run or the user's switch (R16).
        if focusOverride == true, !override { engineSound.holdMicPrompt() }
        focusOverride = override
        engineSound.handle(enabled: engineSoundsEffective)
    }

    /// Each run starts with the override unknown, so nothing listens or prompts until the filter answers (R17).
    /// A mic prompt held since a Focus ended may then follow (R16).
    func beginFocusRun() {
        if focusFilter != nil { focusOverride = nil }
        engineSound.handle(enabled: engineSoundsEffective)
        engineSound.releaseMicPrompt()
    }

    func runFocusFilter() async {
        guard let focusFilter else { return }
        for await override in focusFilter.updates() {
            handle(focusOverride: override)
        }
    }
}
