import SwiftUI
import SwiftData
import MapKit

/// Root view. Owns camera and filter state so both survive Map/List switches.
struct ContentView: View {

    // MARK: - View Mode

    enum ViewMode: String, CaseIterable {
        case map  = "Map"
        case list = "List"

        var iconName: String {
            switch self {
            case .map:  return "map.fill"
            case .list: return "list.bullet"
            }
        }
    }

    // MARK: - Environment


    // MARK: - Data

    @Query private var bathrooms: [Bathroom]
    @Query private var candidates: [Candidate]

    // MARK: - State

    @State private var locationManager    = LocationManager()
    @State private var selectedView: ViewMode = .map
    @State private var mapCameraPosition: MapCameraPosition = .userLocation(
        followsHeading: false,
        fallback: .region(.unitedStates)
    )
    @State private var hasFittedMapCamera = false
    @State private var showAddBathroom    = false
    @State private var filter             = BathroomFilter()
    @State private var showFilterSheet    = false
    @State private var showEmergencyAlert = false
    @State private var emergencyAlertMsg  = ""
    @State private var isFindingRoute     = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {

                Group {
                    switch selectedView {
                    case .map:
                        MapTabView(
                            locationManager: locationManager,
                            cameraPosition: $mapCameraPosition,
                            hasFittedCamera: $hasFittedMapCamera,
                            filter: filter
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))

                    case .list:
                        ListTabView(locationManager: locationManager, filter: filter)
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }
                }
                .animation(.spring(response: 0.38, dampingFraction: 0.88), value: selectedView)


                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        EmergencyButton(isWorking: isFindingRoute) {
                            Task { await handleEmergencyTap() }
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("Pitstop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $selectedView) {
                        ForEach(ViewMode.allCases, id: \.self) { mode in
                            Label(mode.rawValue, systemImage: mode.iconName)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }

                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showFilterSheet = true
                    } label: {
                        Image(systemName: filter.isActive
                              ? "line.3.horizontal.decrease.circle.fill"
                              : "line.3.horizontal.decrease.circle")
                            .foregroundStyle(filter.isActive ? .blue : .primary)
                    }
                    .accessibilityLabel(filter.isActive ? "Filters active" : "Filter bathrooms")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddBathroom = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("Emergency", isPresented: $showEmergencyAlert) {
                if locationManager.isLocationDenied {
                    Button("Open Settings") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                    Button("Cancel", role: .cancel) {}
                } else {
                    Button("OK", role: .cancel) {}
                }
            } message: {
                Text(emergencyAlertMsg)
            }
        }
        .onAppear {
            locationManager.requestPermission()
        }
        .fullScreenCover(isPresented: $showAddBathroom) {
            AddBathroomView(userLocation: locationManager.userLocation)
        }
        .sheet(isPresented: $showFilterSheet) {
            FilterSheetView(filter: $filter)
        }
    }

    // MARK: - Emergency Logic

    /// Opens driving directions to the place with the fewest effective minutes.
    private func handleEmergencyTap() async {
        // A second tap during the lookup would open Maps twice.
        guard !isFindingRoute else { return }

        guard locationManager.hasLocationPermission else {
            emergencyAlertMsg = "Enable location access in Settings to find the nearest bathroom."
            showEmergencyAlert = true
            return
        }

        guard let userCoord = locationManager.userLocation else {
            emergencyAlertMsg = "Waiting for your location. Please try again in a moment."
            showEmergencyAlert = true
            return
        }

        let visited: [EmergencyRanker.VisitedPlace] = bathrooms.map {
            .init(id: $0.id, sourceID: $0.sourceID, latitude: $0.latitude, longitude: $0.longitude,
                  rating: $0.rating, isOpen24Hours: $0.isOpen24Hours)
        }
        let unvisited: [EmergencyRanker.UnvisitedPlace] = candidates.map {
            .init(sourceID: $0.sourceID, latitude: $0.latitude, longitude: $0.longitude,
                  reliability: $0.brand.reliability, isOpen24Hours: $0.isOpen24HoursIfKnown,
                  isDismissed: $0.isDismissed)
        }

        // Driving times for the closest few; anything that misses the deadline (or has no signal)
        // falls back to straight-line distance inside the ranker.
        let nearest = EmergencyRanker.nearest(8, from: userCoord, visited: visited, unvisited: unvisited)
        isFindingRoute = true
        let drivingTimes = await DrivingTimeLookup.drivingTimes(from: userCoord, to: nearest)
        isFindingRoute = false

        let ranked = EmergencyRanker.rank(
            from: userCoord,
            at: .now,
            visited: visited,
            unvisited: unvisited,
            drivingTimes: drivingTimes
        )

        guard let best = ranked.first else {
            emergencyAlertMsg = "No saved bathrooms or unvisited places to go to. Add a bathroom so one is ready in an emergency."
            showEmergencyAlert = true
            return
        }
        MapURLHelper.openDirections(toLatitude: best.latitude, longitude: best.longitude, mode: .driving)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .modelContainer(for: [Bathroom.self, Candidate.self], inMemory: true)
}
