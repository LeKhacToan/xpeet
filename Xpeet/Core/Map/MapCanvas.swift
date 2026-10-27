import MapKit
import SwiftUI

/// `MKMapView` showing OpenStreetMap tiles (specs/osm-map R5-R8, R10, R15, R18, R23). It only applies a
/// `MapScene` decided by the ViewModel: camera, marker, trail and dimming. Used live (following, heading-up) and
/// for a past trip's route (fitted, north-up).
struct MapCanvas: UIViewRepresentable {
    enum Style: Equatable {
        /// The live map: rotation on, so the camera heading is applied (R6, R8).
        case live
        /// A past trip: north-up, fitted to the route, with start and end dots (R23).
        case route
    }

    let scene: MapScene
    let style: Style
    let tileFetcher: TileFetcher
    let trailColor: UIColor
    var reduceMotion = false
    /// A drag, pinch, rotation or tap-zoom by hand (R8).
    var onUserGesture: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = LayoutReportingMapView()
        map.delegate = context.coordinator
        // The first scene arrives before the map has a size: camera and fitting wait for layout.
        map.onSizeChange = { [weak coordinator = context.coordinator, weak map] in
            if let map { coordinator?.sizeChanged(map) }
        }
        map.pointOfInterestFilter = .excludingAll
        map.showsBuildings = false
        map.showsTraffic = false
        map.showsCompass = false
        map.showsScale = false
        map.isPitchEnabled = false
        // MapKit ignores a camera heading while rotation is off, so the live map keeps it on (R8, amended).
        map.isRotateEnabled = style == .live
        map.cameraZoomRange = MKMapView.CameraZoomRange(minCenterCoordinateDistance: 120)
        context.coordinator.attach(to: map, style: style, fetcher: tileFetcher)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.onUserGesture = onUserGesture
        context.coordinator.apply(scene, trailColor: trailColor, reduceMotion: reduceMotion, to: map)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        /// Trail segments are split into polylines of at most this many points, so a fix replaces only the last one.
        static let chunkSize = 200

        var onUserGesture: () -> Void = {}
        private var tiles: OSMTileOverlay?
        private var dim: DimOverlay?
        private var chunks: [[MapCoordinate]] = []
        private var polylines: [MKPolyline] = []
        private let marker = MarkerAnnotation()
        private var routeEnds: [RouteEndAnnotation] = []
        private var applied: MapScene?
        private var trailColor = UIColor.cyan
        private var style = Style.live
        private var distancePerVisibleHeight = CameraMath.defaultDistancePerVisibleHeight
        private var calibratedSize: CGSize = .zero
        private var hasFittedRoute = false

