import Foundation

/// Where the mascot goes next to the gauge (specs/speed-mascot R12, sized by specs/ui-redesign R5). Pure geometry, unit-tested.
/// The gauge is a `min(width, height)` square centred in the container; the mascot takes the leftover space.
enum MascotPlacement {
    /// Mascot size as a share of the gauge diameter, clamped to `sizeRange`.
    static let sizeFraction = 0.22
    static let sizeRange: ClosedRange<CGFloat> = 44...96
    /// Gap between the mascot and the gauge.
    static let gap: CGFloat = 8

    static func size(gaugeDiameter: CGFloat) -> CGFloat {
        min(max(gaugeDiameter * sizeFraction, sizeRange.lowerBound), sizeRange.upperBound)
    }

    /// The mascot's frame in the container, or nil when there is no room (the gauge never shrinks for it).
    /// Portrait: centred above the gauge. Landscape: on the leading side, vertically centred.
    /// A badge that doesn't fit shrinks to the free space, down to the 44 pt floor, before it hides (specs/ui-redesign R5).
    static func frame(in container: CGSize) -> CGRect? {
        let diameter = min(container.width, container.height)
        if container.height >= container.width {
            let spaceAbove = (container.height - diameter) / 2
            guard let size = fitted(size(gaugeDiameter: diameter), in: spaceAbove) else { return nil }
            return CGRect(x: (container.width - size) / 2, y: spaceAbove - gap - size, width: size, height: size)
        } else {
            let spaceLeading = (container.width - diameter) / 2
            guard let size = fitted(size(gaugeDiameter: diameter), in: spaceLeading) else { return nil }
            return CGRect(x: spaceLeading - gap - size, y: (container.height - size) / 2, width: size, height: size)
        }
    }

    private static func fitted(_ size: CGFloat, in space: CGFloat) -> CGFloat? {
        let fitted = min(size, space - gap)
        return fitted >= sizeRange.lowerBound ? fitted : nil
    }
}
