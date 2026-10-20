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
                    .strokeBorder(AngularGradient(colors: lights, center: .center, angle: .degrees(-45)), lineWidth: diameter * 0.018)
                Circle()
                    .inset(by: diameter * 0.018)
                    .strokeBorder(Color.black.opacity(isDark ? 0.5 : 0.22), lineWidth: diameter * 0.004)
            }
            .frame(width: diameter, height: diameter)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
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
    }
    .padding()
    .background(.black)
}
