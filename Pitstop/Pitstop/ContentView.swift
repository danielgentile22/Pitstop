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

    // MARK: - State

    @State private var locationManager    = LocationManager()
    @State private var selectedView: ViewMode = .map
    @State private var mapCameraPosition: MapCameraPosition = .userLocation(
        followsHeading: false,
        fallback: .region(.unitedStates)
    )
    @State private var showAddBathroom    = false
    @State private var filter             = BathroomFilter()
    @State private var showFilterSheet    = false
    @State private var showEmergencyAlert = false
    @State private var emergencyAlertMsg  = ""

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
                        EmergencyButton(onTap: handleEmergencyTap)
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

    /// Opens walking directions to the nearest saved bathroom.
    private func handleEmergencyTap() {
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

        let origin = CLLocation(latitude: userCoord.latitude, longitude: userCoord.longitude)

        // Straight-line distance: no routing call, so it works offline.
        guard let nearest = bathrooms.min(by: {
            $0.distance(from: origin) < $1.distance(from: origin)
        }) else {
            emergencyAlertMsg = "No bathrooms saved yet. Add some so they're ready in an emergency."
            showEmergencyAlert = true
            return
        }
        MapURLHelper.openDirections(toLatitude: nearest.latitude, longitude: nearest.longitude)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .modelContainer(for: Bathroom.self, inMemory: true)
}
