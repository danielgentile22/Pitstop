import SwiftUI
import SwiftData
import MapKit

/// Root view after sign-in. Owns camera and filter state so both survive Map/List switches.
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

    @Environment(SupabaseService.self)  private var supabaseService
    @Environment(NetworkMonitor.self)   private var networkMonitor
    @Environment(SyncQueue.self)        private var syncQueue
    @Environment(\.modelContext)        private var modelContext

    // MARK: - Data

    @Query private var bathrooms: [Bathroom]

    // MARK: - State

    @State private var locationManager    = LocationManager()
    @State private var showProfileSheet   = false
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
    @State private var isSyncing          = false
    @State private var isSearchingEmergency = false

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

                if !networkMonitor.isConnected {
                    OfflineBanner()
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1)
                }

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        EmergencyButton(
                            onTap: { Task { await handleEmergencyTap() } },
                            isLoading: isSearchingEmergency
                        )
                        .padding(.trailing, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: networkMonitor.isConnected)
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
                    if isSyncing {
                        ProgressView()
                            .scaleEffect(0.8)
                            .accessibilityLabel("Syncing")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showProfileSheet = true
                    } label: {
                        Image(systemName: "person.circle")
                    }
                    .accessibilityLabel("Profile")
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
            Task {
                isSyncing = true
                defer { isSyncing = false }
                await supabaseService.syncAll(context: modelContext, userLocation: locationManager.userLocation)
            }
        }
        .fullScreenCover(isPresented: $showAddBathroom) {
            AddBathroomView(userLocation: locationManager.userLocation)
        }
        .sheet(isPresented: $showFilterSheet) {
            FilterSheetView(filter: $filter)
        }
        .sheet(isPresented: $showProfileSheet) {
            ProfileView()
        }
    }

    // MARK: - Emergency Logic

    /// Opens directions to the nearest cached bathroom, falling back to a server query when none are cached.
    private func handleEmergencyTap() async {
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

        if !bathrooms.isEmpty {
            // Straight-line distance: no routing call, so it works offline.
            guard let nearest = bathrooms.min(by: {
                $0.distance(from: origin) < $1.distance(from: origin)
            }) else { return }
            MapURLHelper.openDirections(toLatitude: nearest.latitude, longitude: nearest.longitude)
        } else {
            guard networkMonitor.isConnected else {
                emergencyAlertMsg = "No bathrooms saved and you're offline. Add bathrooms while connected so they're available in an emergency."
                showEmergencyAlert = true
                return
            }

            isSearchingEmergency = true
            defer { isSearchingEmergency = false }

            do {
                guard let remote = try await supabaseService.findNearestBathroom(near: userCoord) else {
                    emergencyAlertMsg = "No bathrooms found nearby. Try adding some to help others too!"
                    showEmergencyAlert = true
                    return
                }
                MapURLHelper.openDirections(toLatitude: remote.latitude, longitude: remote.longitude)
            } catch {
                emergencyAlertMsg = "Could not search for bathrooms. Please try again."
                showEmergencyAlert = true
            }
        }
    }
}

// MARK: - Offline Banner

private struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .foregroundStyle(.white)

            Text("No internet connection")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)

            Spacer()

            Text("Offline mode")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.2))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.gray)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        )
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .modelContainer(for: Bathroom.self, inMemory: true)
        .environment(SupabaseService())
        .environment(NetworkMonitor())
        .environment(SyncQueue())
}