        func attach(to map: MKMapView, style: Style, fetcher: TileFetcher) {
            self.style = style
            let tiles = OSMTileOverlay(fetcher: fetcher)
            map.addOverlay(tiles, level: .aboveLabels)
            self.tiles = tiles
            let recognizers: [UIGestureRecognizer] = [
                UIPanGestureRecognizer(target: self, action: #selector(gestureBegan(_:))),
                UIPinchGestureRecognizer(target: self, action: #selector(gestureBegan(_:))),
                UIRotationGestureRecognizer(target: self, action: #selector(gestureBegan(_:))),
                Self.tap(touches: 1, taps: 2, target: self),
                Self.tap(touches: 2, taps: 1, target: self),
            ]
            for recognizer in recognizers {
                recognizer.delegate = self
                recognizer.cancelsTouchesInView = false
                recognizer.delaysTouchesEnded = false
                map.addGestureRecognizer(recognizer)
            }
        }

        func apply(_ scene: MapScene, trailColor: UIColor, reduceMotion: Bool, to map: MKMapView) {
            // The route view's sheet refreshes twice a second; skip when nothing changed.
            guard scene != applied || trailColor != self.trailColor else { return }
            let previous = applied
            applied = scene
            if trailColor != self.trailColor {
                self.trailColor = trailColor
                polylines.forEach { (map.renderer(for: $0) as? MKPolylineRenderer)?.strokeColor = trailColor }
            }
            applyDimming(scene.dimsTiles, to: map)
            applyTrail(scene.trail, to: map)
            applyMarker(scene.marker, previous: previous?.marker, reduceMotion: reduceMotion, to: map)
            if style == .route { fitRoute(scene.trail, to: map) }
            if let camera = scene.camera, camera != previous?.camera {
                applyCamera(camera, animated: !reduceMotion && previous?.camera != nil, to: map)
            }
        }

        /// A new size: measure the camera again and re-apply what waited for layout.
        func sizeChanged(_ map: MKMapView) {
            if let camera = applied?.camera { applyCamera(camera, animated: false, to: map) }
            if style == .route, let trail = applied?.trail { fitRoute(trail, to: map) }
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            switch overlay {
            case let tiles as MKTileOverlay:
                return MKTileOverlayRenderer(tileOverlay: tiles)
            case let dim as DimOverlay:
                let renderer = MKPolygonRenderer(polygon: dim)
                renderer.fillColor = UIColor.black.withAlphaComponent(MapStyle.dimOpacity)
                return renderer
            case let line as MKPolyline:
                let renderer = MKPolylineRenderer(polyline: line)
                renderer.strokeColor = trailColor
                renderer.lineWidth = MapStyle.trailWidth
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            default:
                return MKOverlayRenderer(overlay: overlay)
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            switch annotation {
            case let marker as MarkerAnnotation:
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: MarkerView.reuseID) as? MarkerView
                    ?? MarkerView(annotation: marker, reuseIdentifier: MarkerView.reuseID)
                view.annotation = marker
                view.update(heading: marker.heading, mapHeading: mapView.camera.heading, isDimmed: marker.isDimmed, accent: trailColor)
                return view
            case let end as RouteEndAnnotation:
                let view = RouteEndView(annotation: end, reuseIdentifier: nil)
                view.configure(isStart: end.isStart, accent: trailColor)
                return view
            default:
                return nil
            }
        }

        /// Keeps the arrow pointing along the course while the map turns.
        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            (mapView.view(for: marker) as? MarkerView)?.update(
                heading: marker.heading, mapHeading: mapView.camera.heading, isDimmed: marker.isDimmed, accent: trailColor
            )
        }

        // MARK: UIGestureRecognizerDelegate

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        @objc private func gestureBegan(_ recognizer: UIGestureRecognizer) {
            if recognizer.state == .began || recognizer is UITapGestureRecognizer && recognizer.state == .ended {
                onUserGesture()
            }
        }

        private static func tap(touches: Int, taps: Int, target: Coordinator) -> UITapGestureRecognizer {
            let tap = UITapGestureRecognizer(target: target, action: #selector(gestureBegan(_:)))
            tap.numberOfTouchesRequired = touches
            tap.numberOfTapsRequired = taps
            return tap
        }

        // MARK: Applying

        private func applyDimming(_ dims: Bool, to map: MKMapView) {
            if dims, dim == nil, let tiles {
                let dim = DimOverlay.world()
                map.insertOverlay(dim, above: tiles)
                self.dim = dim
            } else if !dims, let dim {
                map.removeOverlay(dim)
                self.dim = nil
            }
        }

        /// Replaces only the chunks that changed: normally just the last one (R18).
        private func applyTrail(_ trail: [[MapCoordinate]], to map: MKMapView) {
            let next = trail.flatMap(Self.chunked)
            var index = 0
            while index < max(next.count, chunks.count) {
                let old = index < chunks.count ? chunks[index] : nil
                let new = index < next.count ? next[index] : nil
                if old != new {
                    if index < polylines.count {
                        map.removeOverlay(polylines[index])
                    }
                    if let new {
                        let line = MKPolyline(coordinates: new.map(\.location), count: new.count)
                        map.addOverlay(line, level: .aboveLabels)
                        if index < polylines.count { polylines[index] = line } else { polylines.append(line) }
                    }
                }
                index += 1
            }
            if polylines.count > next.count { polylines.removeLast(polylines.count - next.count) }
            chunks = next
        }

        /// Consecutive chunks share their joining point, so the line has no gaps inside a segment.
        private static func chunked(_ segment: [MapCoordinate]) -> [[MapCoordinate]] {
            guard segment.count > chunkSize else { return [segment] }
            return stride(from: 0, to: segment.count - 1, by: chunkSize - 1).map {
                Array(segment[$0..<min($0 + chunkSize, segment.count)])
            }
        }

        private func applyMarker(_ scene: MapScene.Marker?, previous: MapScene.Marker?, reduceMotion: Bool, to map: MKMapView) {
            guard let scene else {
                if map.annotations.contains(where: { $0 === marker }) { map.removeAnnotation(marker) }
                return
            }
            marker.heading = scene.heading
            marker.isDimmed = scene.isDimmed
            if previous == nil || !map.annotations.contains(where: { $0 === marker }) {
                marker.coordinate = scene.coordinate.location
                map.addAnnotation(marker)
            } else if scene.coordinate != previous?.coordinate {
                // One second between fixes: glide over it, or jump with Reduce Motion (R5).
                UIView.animate(withDuration: reduceMotion ? 0 : 1, delay: 0, options: [.curveLinear, .beginFromCurrentState]) {
                    self.marker.coordinate = scene.coordinate.location
                }
            }
            (map.view(for: marker) as? MarkerView)?.update(
                heading: scene.heading, mapHeading: map.camera.heading, isDimmed: scene.isDimmed, accent: trailColor
            )
        }

        private func applyCamera(_ camera: MapScene.Camera, animated: Bool, to map: MKMapView) {
            guard map.bounds.height > 0 else { return }
            if map.bounds.size != calibratedSize {
                // Measure at street level: set once with the current ratio, measure, then set the corrected camera.
                map.setCamera(makeCamera(camera, for: map), animated: false)
                calibrate(map)
                map.setCamera(makeCamera(camera, for: map), animated: false)
                return
            }
            let next = makeCamera(camera, for: map)
            guard animated else {
                map.setCamera(next, animated: false)
                return
            }
            // One second between fixes: the camera glides with the marker (R5, R7).
            UIView.animate(withDuration: 1, delay: 0, options: [.curveLinear, .beginFromCurrentState, .allowUserInteraction]) {
                map.camera = next
            }
        }

        private func makeCamera(_ camera: MapScene.Camera, for map: MKMapView) -> MKMapCamera {
            let distance = CameraMath.distance(
                zoom: camera.zoom, latitude: camera.center.latitude,
                viewHeight: map.bounds.height, distancePerVisibleHeight: distancePerVisibleHeight
            )
            return MKMapCamera(lookingAtCenter: camera.center.location, fromDistance: distance, pitch: 0, heading: camera.heading)
        }

        /// Camera distance over visible ground height, measured on the live map for this view size.
        private func calibrate(_ map: MKMapView) {
            let size = map.bounds.size
            let top = map.convert(CGPoint(x: size.width / 2, y: 0), toCoordinateFrom: map)
            let bottom = map.convert(CGPoint(x: size.width / 2, y: size.height), toCoordinateFrom: map)
            let visibleHeight = MKMapPoint(top).distance(to: MKMapPoint(bottom))
            guard visibleHeight > 0, map.camera.centerCoordinateDistance > 0 else { return }
            distancePerVisibleHeight = map.camera.centerCoordinateDistance / visibleHeight
            calibratedSize = size
        }

        private func fitRoute(_ trail: [[MapCoordinate]], to map: MKMapView) {
            guard !hasFittedRoute, !polylines.isEmpty, map.bounds.height > 0 else { return }
            let rect = polylines.dropFirst().reduce(polylines[0].boundingMapRect) { $0.union($1.boundingMapRect) }
            map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 40, left: 32, bottom: 40, right: 32), animated: false)
            if let first = trail.first?.first, let last = trail.last?.last {
                routeEnds = [RouteEndAnnotation(coordinate: first.location, isStart: true),
                             RouteEndAnnotation(coordinate: last.location, isStart: false)]
                map.addAnnotations(routeEnds)
            }
            hasFittedRoute = true
        }
    }
}

