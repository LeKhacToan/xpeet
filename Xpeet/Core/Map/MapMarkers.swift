import MapKit

// The live marker and a route's end dots, drawn by `MapCanvas` (specs/osm-map R5, R23).

extension MapCoordinate {
    var location: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

final class MarkerAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate = CLLocationCoordinate2D()
    var heading: Double?
    var isDimmed = false
}

final class RouteEndAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let isStart: Bool

    init(coordinate: CLLocationCoordinate2D, isStart: Bool) {
        self.coordinate = coordinate
        self.isStart = isStart
    }
}

/// The car: an arrow along the course in a white-rimmed disc, or a dot before any course (R5).
final class MarkerView: MKAnnotationView {
    static let reuseID = "marker"
    private let disc = UIView()
    private let arrow = UIImageView()
    private let dot = UIView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        disc.frame = bounds
        disc.layer.cornerRadius = 15
        disc.layer.borderWidth = 2
        disc.layer.borderColor = UIColor.white.cgColor
        disc.backgroundColor = UIColor(red: 0.05, green: 0.07, blue: 0.11, alpha: 1)
        addSubview(disc)
        let symbol = UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        arrow.image = UIImage(systemName: "location.north.fill", withConfiguration: symbol)
        arrow.contentMode = .center
        arrow.frame = bounds
        addSubview(arrow)
        dot.frame = CGRect(x: 9, y: 9, width: 12, height: 12)
        dot.layer.cornerRadius = 6
        addSubview(dot)
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { nil }

    func update(heading: Double?, mapHeading: Double, isDimmed: Bool, accent: UIColor) {
        arrow.tintColor = accent
        dot.backgroundColor = accent
        arrow.isHidden = heading == nil
        dot.isHidden = heading != nil
        let degrees = (heading ?? 0) - mapHeading
        arrow.transform = CGAffineTransform(rotationAngle: degrees * .pi / 180)
        alpha = isDimmed ? MapStyle.dimmedMarkerOpacity : 1
    }
}

/// A route's start (hollow ring) or end (filled dot with a white rim) (R23).
final class RouteEndView: MKAnnotationView {
    func configure(isStart: Bool, accent: UIColor) {
        frame = CGRect(x: 0, y: 0, width: 16, height: 16)
        layer.cornerRadius = 8
        layer.borderWidth = isStart ? 3 : 2
        layer.borderColor = (isStart ? accent : .white).cgColor
        backgroundColor = isStart ? UIColor(red: 0.05, green: 0.07, blue: 0.11, alpha: 1) : accent
        isAccessibilityElement = false
    }
}
