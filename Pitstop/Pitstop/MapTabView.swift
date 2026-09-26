//
//  MapTabView.swift
//  Pitstop
//
//  The primary map view. Shows saved bathrooms as color-coded pins,
//  the user's live location, and a banner when location access is denied.
//
//  Architecture notes:
//  - Camera position is owned by ContentView (@Binding) so it survives
//    Map ↔ List view switches without resetting.
//  - Bathroom records are queried live from SwiftData via @Query.
//  - The active BathroomFilter is applied in the view layer (not in the
//    @Query predicate) because distance-based filtering needs a live
//    CLLocation that a SwiftData predicate cannot provide.
//  - Pin selection is tracked locally and drives the detail sheet.
//  - fitCameraToSavedBathrooms() constrains the zoom-to-fit to bathrooms
//    within ~50 km of the user to avoid bizarre wide-angle fits when a
//    handful of pins are scattered globally.
//

import MapKit
import SwiftUI
import SwiftData

struct MapTabView: View {

    // MARK: - Dependencies

    /// Provides authorization status and the user's live coordinate.
    var locationManager: LocationManager

    /// Map camera position, lifted to ContentView so it survives view switches.
    @Binding var cameraPosition: MapCameraPosition

    /// Active filter criteria, owned by ContentView.
    var filter: BathroomFilter

    // MARK: - Data

    /// All saved bathrooms, live-synced from SwiftData. Newest entries first.
    @Query(sort: \Bathroom.dateCreated, order: .reverse) private var allBathrooms: [Bathroom]

    // MARK: - State

    /// The bathroom whose pin was most recently tapped. Non-nil → detail sheet shows.
    @State private var selectedBathroom: Bathroom?

    // MARK: - Derived

    /// Bathrooms that pass the active filter criteria.
    ///
    /// Distance filtering (maxDistance) is intentionally excluded here because
    /// it changes continuously as the user moves, which would cause pins to
    /// appear/disappear during panning and is confusing on a map. Distance
    /// filtering is only applied in the List view where the user explicitly
    /// expects proximity-sorted, distance-limited results.
    private var filteredBathrooms: [Bathroom] {
        guard filter.isActive else { return allBathrooms }
        return allBathrooms.filter { filter.applies(to: $0) }
    }

    /// Bathrooms within 50 km of the user, used to constrain the zoom-to-fit
    /// camera calculation. Falls back to all filtered bathrooms if no user
    /// location is available.
    private var nearbyBathrooms: [Bathroom] {
        guard let userCoord = locationManager.userLocation else {
            return filteredBathrooms
        }
        let origin = CLLocation(latitude: userCoord.latitude, longitude: userCoord.longitude)
        return filteredBathrooms.filter { $0.distance(from: origin) <= 50_000 }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {

            // ── Map ────────────────────────────────────────────────────────────
            Map(position: $cameraPosition) {

                // Blue pulsing dot at the user's live position
                UserAnnotation()

                // One custom pin per filtered bathroom
                ForEach(filteredBathrooms) { bathroom in
                    Annotation(
                        bathroom.name,
                        coordinate: bathroom.coordinate,
                        anchor: .center
                    ) {
                        BathroomAnnotation(
                            rating: bathroom.rating,
                            isSelected: selectedBathroom?.id == bathroom.id
                        )
                        .onTapGesture {
                            toggleSelection(bathroom)
                        }
                    }
                }
            }
            .mapControls {
                MapUserLocationButton()  // Re-center on user
                MapCompass()
                MapScaleView()
            }
            .mapStyle(.standard(pointsOfInterest: .including([.restroom])))
            .ignoresSafeArea(edges: .bottom)

            // ── Location Denied Banner ─────────────────────────────────────────
            if locationManager.isLocationDenied {
                LocationDeniedBanner()
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: locationManager.isLocationDenied)

        // ── Camera Initialization ──────────────────────────────────────────────
        // Zoom to fit nearby bathrooms on first appear; no-op if none exist.
        .onAppear {
            fitCameraToNearbyBathrooms()
        }
        // Re-fit only when the list transitions between empty and non-empty.
        .onChange(of: allBathrooms.isEmpty) {
            fitCameraToNearbyBathrooms()
        }

        // ── Detail Sheet ───────────────────────────────────────────────────────
        .sheet(item: $selectedBathroom) { bathroom in
            DetailView(
                bathroom: bathroom,
                userLocation: locationManager.userLocation
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Selection

    private func toggleSelection(_ bathroom: Bathroom) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            selectedBathroom = (selectedBathroom?.id == bathroom.id) ? nil : bathroom
        }
    }

    // MARK: - Camera Logic

    /// Zooms the camera to fit bathrooms within 50 km of the user.
    ///
    /// Using nearby bathrooms rather than all bathrooms prevents the map
    /// from zooming out to country-level when the user has saved pins spread
    /// across multiple cities or countries. The 50 km threshold is generous
    /// enough to capture a reasonable driving radius around the user.
    ///
    /// Falls back to all filtered bathrooms when no user location is available
    /// (simulator, location permission not yet granted).
    private func fitCameraToNearbyBathrooms() {
        let candidates = nearbyBathrooms.isEmpty ? filteredBathrooms : nearbyBathrooms
        guard !candidates.isEmpty else { return }
        let region = MKCoordinateRegion(fittingCoordinates: candidates.map(\.coordinate))
        withAnimation(.easeInOut(duration: 0.6)) {
            cameraPosition = .region(region)
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

    /// Builds a region that comfortably contains all given coordinates.
    ///
    /// Adds 30% padding on each axis so pins don't sit flush against the edges.
    /// The minimum span of ~500m prevents over-zooming on a single pin.
    ///
    /// - Parameter coordinates: The coordinates to fit. Must not be empty.
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

    /// Fallback region: continental United States, country-level zoom.
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
    .modelContainer(for: Bathroom.self, inMemory: true)
}
