import SwiftUI

/// A face's fixed palette and type style. Colours are hex so contrast can be unit-tested.
/// No colour here ever depends on speed.
struct Theme: Equatable {
    /// A colour drawn with transparency over the background.
    struct Overlay: Equatable {
        var hex: UInt32
        var opacity: Double
    }

    enum Design: Equatable {
        case rounded, monospaced, serif

        var font: Font.Design {
            switch self {
            case .rounded: .rounded
            case .monospaced: .monospaced
            case .serif: .serif
            }
        }
    }

    var backgroundCenter: UInt32
    var backgroundEdge: UInt32
    var number: UInt32
    var placeholder: UInt32
    /// Arc or needle, unit pill text, status icons, "Open Settings" fill.
    var accent: UInt32
    /// Start of the arc gradient; the arc ends in `accent`.
    var accentDeep: UInt32
    /// Unfilled track, dim segments, minor ticks.
    var track: Overlay
    var chipFill: Overlay
    var chipText: UInt32
    /// Label on the accent-filled "Open Settings" button.
    var buttonLabel: UInt32
    /// Dial scale labels and major ticks.
    var scaleLabel: UInt32
    var design: Design
    var colorScheme: ColorScheme

    static let pillTintOpacity = 0.16
    static let glowOpacity = 0.45

    var backgroundGradient: EllipticalGradient {
        EllipticalGradient(
            colors: [Color(hex: backgroundCenter), Color(hex: backgroundEdge)],
            center: .center,
            startRadiusFraction: 0,
            endRadiusFraction: 0.75
        )
    }

    var arcGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: accentDeep), Color(hex: accent)],
            startPoint: .bottomLeading,
            endPoint: .topTrailing
        )
    }

    func color(_ overlay: Overlay) -> Color {
        Color(hex: overlay.hex).opacity(overlay.opacity)
    }
}

// MARK: - WCAG contrast

extension Theme {
    /// WCAG 2.x contrast ratio between two opaque colours, 1...21.
    static func contrastRatio(_ first: UInt32, _ second: UInt32) -> Double {
        let (lighter, darker) = (max(luminance(first), luminance(second)), min(luminance(first), luminance(second)))
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// The opaque colour of `foreground` drawn at `opacity` over `background`.
    static func blend(_ foreground: UInt32, over background: UInt32, opacity: Double) -> UInt32 {
        let channels = [16, 8, 0].map { shift -> UInt32 in
            let front = Double((foreground >> UInt32(shift)) & 0xFF)
            let back = Double((background >> UInt32(shift)) & 0xFF)
            return UInt32((front * opacity + back * (1 - opacity)).rounded()) << UInt32(shift)
        }
        return channels.reduce(0, |)
    }

    private static func luminance(_ hex: UInt32) -> Double {
        let linear = [16, 8, 0].map { shift -> Double in
            let channel = Double((hex >> UInt32(shift)) & 0xFF) / 255
            return channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
