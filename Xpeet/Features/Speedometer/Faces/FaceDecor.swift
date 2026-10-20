import SwiftUI

// Static decoration layers (specs/visual-polish R5). Each depends only on the theme and its size,
// so SwiftUI draws it once per size change, never per sample.

/// Darkens the edge of a dial.
struct Vignette: View {
    let theme: Theme

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            Circle()
                .fill(RadialGradient(
                    colors: [.clear, .clear, .black.opacity(theme.colorScheme == .dark ? 0.45 : 0.12)],
                    center: .center, startRadius: 0, endRadius: diameter / 2
                ))
                .frame(width: diameter, height: diameter)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
    }
}

/// Rim with a light-to-dark sweep: chrome on light faces, a dark bevel on dark faces.
struct ChromeRim: View {
    let theme: Theme

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            let isDark = theme.colorScheme == .dark
            let lights: [Color] = isDark
                ? [.white.opacity(0.35), .white.opacity(0.06), .white.opacity(0.28), .white.opacity(0.03), .white.opacity(0.35)]
                : [.white, Color(white: 0.62), .white.opacity(0.95), Color(white: 0.55), .white]
            ZStack {
                Circle()
                    .strokeBorder(AngularGradient(colors: lights, center: .center, angle: .degrees(-45)), lineWidth: width(diameter))
                // Polished highlight along the top of the light faces' thicker bezel (specs/ui-redesign R13).
                if !isDark {
                    Circle()
                        .inset(by: width(diameter) * 0.3)
                        .trim(from: 0.6, to: 0.9)
                        .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: diameter * 0.006, lineCap: .round))
                        .blur(radius: diameter * 0.003)
                }
                Circle()
                    .inset(by: width(diameter))
                    .strokeBorder(Color.black.opacity(isDark ? 0.5 : 0.22), lineWidth: diameter * 0.004)
            }
            .frame(width: diameter, height: diameter)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
    }

    private func width(_ diameter: CGFloat) -> CGFloat {
        diameter * Self.widthFraction(theme.colorScheme)
    }

    /// Rim width as a share of the diameter; light faces get the thicker polished bezel (specs/ui-redesign R13).
    /// `DialFace` keeps its scale inside this.
    static func widthFraction(_ colorScheme: ColorScheme) -> Double {
        colorScheme == .dark ? 0.018 : 0.04
    }
}

/// The Digital HUD's frame: a dashed circle, four corner brackets and four cardinal ticks (specs/ui-redesign R12).
struct HUDFrame: View, Equatable {
    let theme: Theme

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let color = Color(hex: theme.accent)
            let radius = side * 0.47

            let circle = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            context.stroke(circle, with: .color(color.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
            let inner = radius * 0.93
            context.stroke(
                Path(ellipseIn: CGRect(x: center.x - inner, y: center.y - inner, width: inner * 2, height: inner * 2)),
                with: .color(color.opacity(0.12)), lineWidth: 1
            )

            // Cardinal ticks just inside the dashed circle.
            var ticks = Path()
            let tickInner = radius - side * 0.035
            for angle in stride(from: 0.0, to: 360, by: 90) {
                let radians = angle * .pi / 180
                ticks.move(to: CGPoint(x: center.x + radius * sin(radians), y: center.y - radius * cos(radians)))
                ticks.addLine(to: CGPoint(x: center.x + tickInner * sin(radians), y: center.y - tickInner * cos(radians)))
            }
            context.stroke(ticks, with: .color(color.opacity(0.7)), style: StrokeStyle(lineWidth: 2, lineCap: .round))

            // Corner brackets on the bounding square.
            let half = side * 0.49
            let arm = side * 0.09
            var brackets = Path()
            for (dx, dy) in [(-1.0, -1.0), (1, -1), (1, 1), (-1, 1)] {
                let corner = CGPoint(x: center.x + dx * half, y: center.y + dy * half)
                brackets.move(to: CGPoint(x: corner.x - dx * arm, y: corner.y))
                brackets.addLine(to: corner)
                brackets.addLine(to: CGPoint(x: corner.x, y: corner.y - dy * arm))
            }
            context.stroke(brackets, with: .color(color.opacity(0.6)), style: StrokeStyle(lineWidth: 2, lineCap: .square))
        }
        .allowsHitTesting(false)
    }
}

/// Frosted glass shared by the chip, buttons, pill and picker cards (specs/ui-redesign R7, R8, R15, R18):
/// the system material, a tint, and a hairline that is brighter at the top.
struct GlassBackground<S: InsettableShape>: View {
    let shape: S
    let tint: Color
    let colorScheme: ColorScheme

    var body: some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay { shape.fill(tint) }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(colorScheme == .dark ? 0.22 : 0.8), .white.opacity(colorScheme == .dark ? 0.03 : 0.2)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
    }
}

/// Horizontal scanlines for the HUD face.
struct Scanlines: View, Equatable {
    let theme: Theme

    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 3
            var y: CGFloat = 0
            var path = Path()
            while y < size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }
            context.stroke(path, with: .color(Color(hex: theme.accent).opacity(0.07)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

/// Paper grain: deterministic pseudo-random dots at low opacity.
struct PaperGrain: View, Equatable {
    let theme: Theme

    var body: some View {
        Canvas { context, size in
            var seed: UInt32 = 0x9E37_79B9
            func next() -> CGFloat {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                return CGFloat(seed >> 8) / CGFloat(1 << 24)
            }
            let count = min(1_500, Int(size.width * size.height / 60))
            let ink = Color(hex: theme.number)
            for _ in 0..<count {
                let rect = CGRect(x: next() * size.width, y: next() * size.height, width: 1.2, height: 1.2)
                context.fill(Path(ellipseIn: rect), with: .color(ink.opacity(0.03 + next() * 0.05)))
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview("Decor") {
    VStack {
        ZStack {
            Circle().fill(Theme.analogSport.backgroundGradient)
            ChromeRim(theme: .analogSport)
            Vignette(theme: .analogSport)
        }
        .frame(width: 200, height: 200)
        ZStack {
            Circle().fill(Theme.retro.backgroundGradient)
            PaperGrain(theme: .retro).equatable().clipShape(Circle())
            ChromeRim(theme: .retro)
        }
        .frame(width: 200, height: 200)
        Scanlines(theme: .digitalHUD).equatable()
            .frame(width: 200, height: 80)
            .background(Theme.digitalHUD.backgroundGradient)
        HUDFrame(theme: .digitalHUD).equatable()
            .frame(width: 200, height: 200)
            .background(Theme.digitalHUD.backgroundGradient)
    }
    .padding()
    .background(.black)
}