/// Tells the coordinator when the map gets a new size.
private final class LayoutReportingMapView: MKMapView {
    var onSizeChange: (() -> Void)?
    private var reportedSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != reportedSize, bounds.height > 0 else { return }
        reportedSize = bounds.size
        onSizeChange?()
    }
}

// MARK: - Annotations

private extension MapCoordinate {
    var location: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

private final class MarkerAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate = CLLocationCoordinate2D()
    var heading: Double?
    var isDimmed = false
}

private final class RouteEndAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let isStart: Bool

    init(coordinate: CLLocationCoordinate2D, isStart: Bool) {
        self.coordinate = coordinate
        self.isStart = isStart
    }
}

/// The car: an arrow along the course in a white-rimmed disc, or a dot before any course (R5).
private final class MarkerView: MKAnnotationView {
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
        arrow.image = UIImage(systemName: "location.north.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold))
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
private final class RouteEndView: MKAnnotationView {
    func configure(isStart: Bool, accent: UIColor) {
        frame = CGRect(x: 0, y: 0, width: 16, height: 16)
        layer.cornerRadius = 8
        layer.borderWidth = isStart ? 3 : 2
        layer.borderColor = (isStart ? accent : .white).cgColor
        backgroundColor = isStart ? UIColor(red: 0.05, green: 0.07, blue: 0.11, alpha: 1) : accent
        isAccessibilityElement = false
    }
}
