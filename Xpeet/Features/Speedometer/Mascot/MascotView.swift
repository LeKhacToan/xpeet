import SwiftUI

/// An original kawaii anime face in a "2.5D" style, drawn with shapes and gradients only (specs/visual-polish R7).
/// Decorative: VoiceOver ignores it, the number carries the speed. Colours come from `Theme.mascot`.
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

    private var palette: Theme.MascotPalette { theme.mascot }
    private var ink: Color { Color(hex: palette.ink) }
    private var canBlink: Bool { blinks && !reduceMotion && mood != .sleepy && scenePhase == .active }

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let unit = size / 100
            ZStack {
                shadow(unit: unit)
                head(unit: unit)
                face(unit: unit)
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

    // MARK: - Head

    private func shadow(unit: CGFloat) -> some View {
        Ellipse()
            .fill(.black.opacity(0.28))
            .frame(width: 66 * unit, height: 12 * unit)
            .blur(radius: 3 * unit)
            .offset(y: 46 * unit)
    }

    private func head(unit: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Color(hex: palette.highlight), Color(hex: palette.face)],
                    center: UnitPoint(x: 0.38, y: 0.3), startRadius: 0, endRadius: 62 * unit
                ))
            Bangs()
                .fill(LinearGradient(
                    colors: [Color(hex: palette.hair).opacity(0.95), Color(hex: palette.hair).opacity(0.75)],
                    startPoint: .top, endPoint: .bottom
                ))
            // Hair highlight streak.
            Bangs()
                .stroke(.white.opacity(0.35), lineWidth: 3 * unit)
                .mask { Rectangle().frame(width: 40 * unit, height: 30 * unit).offset(x: -14 * unit, y: -36 * unit) }
            // Cheek blush.
            HStack(spacing: 42 * unit) {
                blush(unit: unit)
                blush(unit: unit)
            }
            .offset(y: 18 * unit)
        }
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(ink.opacity(0.55), lineWidth: 2.2 * unit) }
        .frame(width: 92 * unit, height: 92 * unit)
    }

    private func blush(unit: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(
                colors: [theme.color(palette.blush), theme.color(palette.blush).opacity(0)],
                center: .center, startRadius: 0, endRadius: 9 * unit
            ))
            .frame(width: 18 * unit, height: 18 * unit)
    }

    // MARK: - Face

    @ViewBuilder
    private func face(unit: CGFloat) -> some View {
        ZStack {
            eyebrows(unit: unit)
            eyes(unit: unit)
            mouth(unit: unit)
            accessories(unit: unit)
        }
    }

    private func eyebrows(unit: CGFloat) -> some View {
        let spacing = 22 * unit
        let y = -12 * unit
        return HStack(spacing: spacing) {
            brow(unit: unit, angle: browAngle(left: true), lift: browLift(left: true))
            brow(unit: unit, angle: browAngle(left: false), lift: browLift(left: false))
        }
        .offset(y: y)
    }

    private func brow(unit: CGFloat, angle: Double, lift: CGFloat) -> some View {
        Capsule()
            .fill(ink)
            .frame(width: 14 * unit, height: 3 * unit)
            .rotationEffect(.degrees(angle))
            .offset(y: -lift * unit)
    }

    /// Positive angles tilt clockwise. Worried: inner ends up. Searching: one brow raised.
    private func browAngle(left: Bool) -> Double {
        switch mood {
        case .worried: left ? -18 : 18
        case .happy, .startled: left ? 8 : -8
        case .searching: left ? 0 : -6
        case .calm, .sleepy: left ? 4 : -4
        }
    }

    private func browLift(left: Bool) -> CGFloat {
        switch mood {
        case .startled: 6
        case .happy: 3
        case .searching: left ? 0 : 4
        case .worried, .calm, .sleepy: 0
        }
    }

    @ViewBuilder
    private func eyes(unit: CGFloat) -> some View {
        let spacing = 18 * unit
        let y = 4 * unit
        if mood == .sleepy || eyesClosed {
            HStack(spacing: spacing + 6 * unit) {
                ClosedEye().stroke(ink, style: StrokeStyle(lineWidth: 3 * unit, lineCap: .round)).frame(width: 14 * unit, height: 5 * unit)
                ClosedEye().stroke(ink, style: StrokeStyle(lineWidth: 3 * unit, lineCap: .round)).frame(width: 14 * unit, height: 5 * unit)
            }
            .offset(y: y + 2 * unit)
        } else {
            HStack(spacing: spacing) {
                eye(unit: unit)
                eye(unit: unit)
            }
            .offset(y: y)
        }
    }

    /// A big anime eye: white, iris gradient, pupil, lash line and two highlights.
    private func eye(unit: CGFloat) -> some View {
        let width = eyeSize.width * unit
        let height = eyeSize.height * unit
        let irisDiameter = irisSize * unit
        let pupilDiameter = pupilSize * unit
        let gaze = mood == .searching ? 3 * unit : 0
        return ZStack {
            Ellipse()
                .fill(Color(hex: palette.eyeWhite))
            Circle()
                .fill(RadialGradient(
                    colors: [Color(hex: palette.iris).opacity(0.75), Color(hex: palette.iris), ink.opacity(0.9)],
                    center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: irisDiameter * 0.55
                ))
                .frame(width: irisDiameter, height: irisDiameter)
                .offset(x: gaze, y: 1.5 * unit)
            Circle()
                .fill(ink)
                .frame(width: pupilDiameter, height: pupilDiameter)
                .offset(x: gaze, y: 1.5 * unit)
            Circle()
                .fill(.white)
                .frame(width: 5.5 * unit, height: 5.5 * unit)
                .offset(x: gaze - 3.5 * unit, y: -4 * unit)
            Circle()
                .fill(.white.opacity(0.9))
                .frame(width: 2.5 * unit, height: 2.5 * unit)
                .offset(x: gaze + 3 * unit, y: 4 * unit)
            // Upper lash line.
            Lash()
                .stroke(ink, style: StrokeStyle(lineWidth: 2.6 * unit, lineCap: .round))
        }
        .frame(width: width, height: height)
    }

    private var eyeSize: (width: CGFloat, height: CGFloat) {
        switch mood {
        case .startled: (22, 24)
        case .worried: (20, 23)
        case .happy: (19, 20)
        case .calm, .searching, .sleepy: (18, 21)
        }
    }

    private var irisSize: CGFloat {
        switch mood {
        case .startled: 11
        case .worried: 12
        case .calm, .searching, .sleepy, .happy: 14
        }
    }

    private var pupilSize: CGFloat {
        switch mood {
        case .startled: 4
        case .worried: 5.5
        case .calm, .searching, .sleepy, .happy: 7
        }
    }

    @ViewBuilder
    private func mouth(unit: CGFloat) -> some View {
        let y = 26 * unit
        let stroke = StrokeStyle(lineWidth: 3.2 * unit, lineCap: .round)
        switch mood {
        case .searching, .sleepy:
            Capsule().fill(ink).frame(width: 9 * unit, height: 3 * unit).offset(y: y)
        case .calm:
            Smile(curve: 0.35).stroke(ink, style: stroke).frame(width: 16 * unit, height: 7 * unit).offset(y: y)
        case .happy:
            // Open smile: a filled half-moon with a lighter lower lip.
            ZStack {
                OpenSmile().fill(ink).frame(width: 26 * unit, height: 13 * unit)
                OpenSmile().fill(theme.color(palette.blush).opacity(1)).frame(width: 14 * unit, height: 6 * unit).offset(y: 5 * unit)
            }
            .offset(y: y - 2 * unit)
        case .worried:
            Wave().stroke(ink, style: stroke).frame(width: 22 * unit, height: 7 * unit).offset(y: y)
        case .startled:
            Circle().fill(ink).frame(width: 12 * unit, height: 12 * unit).offset(y: y + 2 * unit)
        }
    }

    @ViewBuilder
    private func accessories(unit: CGFloat) -> some View {
        switch mood {
        case .sleepy:
            Text(verbatim: "z")
                .font(theme.font(role: .number, size: 22 * unit))
                .foregroundStyle(ink)
                .offset(x: 36 * unit, y: -36 * unit)
        case .worried:
            Drop()
                .fill(LinearGradient(colors: [.white.opacity(0.9), Color(hex: palette.iris)], startPoint: .top, endPoint: .bottom))
                .overlay { Drop().stroke(ink.opacity(0.6), lineWidth: 1.2 * unit) }
                .frame(width: 9 * unit, height: 14 * unit)
                .offset(x: 38 * unit, y: -24 * unit)
        case .startled:
            Text(verbatim: "!")
                .font(theme.font(role: .number, size: 28 * unit))
                .foregroundStyle(ink)
                .offset(x: 42 * unit, y: -36 * unit)
        case .searching, .calm, .happy:
            EmptyView()
        }
    }
}

