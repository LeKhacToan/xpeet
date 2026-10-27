import Foundation

/// Where the trip line goes in landscape: the free space trailing the gauge, mirroring the mascot on the leading
/// side (specs/trip-stats R12, `MascotPlacement`). Pure geometry, unit-tested. In portrait the line sits under the
/// gauge in the layout instead, so this returns nil.
enum TripLinePlacement {
    /// Gap kept to the gauge and to the screen edge.
    static let gap: CGFloat = 8
    /// Narrower than this, even the two-line layout doesn't fit: the line hides; the gauge never shrinks for it.
    static let minimumWidth: CGFloat = 96

    /// The space the line may use, full height so it centres vertically on the gauge. Nil in portrait or with no room.
    static func frame(in container: CGSize) -> CGRect? {
        guard container.width > container.height else { return nil }
        let spaceTrailing = (container.width - container.height) / 2
        let width = spaceTrailing - 2 * gap
        guard width >= minimumWidth else { return nil }
        return CGRect(x: container.width - spaceTrailing + gap, y: 0, width: width, height: container.height)
    }
}
