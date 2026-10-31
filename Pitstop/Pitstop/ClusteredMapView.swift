import MapKit
import SwiftUI
import SwiftData

/// `MKMapView` wrapper, because SwiftUI's `Map` cannot cluster pins and slows down with thousands of them.
/// Pins are the SwiftUI pin views, rendered once per look into images.
struct ClusteredMapView: UIViewRepresentable {

    @Binding var cameraPosition: MapCameraPosition

    let bathrooms: [Bathroom]
    let candidates: [Candidate]

    /// Pins deselect when this goes nil (the detail sheet closed).
    let selection: MapSelection?
    let onSelect: (MapSelection) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> PlaceMapView {
        let mapView = PlaceMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = false
        mapView.showsScale = true
        mapView.pointOfInterestFilter = MKPointOfInterestFilter(including: [.restroom])
        mapView.register(PlacePinView.self, forAnnotationViewWithReuseIdentifier: PlacePinView.reuseID)
        mapView.register(ClusterPinView.self, forAnnotationViewWithReuseIdentifier: ClusterPinView.reuseID)
        addControls(to: mapView)
        return mapView
    }

    func updateUIView(_ mapView: PlaceMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.syncAnnotations(on: mapView)
        coordinator.apply(cameraPosition, to: mapView, animated: context.transaction.animation != nil)

        if selection == nil {
            for annotation in mapView.selectedAnnotations where annotation is PlaceAnnotation {
                mapView.deselectAnnotation(annotation, animated: true)
            }
        }
    }

    /// Location button with the compass under it, top trailing like SwiftUI `Map`'s controls.
    private func addControls(to mapView: MKMapView) {
        let trackingButton = MKUserTrackingButton(mapView: mapView)
        trackingButton.backgroundColor = .secondarySystemBackground
        trackingButton.layer.cornerRadius = 8
        trackingButton.clipsToBounds = true

        let compass = MKCompassButton(mapView: mapView)
        compass.compassVisibility = .adaptive

        let stack = UIStackView(arrangedSubviews: [trackingButton, compass])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        mapView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.topAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            trackingButton.widthAnchor.constraint(equalToConstant: 44),
            trackingButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {

        var parent: ClusteredMapView

        private var annotations: [PersistentIdentifier: PlaceAnnotation] = [:]

        /// The last camera position the map was moved to or reported, so a write-back does not move it again.
        private var appliedPosition: MapCameraPosition?

        init(parent: ClusteredMapView) {
            self.parent = parent
        }

        /// Adds and removes only what changed, so an update with thousands of pins stays cheap.
        func syncAnnotations(on mapView: MKMapView) {
            var wanted: [PersistentIdentifier: MapSelection] = [:]
            for candidate in parent.candidates { wanted[candidate.persistentModelID] = .candidate(candidate) }
            for bathroom in parent.bathrooms { wanted[bathroom.persistentModelID] = .bathroom(bathroom) }

            var stale: [PlaceAnnotation] = []
            var fresh: [PlaceAnnotation] = []

            for (id, existing) in annotations where wanted[id] == nil {
                stale.append(existing)
                annotations[id] = nil
            }
            for (id, place) in wanted {
                let look = PinLook(place)
                if let existing = annotations[id] {
                    guard existing.look != look else { continue }
                    stale.append(existing)
                }
                let annotation = PlaceAnnotation(place: place, look: look)
                annotations[id] = annotation
                fresh.append(annotation)
            }

            if !stale.isEmpty { mapView.removeAnnotations(stale) }
            if !fresh.isEmpty { mapView.addAnnotations(fresh) }
        }

        func apply(_ position: MapCameraPosition, to mapView: PlaceMapView, animated: Bool) {
            guard position != appliedPosition else { return }
            appliedPosition = position

            // A region set before the first layout is fitted to a zero-size map.
            guard !mapView.bounds.isEmpty else {
                mapView.onFirstLayout = { [weak self, weak mapView] in
                    guard let self, let mapView else { return }
                    self.appliedPosition = nil
                    self.apply(position, to: mapView, animated: false)
                }
                return
            }

            if let region = position.region {
                mapView.setUserTrackingMode(.none, animated: false)
                mapView.setRegion(region, animated: animated)
            } else if position.followsUserLocation {
                if mapView.userLocation.location == nil, let fallback = position.fallbackPosition?.region {
                    mapView.setRegion(fallback, animated: false)
                }
                mapView.setUserTrackingMode(position.followsUserHeading ? .followWithHeading : .follow, animated: animated)
            }
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            switch annotation {
            case is MKClusterAnnotation:
                return mapView.dequeueReusableAnnotationView(withIdentifier: ClusterPinView.reuseID, for: annotation)
            case is PlaceAnnotation:
                return mapView.dequeueReusableAnnotationView(withIdentifier: PlacePinView.reuseID, for: annotation)
            default:
                return nil  // the user's location dot
            }
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            if let cluster = annotation as? MKClusterAnnotation {
                mapView.deselectAnnotation(cluster, animated: false)
                open(cluster, on: mapView)
            } else if let place = annotation as? PlaceAnnotation {
                parent.onSelect(place.place)
            }
        }

        /// Keeps the binding current so the map comes back where the user left it after the List tab,
        /// still following the user if it was.
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let region = MapCameraPosition.region(mapView.region)
            let position: MapCameraPosition
            switch mapView.userTrackingMode {
            case .follow:            position = .userLocation(followsHeading: false, fallback: region)
            case .followWithHeading: position = .userLocation(followsHeading: true, fallback: region)
            default:                 position = region
            }
            appliedPosition = position
            // Can fire inside updateUIView (an unanimated setRegion), where SwiftUI state must not change.
            DispatchQueue.main.async { [weak self] in
                self?.parent.cameraPosition = position
            }
        }

        /// Zooms in until the cluster splits. Members too close together to ever split open the first one.
        private func open(_ cluster: MKClusterAnnotation, on mapView: MKMapView) {
            let members = cluster.memberAnnotations
            let rect = members.reduce(MKMapRect.null) { rect, member in
                rect.union(MKMapRect(origin: MKMapPoint(member.coordinate), size: MKMapSize(width: 0, height: 0)))
            }
            let pointsPerMeter = MKMapPointsPerMeterAtLatitude(cluster.coordinate.latitude)
            if max(rect.size.width, rect.size.height) / pointsPerMeter < 30 {
                if let first = members.first as? PlaceAnnotation {
                    parent.onSelect(first.place)
                }
                return
            }
            mapView.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 80, left: 60, bottom: 80, right: 60), animated: true)
        }
    }
}

