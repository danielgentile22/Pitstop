import CoreLocation
import SwiftData
import SwiftUI

// MARK: - SortOption

enum SortOption: String, CaseIterable {
    case distance  = "Distance"
    case rating    = "Rating"
    case dateAdded = "Date Added"
    case name      = "Name"
}

// MARK: - ListTabView

struct ListTabView: View {

    // MARK: - Dependencies

    var locationManager: LocationManager

    var filter: BathroomFilter

    // MARK: - Data

    @Query(sort: \Bathroom.dateCreated, order: .reverse) private var bathrooms: [Bathroom]
    @Query private var candidates: [Candidate]

    @Environment(\.modelContext)       private var modelContext

    // MARK: - State

    @State private var searchText       = ""
    @State private var sortOption       = SortOption.distance
    @State private var selectedPlace:    MapSelection?
    @State private var bathroomToDelete: Bathroom?
    @State private var showDeleteAlert  = false

    // MARK: - Derived

    /// Visited and unvisited places together. Computed once per render; there can be thousands of Candidates.
    private var displayedPlaces: [MapSelection] {
        let userLocation = locationManager.userLocation

        // BathroomFilter.applies(to:) has no user location, so max distance is checked separately.
        let visited = bathrooms.filter {
            matchesSearch($0.name)
            && filter.applies(to: $0)
            && filter.isWithinMaxDistance($0.coordinate, of: userLocation)
        }
        let unvisited = candidates.unlinked(from: bathrooms).filter {
            matchesSearch($0.name)
            && filter.applies(to: $0)
            && filter.isWithinMaxDistance($0.coordinate, of: userLocation)
        }

        return sorted(visited.map(MapSelection.bathroom) + unvisited.map(MapSelection.candidate))
    }

    private func matchesSearch(_ name: String) -> Bool {
        searchText.isEmpty || name.localizedCaseInsensitiveContains(searchText)
    }

    // MARK: - Body

    var body: some View {
        let places = displayedPlaces

        Group {
            if bathrooms.isEmpty && candidates.isEmpty {
                emptyStateView
            } else if places.isEmpty && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else if places.isEmpty {
                filteredEmptyStateView
            } else {
                listView(places)
            }
        }
        .searchable(text: $searchText, prompt: "Search places…")
        // Same sheet as MapTabView.
        .sheet(item: $selectedPlace) { place in
            Group {
                switch place {
                case .bathroom(let bathroom):
                    DetailView(bathroom: bathroom, userLocation: locationManager.userLocation)
                case .candidate(let candidate):
                    CandidateDetailView(candidate: candidate, userLocation: locationManager.userLocation)
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert("Delete Bathroom?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let bathroom = bathroomToDelete {
                    deleteBathroom(bathroom)
                }
            }
            Button("Cancel", role: .cancel) {
                bathroomToDelete = nil
            }
        } message: {
            Text("This will permanently remove \"\(bathroomToDelete?.name ?? "")\" and all its photos.")
        }
    }

    // MARK: - List

    private func listView(_ places: [MapSelection]) -> some View {
        List {
            sortPickerRow(places)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color(.systemGroupedBackground))

            ForEach(places) { place in
                row(for: place)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedPlace = place
                    }
            }
        }
        .listStyle(.plain)
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: sortOption)
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: searchText)
    }

    /// Only visited bathrooms can be deleted; Candidates come from the bundled seed.
    @ViewBuilder
    private func row(for place: MapSelection) -> some View {
        switch place {
        case .bathroom(let bathroom):
            BathroomRow(bathroom: bathroom, userLocation: locationManager.userLocation)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        bathroomToDelete = bathroom
                        showDeleteAlert  = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
        case .candidate(let candidate):
            CandidateRow(candidate: candidate, userLocation: locationManager.userLocation)
        }
    }

    // MARK: - Sort Picker Row

    private func sortPickerRow(_ places: [MapSelection]) -> some View {
        HStack(spacing: 6) {
            Text("Sort:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Menu {
                Picker("Sort by", selection: $sortOption) {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        if option == .distance && !locationManager.hasLocationPermission {
                            Text(option.rawValue + " (unavailable)").tag(option)
                        } else {
                            Text(option.rawValue).tag(option)
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(sortOption.rawValue)
                        .font(.subheadline.weight(.medium))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.blue)
            }

            Spacer()

            Text(countText(places))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func countText(_ places: [MapSelection]) -> String {
        let unvisited = places.count { if case .candidate = $0 { true } else { false } }
        let saved = places.count - unvisited
        return unvisited == 0 ? "\(saved) saved" : "\(saved) saved · \(unvisited) unvisited"
    }

    // MARK: - Empty States

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Bathrooms Saved", systemImage: "toilet")
        } description: {
            Text("Tap + to add your first bathroom.")
        }
    }

    private var filteredEmptyStateView: some View {
        ContentUnavailableView {
            Label("No Matches", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("No places match the current filters.\nTry adjusting or clearing your filters.")
        }
    }

    // MARK: - Sort Logic

    private func sorted(_ list: [MapSelection]) -> [MapSelection] {
        switch sortOption {
        case .distance:
            guard let coord = locationManager.userLocation else { return list }
            let origin = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            // Measure each place once, not on every comparison.
            return list
                .map { place in (place, CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude).distance(from: origin)) }
                .sorted { $0.1 < $1.1 }
                .map(\.0)

        case .rating:
            // Highest first; unrated (0) and unvisited sort last.
            return list.sorted {
                if $0.rating == $1.rating { return $0.name < $1.name }
                if $0.rating == 0 { return false }
                if $1.rating == 0 { return true }
                return $0.rating > $1.rating
            }

        case .dateAdded:
            // Newest first; unvisited places have no date and sort last, by name.
            return list.sorted {
                switch ($0.dateCreated, $1.dateCreated) {
                case let (lhs?, rhs?): return lhs > rhs
                case (.some, nil):     return true
                case (nil, .some):     return false
                case (nil, nil):       return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            }

        case .name:
            return list.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    // MARK: - Delete

    private func deleteBathroom(_ bathroom: Bathroom) {
        ImageStorage.deleteAllImages(bathroomID: bathroom.id)
        modelContext.delete(bathroom)
        bathroomToDelete = nil
    }
}

// MARK: - Sort Keys

private extension MapSelection {

    var name: String {
        switch self {
        case .bathroom(let bathroom):   return bathroom.name
        case .candidate(let candidate): return candidate.name
        }
    }

    var coordinate: CLLocationCoordinate2D {
        switch self {
        case .bathroom(let bathroom):   return bathroom.coordinate
        case .candidate(let candidate): return candidate.coordinate
        }
    }

    /// 0 for unvisited places, the same as an unrated bathroom.
    var rating: Int {
        switch self {
        case .bathroom(let bathroom): return bathroom.rating
        case .candidate:              return 0
        }
    }

    var dateCreated: Date? {
        switch self {
        case .bathroom(let bathroom): return bathroom.dateCreated
        case .candidate:              return nil
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ListTabView(locationManager: LocationManager(), filter: BathroomFilter())
            .modelContainer(for: [Bathroom.self, Candidate.self], inMemory: true)
    }
}
