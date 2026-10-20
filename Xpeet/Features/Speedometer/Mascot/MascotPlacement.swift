import Foundation

/// Where the mascot goes next to the gauge (specs/speed-mascot R12). Pure geometry, unit-tested.
/// The gauge is a `min(width, height)` square centred in the container; the mascot takes the leftover space.
enum MascotPlacement {
    /// Mascot size as a share of the gauge diameter, clamped to `sizeRange`.
    static let sizeFraction = 0.18
    static let sizeRange: ClosedRange<CGFloat> = 44...84
    /// Gap between the mascot and the gauge.
    static let gap: CGFloat = 8

    static func size(gaugeDiameter: CGFloat) -> CGFloat {
        min(max(gaugeDiameter * sizeFraction, sizeRange.lowerBound), sizeRange.upperBound)
    }

    /// The mascot's frame in the container, or nil when there is no room (the gauge never shrinks for it).
    /// Portrait: centred above the gauge. Landscape: on the leading side, vertically centred.
    static func frame(in container: CGSize) -> CGRect? {
        let diameter = min(container.width, container.height)
        let size = size(gaugeDiameter: diameter)
        if container.height >= container.width {
            let spaceAbove = (container.height - diameter) / 2
            guard spaceAbove >= size + gap else { return nil }
            return CGRect(x: (container.width - size) / 2, y: spaceAbove - gap - size, width: size, height: size)
        } else {
            let spaceLeading = (container.width - diameter) / 2
            guard spaceLeading >= size + gap else { return nil }
            return CGRect(x: spaceLeading - gap - size, y: (container.height - size) / 2, width: size, height: size)
        }
    }
}