// MARK: - Shapes

/// Hair bangs: covers the top third of the head, scalloped along the bottom, longer at the sides.
private struct Bangs: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + w * x, y: rect.minY + h * y) }
        var path = Path()
        path.move(to: point(0, 0.55))
        path.addQuadCurve(to: point(0.5, -0.04), control: point(0, 0))
        path.addQuadCurve(to: point(1, 0.55), control: point(1, 0))
        // Scallops, right to left; the lowest point between them is about a third of the way down.
        path.addQuadCurve(to: point(0.8, 0.28), control: point(0.92, 0.42))
        path.addQuadCurve(to: point(0.55, 0.24), control: point(0.68, 0.38))
        path.addQuadCurve(to: point(0.3, 0.28), control: point(0.42, 0.38))
        path.addQuadCurve(to: point(0, 0.55), control: point(0.1, 0.42))
        path.closeSubpath()
        return path
    }
}

/// Upper lash: an arc over the top of the eye.
private struct Lash: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.42))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.minY + rect.height * 0.42),
            control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.2)
        )
        return path
    }
}

/// Filled open smile: flat top, round bottom.
private struct OpenSmile: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY + rect.height))
        path.closeSubpath()
        return path
    }
}

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
                HStack(spacing: 10) {
                    ForEach(Mood.allCases, id: \.self) { mood in
                        MascotView(mood: mood, theme: face.theme, blinks: false)
                            .frame(width: 58, height: 58)
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
        MascotView(mood: .happy, theme: .minimalRing)
        MascotView(mood: .worried, theme: .retro)
    }
    .frame(height: 160)
    .padding(40)
    .background(Theme.minimalRing.backgroundGradient)
}