// MARK: - Map View

/// Reports its first real layout, so a camera position set before then can be applied at the right size.
final class PlaceMapView: MKMapView {

    var onFirstLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !bounds.isEmpty, let onFirstLayout else { return }
        self.onFirstLayout = nil
        onFirstLayout()
    }
}

// MARK: - Annotations

/// Everything a pin's appearance depends on. An annotation is replaced only when this changes.
struct PinLook: Equatable {
    let latitude: Double
    let longitude: Double
    let style: PinStyle
    let accessibilityLabel: String

    init(_ place: MapSelection) {
        switch place {
        case .bathroom(let bathroom):
            latitude = bathroom.latitude
            longitude = bathroom.longitude
            style = .bathroom(rating: bathroom.rating)
            let ratingText = bathroom.rating > 0 ? "\(bathroom.rating) out of 5 stars" : "unrated"
            accessibilityLabel = "\(bathroom.name), \(ratingText)"
        case .candidate(let candidate):
            let brand = candidate.brand
            latitude = candidate.latitude
            longitude = candidate.longitude
            if candidate.isDismissed {
                style = .dismissed
                accessibilityLabel = "\(candidate.name), dismissed, no public restroom"
            } else {
                style = .candidate(brand.reliability)
                accessibilityLabel = "\(candidate.name), unvisited, \(brand.reliability.displayName.lowercased())"
            }
        }
    }
}

enum PinStyle: Hashable {
    case bathroom(rating: Int)
    case candidate(Reliability)
    /// A Candidate marked "No public restroom here", shown only while "Show dismissed" is on.
    case dismissed

    /// Visited and unvisited pins cluster apart, so a bathroom never disappears into a cluster of guesses.
    var clusteringIdentifier: String {
        switch self {
        case .bathroom:              return "bathroom"
        case .candidate, .dismissed: return "candidate"
        }
    }
}

final class PlaceAnnotation: NSObject, MKAnnotation {

    let place: MapSelection
    let look: PinLook
    let coordinate: CLLocationCoordinate2D

