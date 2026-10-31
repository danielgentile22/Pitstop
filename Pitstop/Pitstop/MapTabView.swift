import MapKit
import SwiftUI
import SwiftData

struct MapTabView: View {

    // MARK: - Dependencies

    var locationManager: LocationManager

    @Binding var cameraPosition: MapCameraPosition

    var filter: BathroomFilter

    // MARK: - Data

    @Query(sort: \Bathroom.dateCreated, order: .reverse) private var allBathrooms: [Bathroom]
    @Query private var candidates: [Candidate]

    // MARK: - State

    @State private var selection: MapSelection?

    // MARK: - Derived

    /// The same places the list shows, max distance included.
    private var visiblePlaces: (bathrooms: [Bathroom], candidates: [Candidate]) {
        filter.visiblePlaces(bathrooms: allBathrooms, candidates: candidates, userLocation: locationManager.userLocation)
    }

    private var filteredBathrooms: [Bathroom] {
        visiblePlaces.bathrooms
    }

    /// Within 50 km of the user, so zoom-to-fit ignores pins saved in other cities.
    private var nearbyBathrooms: [Bathroom] {
        guard let userCoord = locationManager.userLocation else {
            return filteredBathrooms
        }
        return filteredBathrooms.filter { Distance.meters(from: userCoord, to: $0.coordinate) <= 50_000 }
    }

    // MARK: - Body

    var body: some View {
        let visible = visiblePlaces

        ZStack(alignment: .top) {

            ClusteredMapView(
                cameraPosition: $cameraPosition,
                bathrooms: visible.bathrooms,
                candidates: visible.candidates,
                selection: selection,
                onSelect: select
            )
            .ignoresSafeArea(edges: .bottom)

            if locationManager.isLocationDenied {
                LocationDeniedBanner()
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: locationManager.isLocationDenied)

        .onAppear {
            fitCameraToNearbyBathrooms()
        }
        // Re-fit only when the list goes between empty and non-empty.
        .onChange(of: allBathrooms.isEmpty) {
            fitCameraToNearbyBathrooms()
        }

        .sheet(item: $selection) { selection in
            PlaceDetailSheet(place: selection, userLocation: locationManager.userLocation)
        }
    }

    // MARK: - Selection

    private func select(_ tapped: MapSelection) {
        selection = tapped
    }

    // MARK: - Camera Logic

    /// Fits the camera to nearby bathrooms, or to all filtered ones when none are nearby or location is unknown.
    private func fitCameraToNearbyBathrooms() {
        let candidates = nearbyBathrooms.isEmpty ? filteredBathrooms : nearbyBathrooms
        guard !candidates.isEmpty else { return }
        let region = MKCoordinateRegion(fittingCoordinates: candidates.map(\.coordinate))
        withAnimation(.easeInOut(duration: 0.6)) {
            cameraPosition = .region(region)
        }
    }
}

// MARK: - Map Selection

/// The pin whose detail sheet is open. One sheet for both kinds, so they never fight over presentation.
enum MapSelection: Identifiable {
    case bathroom(Bathroom)
    case candidate(Candidate)

    var id: PersistentIdentifier {
        switch self {
        case .bathroom(let bathroom):   return bathroom.persistentModelID
        case .candidate(let candidate): return candidate.persistentModelID
        }
    }
}

// MARK: - Location Denied Banner

private struct LocationDeniedBanner: View {

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "location.slash.fill")
                .foregroundStyle(.white)

            Text("Location access needed")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)

            Spacer()

            Button("Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.25))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange)
                .shadow(color: .orange.opacity(0.35), radius: 8, y: 4)
        )
    }
}

// MARK: - MKCoordinateRegion: Coordinate Fitting

extension MKCoordinateRegion {

    /// Pads each axis by 30%, with a minimum span of about 500 m so a single pin is not over-zoomed.
    init(fittingCoordinates coordinates: [CLLocationCoordinate2D]) {
        guard !coordinates.isEmpty else {
            self = .unitedStates
            return
        }

        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)

        let centerLat = ((lats.min()! + lats.max()!) / 2.0)
        let centerLon = ((lons.min()! + lons.max()!) / 2.0)

        let spanLat = max((lats.max()! - lats.min()!) * 1.3, 0.005)
        let spanLon = max((lons.max()! - lons.min()!) * 1.3, 0.005)

        self.init(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
            span: MKCoordinateSpan(latitudeDelta: spanLat, longitudeDelta: spanLon)
        )
    }

    static let unitedStates = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
        span: MKCoordinateSpan(latitudeDelta: 60, longitudeDelta: 60)
    )
}

// MARK: - Preview

#Preview {
    MapTabView(
        locationManager: LocationManager(),
        cameraPosition: .constant(.userLocation(followsHeading: false, fallback: .automatic)),
        filter: BathroomFilter()
    )
    .modelContainer(for: [Bathroom.self, Candidate.self], inMemory: true)
}
