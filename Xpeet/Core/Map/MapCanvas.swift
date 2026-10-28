import MapKit
import SwiftUI

/// `MKMapView` showing OpenStreetMap tiles in the light style (specs/osm-map R5-R8, R10, R18, R23, R33, R34). It only
/// applies a `MapScene` decided by the ViewModel: camera, marker and trail. Used live (following, heading-up) and for
/// a past trip's route (fitted, north-up).
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
        // The tiles are light on every face (R33): MapKit's own background, logo and "Legal" link match them.
        map.overrideUserInterfaceStyle = .light
        // MapKit ignores a camera heading while rotation is off, so the live map keeps it on (R8, amended).
        map.isRotateEnabled = style == .live
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
        private var fetcher: TileFetcher?
        private var tiles: OSMTileOverlay?
        private var chunks: [[MapCoordinate]] = []
        private var polylines: [MKPolyline] = []
        /// The dark edge under each polyline, at the same index (R18).
        private var edges: [TrailEdge] = []
        private let marker = MarkerAnnotation()
        private var routeEnds: [RouteEndAnnotation] = []
        private var applied: MapScene?
        private var trailColor = UIColor.cyan
        private var style = Style.live
        private var distancePerVisibleHeight = CameraMath.defaultDistancePerVisibleHeight
        private var calibratedSize: CGSize = .zero
        private var hasFittedRoute = false
        /// Where the z3-z19 zoom range was last worked out: it changes with latitude and view size (R8).
        private var zoomRangeBasis: (latitude: Double, height: CGFloat)?
        private var lastGestureReport = Date.distantPast

        func attach(to map: MKMapView, style: Style, fetcher: TileFetcher) {
            self.style = style
            self.fetcher = fetcher
            // Above labels: at a lower level MapKit still draws Apple's road names over the tiles.
            let tiles = OSMTileOverlay()
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
            case let tiles as OSMTileOverlay:
                guard let fetcher else { return MKOverlayRenderer(overlay: tiles) }
                return TileRenderer(overlay: tiles, fetcher: fetcher)
            case let edge as TrailEdge:
                return Self.lineRenderer(edge, colour: UIColor(Color(hex: MapStyle.trailEdge)),
                                         width: MapStyle.trailWidth + 2 * MapStyle.trailEdgeWidth)
            case let line as MKPolyline:
                return Self.lineRenderer(line, colour: trailColor, width: MapStyle.trailWidth)
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

        /// Reports the start and end of a gesture, and about once a second while it lasts, so following resumes 10 s
        /// after the last touch rather than the first (R8).
        @objc private func gestureBegan(_ recognizer: UIGestureRecognizer) {
            switch recognizer.state {
            case .began, .ended, .cancelled:
                report()
            case .changed where Date().timeIntervalSince(lastGestureReport) >= 1:
                report()
            default:
                break
            }
        }

        private func report() {
            lastGestureReport = Date()
            onUserGesture()
        }

        private static func tap(touches: Int, taps: Int, target: Coordinator) -> UITapGestureRecognizer {
            let tap = UITapGestureRecognizer(target: target, action: #selector(gestureBegan(_:)))
            tap.numberOfTouchesRequired = touches
            tap.numberOfTapsRequired = taps
            return tap
        }

        // MARK: Applying

        /// Replaces only the chunks that changed: normally just the last one (R18).
        private func applyTrail(_ trail: [[MapCoordinate]], to map: MKMapView) {
            let next = trail.flatMap(Self.chunked)
            var index = 0
            while index < max(next.count, chunks.count) {
                let old = index < chunks.count ? chunks[index] : nil
                let new = index < next.count ? next[index] : nil
                if old != new {
                    if index < polylines.count {
                        map.removeOverlays([edges[index], polylines[index]])
                    }
                    if let new {
                        let coordinates = new.map(\.location)
                        let edge = TrailEdge(coordinates: coordinates, count: coordinates.count)
                        let line = MKPolyline(coordinates: coordinates, count: coordinates.count)
                        // Edges right above the tiles, lines on top: no edge crosses over a line.
                        if let tiles { map.insertOverlay(edge, above: tiles) } else { map.addOverlay(edge, level: .aboveLabels) }
                        map.addOverlay(line, level: .aboveLabels)
                        if index < polylines.count {
                            edges[index] = edge
                            polylines[index] = line
                        } else {
                            edges.append(edge)
                            polylines.append(line)
                        }
                    }
                }
                index += 1
            }
            if polylines.count > next.count {
                edges.removeLast(polylines.count - next.count)
                polylines.removeLast(polylines.count - next.count)
            }
            chunks = next
        }

        private static func lineRenderer(_ polyline: MKPolyline, colour: UIColor, width: Double) -> MKPolylineRenderer {
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = colour
            renderer.lineWidth = width
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
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
                applyZoomRange(latitude: camera.center.latitude, to: map)
                map.setCamera(makeCamera(camera, for: map), animated: false)
                return
            }
            applyZoomRange(latitude: camera.center.latitude, to: map)
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

        /// Keeps pinch-zoom within z3-z19 (R8). Recomputed when the view size or latitude (by over a degree) changes.
        private func applyZoomRange(latitude: Double, to map: MKMapView) {
            let height = map.bounds.height
            guard height > 0 else { return }
            if let basis = zoomRangeBasis, basis.height == height, abs(basis.latitude - latitude) < 1 { return }
            let range = CameraMath.distanceRange(latitude: latitude, viewHeight: height, distancePerVisibleHeight: distancePerVisibleHeight)
            map.cameraZoomRange = MKMapView.CameraZoomRange(
                minCenterCoordinateDistance: range.lowerBound, maxCenterCoordinateDistance: range.upperBound
            )
            zoomRangeBasis = (latitude, height)
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
            applyZoomRange(latitude: MKMapPoint(x: rect.midX, y: rect.midY).coordinate.latitude, to: map)
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

/// The dark edge drawn under a trail polyline, so the accent line shows on the light map in every face's colour
/// (R18). A separate, wider line: MapKit sizes both the same way.
private final class TrailEdge: MKPolyline {}

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