    init(place: MapSelection, look: PinLook) {
        self.place = place
        self.look = look
        self.coordinate = CLLocationCoordinate2D(latitude: look.latitude, longitude: look.longitude)
    }
}

// MARK: - Annotation Views

final class PlacePinView: MKAnnotationView {

    static let reuseID = "place"

    private var normalImage: UIImage?
    private var selectedImage: UIImage?

    override func prepareForDisplay() {
        super.prepareForDisplay()
        guard let look = (annotation as? PlaceAnnotation)?.look else { return }

        normalImage = PinImages.image(for: .pin(look.style, selected: false), scale: traitCollection.displayScale)
        selectedImage = PinImages.image(for: .pin(look.style, selected: true), scale: traitCollection.displayScale)
        image = isSelected ? selectedImage : normalImage

        clusteringIdentifier = look.style.clusteringIdentifier
        collisionMode = .circle
        // Visited pins draw above unvisited ones at the same spot.
        if case .bathroom = look.style {
            zPriority = MKAnnotationViewZPriority(rawValue: MKAnnotationViewZPriority.defaultUnselected.rawValue + 1)
        } else {
            zPriority = .defaultUnselected
        }

        isAccessibilityElement = true
        accessibilityLabel = look.accessibilityLabel
        accessibilityTraits = .button
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        image = selected ? selectedImage : normalImage
    }
}

final class ClusterPinView: MKAnnotationView {

    static let reuseID = "cluster"

    override func prepareForDisplay() {
        super.prepareForDisplay()
        guard let cluster = annotation as? MKClusterAnnotation else { return }

        let styles = cluster.memberAnnotations.compactMap { ($0 as? PlaceAnnotation)?.look.style }
        let kind = Self.kind(of: styles)
        image = PinImages.image(for: .cluster(kind, count: styles.count), scale: traitCollection.displayScale)
        collisionMode = .circle
        if kind == .bathrooms {
            zPriority = MKAnnotationViewZPriority(rawValue: MKAnnotationViewZPriority.defaultUnselected.rawValue + 1)
        } else {
            zPriority = .defaultUnselected
        }

        isAccessibilityElement = true
        accessibilityLabel = kind == .bathrooms
            ? "\(styles.count) bathrooms, zoom in"
            : "\(styles.count) unvisited places, zoom in"
        accessibilityTraits = .button
    }

    private static func kind(of styles: [PinStyle]) -> ClusterAnnotation.Kind {
        let levels = styles.compactMap { style -> Reliability? in
            switch style {
            case .bathroom:            return nil
            case .candidate(let level): return level
            case .dismissed:           return .uncertain
            }
        }
        guard !levels.isEmpty else { return .bathrooms }
        let mostReliable = Reliability.allCases.first(where: levels.contains) ?? .uncertain
        return .candidates(mostReliable)
    }
}

// MARK: - Pin Images

/// SwiftUI pin views rendered to images once per look and reused by every pin that shares it.
private enum PinImages {

    enum Key: Hashable {
        case pin(PinStyle, selected: Bool)
        case cluster(ClusterAnnotation.Kind, count: Int)
    }

    private static var cache: [Key: UIImage] = [:]

    static func image(for key: Key, scale: CGFloat) -> UIImage {
        if let cached = cache[key] { return cached }

        let content: AnyView
        switch key {
        case .pin(.bathroom(let rating), let selected):
            content = AnyView(BathroomAnnotation(rating: rating, isSelected: selected))
        case .pin(.candidate(let reliability), let selected):
            let brand = BrandProfile(key: reliability.rawValue, displayName: reliability.displayName,
                                     reliability: reliability, expectedAccess: .free)
            content = AnyView(CandidateAnnotation(brand: brand, isSelected: selected))
        case .pin(.dismissed, let selected):
            let brand = BrandProfile(key: "dismissed", displayName: "Dismissed",
                                     reliability: .uncertain, expectedAccess: .free)
            content = AnyView(CandidateAnnotation(brand: brand, isSelected: selected, isDismissed: true))
        case .cluster(let kind, let count):
            content = AnyView(ClusterAnnotation(kind: kind, count: count))
        }

        // Padding keeps shadows and the question mark badge from being clipped.
        let renderer = ImageRenderer(content: content.padding(8))
        renderer.scale = scale >= 1 ? scale : 3
        let image = renderer.uiImage ?? UIImage()
        cache[key] = image
        return image
    }
}
