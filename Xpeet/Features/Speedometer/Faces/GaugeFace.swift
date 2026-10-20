import SwiftUI

/// The selectable gauge faces. Each one owns a fixed theme.
enum GaugeFace: String, CaseIterable, Identifiable {
    case minimalRing
    case analogSport
    case digitalHUD
    case retro

    static let defaultFace = GaugeFace.minimalRing

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .minimalRing: String(localized: "Minimal ring")
        case .analogSport: String(localized: "Analog sport")
        case .digitalHUD: String(localized: "Digital HUD")
        case .retro: String(localized: "Retro")
        }
    }

    var theme: Theme {
        switch self {
        case .minimalRing: .minimalRing
        case .analogSport: .analogSport
        case .digitalHUD: .digitalHUD
        case .retro: .retro
        }
    }
}

extension Theme {
    /// The original look: pastel green `#9FE3B5` (the `AccentColor` asset) on a green-tinted near-black.
    static let minimalRing = Theme(
        backgroundCenter: 0x16231B,
        backgroundEdge: 0x0A0F0C,
        number: 0xFFFFFF,
        placeholder: 0xB3B3B3,
        accent: 0x9FE3B5,
        accentDeep: 0x6CCB97,
        track: Overlay(hex: 0xFFFFFF, opacity: 0.1),
        chipFill: Overlay(hex: 0xFFFFFF, opacity: 0.08),
        chipText: 0xBFBFBF,
        buttonLabel: 0x0A0F0C,
        scaleLabel: 0xFFFFFF,
        typeface: Typeface(number: "Nunito-Black", secondary: "Nunito-SemiBold"),
        colorScheme: .dark
    )

    static let analogSport = Theme(
        backgroundCenter: 0x15181C,
        backgroundEdge: 0x08090B,
        number: 0xFFFFFF,
        placeholder: 0xB3B3B3,
        accent: 0x7FD8FF,
        accentDeep: 0x4FB3E8,
        track: Overlay(hex: 0xFFFFFF, opacity: 0.25),
        chipFill: Overlay(hex: 0xFFFFFF, opacity: 0.08),
        chipText: 0xBFBFBF,
        buttonLabel: 0x08090B,
        scaleLabel: 0xD9DDE3,
        typeface: Typeface(number: "BarlowCondensed-Black", secondary: "BarlowCondensed-SemiBold"),
        colorScheme: .dark
    )

    static let digitalHUD = Theme(
        backgroundCenter: 0x04100E,
        backgroundEdge: 0x020605,
        number: 0xE6FBFF,
        placeholder: 0xA9BFC4,
        accent: 0x4DD9FF,
        accentDeep: 0x2BB5E0,
        track: Overlay(hex: 0x4DD9FF, opacity: 0.15),
        chipFill: Overlay(hex: 0x4DD9FF, opacity: 0.1),
        chipText: 0xBFEFFA,
        buttonLabel: 0x020605,
        scaleLabel: 0xBFEFFA,
        typeface: Typeface(number: "OxaniumRoman-ExtraBold", secondary: "OxaniumRoman-SemiBold"),
        colorScheme: .dark
    )

    /// The only light face: cream dial, dark ink, red-brown needle.
    static let retro = Theme(
        backgroundCenter: 0xF3EAD3,
        backgroundEdge: 0xE6D9BC,
        number: 0x2B2118,
        placeholder: 0x4A3E33,
        accent: 0x7A281B,
        accentDeep: 0x5E1E14,
        track: Overlay(hex: 0x2B2118, opacity: 0.3),
        chipFill: Overlay(hex: 0x2B2118, opacity: 0.08),
        chipText: 0x3D3128,
        buttonLabel: 0xFFF8E7,
        scaleLabel: 0x3D3128,
        typeface: Typeface(number: "BodoniModa-Regular_Black", secondary: "BodoniModa-Regular_SemiBold"),
        colorScheme: .light
    )
}
