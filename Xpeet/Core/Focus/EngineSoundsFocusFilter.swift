import AppIntents

/// The "Engine sounds" Focus filter (specs/engine-clip-toggle R15). iOS runs `perform()` when a Focus that uses it
/// starts, and again with the default ("unchanged") when it ends.
struct EngineSoundsFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Engine sounds"
    static let description: IntentDescription? = IntentDescription(
        "Turns Xpeet's engine sounds off and stops the microphone while this Focus is on."
    )

    /// Default false: the value iOS sends when the Focus ends must mean "no change".
    @Parameter(title: "Turn off engine sounds", default: false)
    var turnOff: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: turnOff ? "Engine sounds off" : "Engine sounds unchanged")
    }

    /// Only hands the value to the relay. iOS may run this in a process with no scene; nothing starts from here (R17).
    func perform() async throws -> some IntentResult {
        let turnOff = turnOff
        await FocusFilterRelay.shared.deliver(turnOff)
        return .result()
    }
}

/// Passes each `perform()` to the running provider, in memory only (R17).
@MainActor
final class FocusFilterRelay {
    static let shared = FocusFilterRelay()

    private var receivers: [UUID: (Bool) -> Void] = [:]

    func add(_ receiver: @escaping (Bool) -> Void) -> UUID {
        let id = UUID()
        receivers[id] = receiver
        return id
    }

    func remove(_ id: UUID) {
        receivers[id] = nil
    }

    func deliver(_ turnOff: Bool) {
        receivers.values.forEach { $0(turnOff) }
    }
}
