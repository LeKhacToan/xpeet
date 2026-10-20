import SwiftUI

/// Asset names of the mascot artwork (specs/ui-redesign R1). Sources: `Resources/MASCOT-SOURCE.txt`.
enum MascotArtwork {
    /// Calm with closed eyes, swapped in for a blink.
    static let blink = "Mascot/blink"

    static func assetName(for mood: Mood) -> String {
        "Mascot/\(mood)"
    }
}

/// The mascot as a round portrait badge, one rendered image per mood (specs/ui-redesign R1–R6).
/// Decorative: VoiceOver ignores it, the number carries the speed. The theme only tints the glow ring.
struct MascotView: View {
    let mood: Mood
    let theme: Theme
    /// Off for previews and tests of a single frame.
    var blinks = true

    @State private var eyesClosed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private static let blinkDuration: Duration = .milliseconds(150)
    private static let blinkGap: ClosedRange<Double> = 3...6

    /// The blink frame is calm's face, so only calm blinks (R3).
    private var canBlink: Bool { blinks && !reduceMotion && mood == .calm && scenePhase == .active }

    private var assetName: String {
        eyesClosed && mood == .calm ? MascotArtwork.blink : MascotArtwork.assetName(for: mood)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                // Static glow ring in the face's accent, as in the Stitch frames.
                Circle()
                    .fill(Color(hex: theme.accent).opacity(0.18))
                    .blur(radius: size * 0.06)
                    .frame(width: size, height: size)
                Image(assetName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: size * 0.92, height: size * 0.92)
                    .clipShape(Circle())
                    .overlay {
                        Circle().strokeBorder(Color(hex: theme.accent).opacity(0.55), lineWidth: max(1, size * 0.02))
                    }
                    .shadow(color: .black.opacity(0.35), radius: size * 0.05, y: size * 0.03)
                    .id(mood)
                    .transition(.opacity)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: mood)
        .accessibilityHidden(true)
        .task(id: canBlink) {
            guard canBlink else { eyesClosed = false; return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: Self.blinkGap)))
                guard !Task.isCancelled else { break }
                eyesClosed = true
                try? await Task.sleep(for: Self.blinkDuration)
                eyesClosed = false
            }
        }
    }
}

// MARK: - Previews

#Preview("Moods × faces") {
    ScrollView {
        VStack(spacing: 0) {
            ForEach(GaugeFace.allCases) { face in
                HStack(spacing: 8) {
                    ForEach(Mood.allCases, id: \.self) { mood in
                        MascotView(mood: mood, theme: face.theme, blinks: false)
                            .frame(width: 48, height: 48)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(face.theme.backgroundGradient)
            }
        }
    }
}

#Preview("Large, blinking") {
    HStack(spacing: 24) {
        MascotView(mood: .calm, theme: .minimalRing)
        MascotView(mood: .worried, theme: .retro)
    }
    .frame(height: 160)
    .padding(40)
    .background(Theme.minimalRing.backgroundGradient)
}
