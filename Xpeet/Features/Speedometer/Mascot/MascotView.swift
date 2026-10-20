import SwiftUI

/// An original kawaii face drawn with shapes. Decorative: VoiceOver ignores it, the number carries the speed.
/// Colours come from the active face's theme so it fits every gauge style.
struct MascotView: View {
    let mood: Mood
    let theme: Theme
    /// Off for previews and tests of a single frame.
    var blinks = true

    @State private var eyesClosed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// Fraction of the background the face fill shows through.
    static let fillOpacity = 0.2
    private static let blinkDuration: Duration = .milliseconds(150)
    private static let blinkGap: ClosedRange<Double> = 3...6

    private var ink: Color { Color(hex: theme.number) }
    private var fill: Color { Color(hex: theme.accent) }
    private var canBlink: Bool { blinks && !reduceMotion && mood != .sleepy && scenePhase == .active }

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle()
                    .fill(fill.opacity(Self.fillOpacity))
                    .overlay { Circle().strokeBorder(fill.opacity(0.5), lineWidth: size * 0.04) }
                face(size: size)
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

    // MARK: - Features

    @ViewBuilder
    private func face(size: CGFloat) -> some View {
        let unit = size / 100
        ZStack {
            eyes(unit: unit)
            mouth(unit: unit)
            accessories(unit: unit)
        }
    }

    @ViewBuilder
    private func eyes(unit: CGFloat) -> some View {
        let spacing = 36 * unit
        let y = -8 * unit
        switch mood {
        case .sleepy:
            // Closed, curved down: a content sleeper.
            HStack(spacing: spacing - 12 * unit) {
                ClosedEye().stroke(ink, style: StrokeStyle(lineWidth: 4 * unit, lineCap: .round)).frame(width: 12 * unit, height: 6 * unit)
                ClosedEye().stroke(ink, style: StrokeStyle(lineWidth: 4 * unit, lineCap: .round)).frame(width: 12 * unit, height: 6 * unit)
            }
            .offset(y: y)
        case _ where eyesClosed:
            HStack(spacing: spacing - 10 * unit) {
                Capsule().fill(ink).frame(width: 10 * unit, height: 3.5 * unit)
                Capsule().fill(ink).frame(width: 10 * unit, height: 3.5 * unit)
            }
            .offset(y: y)
        case .searching:
            // Dot eyes glancing to the side.
            HStack(spacing: spacing) {
                Circle().fill(ink).frame(width: 9 * unit)
                Circle().fill(ink).frame(width: 9 * unit)
            }
            .offset(x: 6 * unit, y: y)
        case .calm, .happy:
            HStack(spacing: spacing) {
                Circle().fill(ink).frame(width: 9 * unit)
                Circle().fill(ink).frame(width: 9 * unit)
            }
            .offset(y: y)
        case .worried:
            // Wide eyes: a ring with a small pupil.
            HStack(spacing: spacing - 6 * unit) {
                wideEye(unit: unit, diameter: 15 * unit, pupil: 6 * unit)
                wideEye(unit: unit, diameter: 15 * unit, pupil: 6 * unit)
            }
            .offset(y: y)
        case .startled:
            HStack(spacing: spacing - 10 * unit) {
                wideEye(unit: unit, diameter: 19 * unit, pupil: 7 * unit)
                wideEye(unit: unit, diameter: 19 * unit, pupil: 7 * unit)
            }
            .offset(y: y)
        }
    }

    private func wideEye(unit: CGFloat, diameter: CGFloat, pupil: CGFloat) -> some View {
        Circle()
            .strokeBorder(ink, lineWidth: 2.5 * unit)
            .overlay { Circle().fill(ink).frame(width: pupil) }
            .frame(width: diameter, height: diameter)
    }

    @ViewBuilder
    private func mouth(unit: CGFloat) -> some View {
        let y = 18 * unit
        let stroke = StrokeStyle(lineWidth: 4 * unit, lineCap: .round)
        switch mood {
        case .searching, .sleepy:
            Capsule().fill(ink).frame(width: 10 * unit, height: 3.5 * unit).offset(y: y)
        case .calm:
            Smile(curve: 0.3).stroke(ink, style: stroke).frame(width: 18 * unit, height: 8 * unit).offset(y: y)
        case .happy:
            Smile(curve: 1).stroke(ink, style: stroke).frame(width: 34 * unit, height: 16 * unit).offset(y: y - 2 * unit)
        case .worried:
            Wave().stroke(ink, style: stroke).frame(width: 26 * unit, height: 8 * unit).offset(y: y)
        case .startled:
            Circle().strokeBorder(ink, lineWidth: 3.5 * unit).frame(width: 14 * unit, height: 14 * unit).offset(y: y + 2 * unit)
        }
    }

    @ViewBuilder
    private func accessories(unit: CGFloat) -> some View {
        switch mood {
        case .happy:
            // Blush.
            HStack(spacing: 56 * unit) {
                Circle().fill(fill.opacity(0.7)).frame(width: 11 * unit)
                Circle().fill(fill.opacity(0.7)).frame(width: 11 * unit)
            }
            .offset(y: 8 * unit)
        case .sleepy:
            Text(verbatim: "z")
                .font(.system(size: 22 * unit, weight: .heavy, design: .rounded))
                .foregroundStyle(ink)
                .offset(x: 34 * unit, y: -34 * unit)
        case .worried:
            // Sweat drop.
            Drop().fill(ink.opacity(0.8)).frame(width: 9 * unit, height: 14 * unit).offset(x: 36 * unit, y: -22 * unit)
        case .startled:
            Text(verbatim: "!")
                .font(.system(size: 26 * unit, weight: .black, design: .rounded))
                .foregroundStyle(ink)
                .offset(x: 40 * unit, y: -34 * unit)
        case .searching, .calm:
            EmptyView()
        }
    }
}

// MARK: - Shapes

/// A smile; `curve` 0 is flat, 1 bends the full height.
private struct Smile: Shape {
    var curve: Double
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.minY + rect.height * 2 * curve)
        )
        return path
    }
}

private struct ClosedEye: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY + rect.height))
        return path
    }
}

private struct Wave: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let quarter = rect.width / 4
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + 2 * quarter, y: rect.midY),
            control: CGPoint(x: rect.minX + quarter, y: rect.minY - rect.height / 2)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control: CGPoint(x: rect.minX + 3 * quarter, y: rect.maxY + rect.height / 2)
        )
        return path
    }
}

private struct Drop: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: CGPoint(x: rect.maxX + rect.width / 2, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.minX - rect.width / 2, y: rect.maxY))
        return path
    }
}

// MARK: - Previews

#Preview("Moods × faces") {
    ScrollView {
        VStack(spacing: 0) {
            ForEach(GaugeFace.allCases) { face in
                HStack(spacing: 12) {
                    ForEach(Mood.allCases, id: \.self) { mood in
                        MascotView(mood: mood, theme: face.theme, blinks: false)
                            .frame(width: 56, height: 56)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(face.theme.backgroundGradient)
            }
        }
    }
}

#Preview("Blinking") {
    MascotView(mood: .happy, theme: .minimalRing)
        .frame(width: 120, height: 120)
        .padding(40)
        .background(Theme.minimalRing.backgroundGradient)
}
