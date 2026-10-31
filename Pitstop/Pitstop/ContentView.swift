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
        // The Map tab fits the camera again once there are bathrooms, even if it was not showing when they came.
        .onChange(of: bathrooms.isEmpty) { _, isEmpty in
            if isEmpty { hasFittedMapCamera = false }
        }
        .fullScreenCover(isPresented: $showAddBathroom) {
            AddBathroomView(userLocation: locationManager.userLocation)
        }
        .sheet(isPresented: $showFilterSheet) {
            FilterSheetView(filter: $filter)
        }
    }

    // MARK: - Emergency Logic

    /// Fresh fix plus driving times, from tap to answer.
    private static let emergencyDeadline: Duration = .seconds(3)

    /// Opens driving directions to the place with the fewest effective minutes.
    private func handleEmergencyTap() async {
        // A second tap during the lookup would open Maps twice.
        guard !isFindingRoute else { return }

        guard locationManager.hasLocationPermission else {
            emergencyAlertMsg = "Enable location access in Settings to find the nearest bathroom."
            showEmergencyAlert = true
            return
        }

        isFindingRoute = true
        defer { isFindingRoute = false }

        // The prompt waits on the user, so the deadline starts after it.
        await locationManager.requestTemporaryFullAccuracy()
        let deadline = ContinuousClock.now + Self.emergencyDeadline

        guard let userCoord = await locationManager.freshFix(timeout: .seconds(2))?.coordinate else {
            emergencyAlertMsg = "Waiting for your location. Please try again in a moment."
            showEmergencyAlert = true
            return
        }

        let visited = bathrooms.map(EmergencyRanker.VisitedPlace.init)
        let unvisited = candidates.map(EmergencyRanker.UnvisitedPlace.init)

        // Driving times for the closest few; anything that misses the deadline (or has no signal)
        // falls back to straight-line distance inside the ranker.
        let nearest = EmergencyRanker.nearest(8, from: userCoord, visited: visited, unvisited: unvisited)
        let drivingTimes = await DrivingTimeLookup.drivingTimes(
            from: userCoord,
            to: nearest,
            deadline: ContinuousClock.now.duration(to: deadline)
        )

        let ranked = EmergencyRanker.rank(
            from: userCoord,
            at: .now,
            visited: visited,
            unvisited: unvisited,
            drivingTimes: drivingTimes
        )

        guard let best = ranked.first else {
            emergencyAlertMsg = "Nothing is in range. No saved bathroom or unvisited place is close enough to send you to."
            showEmergencyAlert = true
            return
        }
        guard await MapURLHelper.openDirections(toLatitude: best.latitude, longitude: best.longitude, mode: .driving) else {
            emergencyAlertMsg = "Apple Maps could not be opened. Try again, or open Maps yourself."
            showEmergencyAlert = true
            return
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .modelContainer(for: [Bathroom.self, Candidate.self], inMemory: true)
}
