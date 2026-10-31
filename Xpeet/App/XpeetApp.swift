import SwiftUI

@main
struct XpeetApp: App {
    init() {
        // THROWAWAY spike (specs/engine-clip-toggle R14).
        MainActor.assumeIsolated { SpikeLog.shared.add("process launched") }
    }

    var body: some Scene {
        WindowGroup {
            SpeedometerView()
                .overlay(alignment: .bottom) { SpikeOverlay().padding(.bottom, 120) }
        }
    }
}
