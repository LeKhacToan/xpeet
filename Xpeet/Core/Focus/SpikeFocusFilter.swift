import AppIntents
import SwiftUI
import UIKit

// THROWAWAY spike for specs/engine-clip-toggle R14. Never merged.

struct SpikeFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Engine sounds"
    static let description: IntentDescription? = IntentDescription(
        "Turns Xpeet's engine sounds off and stops the microphone while this Focus is on."
    )

    @Parameter(title: "Turn off engine sounds", default: false)
    var turnOff: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: turnOff ? "Engine sounds off" : "Engine sounds unchanged")
    }

    func perform() async throws -> some IntentResult {
        let value = turnOff
        await MainActor.run {
            SpikeLog.shared.add("perform turnOff=\(value) appState=\(UIApplication.shared.applicationState.rawValue) scenes=\(UIApplication.shared.connectedScenes.count)")
        }
        return .result()
    }
}

@Observable
@MainActor
final class SpikeLog {
    static let shared = SpikeLog()
    private(set) var lines: [String] = []

    func add(_ line: String) {
        let stamp = Date.now.formatted(date: .omitted, time: .standard)
        lines = Array((lines + ["\(stamp) \(line)"]).suffix(12))
    }

    func readCurrent() async {
        let start = Date.now
        do {
            let filter = try await SpikeFocusFilter.current
            add("current turnOff=\(filter.turnOff) in \(Int(Date.now.timeIntervalSince(start) * 1000)) ms")
        } catch {
            add("current threw \(error) in \(Int(Date.now.timeIntervalSince(start) * 1000)) ms")
        }
    }
}

struct SpikeOverlay: View {
    @Environment(\.scenePhase) private var scenePhase
    private var log = SpikeLog.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(log.lines.enumerated()), id: \.offset) { Text($0.element) }
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.yellow)
        .padding(6)
        .background(.black.opacity(0.8))
        .allowsHitTesting(false)
        .task(id: scenePhase) {
            if scenePhase == .active { await log.readCurrent() }
        }
    }
}
