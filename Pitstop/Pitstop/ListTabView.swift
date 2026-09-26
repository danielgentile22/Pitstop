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

    @Environment(\.modelContext)       private var modelContext
    @Environment(SupabaseService.self) private var supabaseService
    @Environment(SyncQueue.self)       private var syncQueue

    // MARK: - State

    @State private var searchText       = ""
    @State private var sortOption       = SortOption.dateAdded
    @State private var selectedBathroom: Bathroom?
    @State private var bathroomToDelete: Bathroom?
    @State private var showDeleteAlert  = false

    // MARK: - Derived

    private var displayedBathrooms: [Bathroom] {
        let afterSearch = searchText.isEmpty
            ? bathrooms
            : bathrooms.filter { $0.name.localizedCaseInsensitiveContains(searchText) }

        var afterFilter = filter.isActive
            ? afterSearch.filter { filter.applies(to: $0) }
            : afterSearch

        // BathroomFilter.applies(to:) has no user location, so max distance is applied here.
        if let maxDist = filter.maxDistance, let coord = locationManager.userLocation {
            let origin = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            afterFilter = afterFilter.filter { $0.distance(from: origin) <= maxDist.rawValue }
        }

        return sorted(afterFilter)
    }

    // MARK: - Body

    var body: some View {
        Group {
            if bathrooms.isEmpty {
                emptyStateView
            } else if displayedBathrooms.isEmpty && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else if displayedBathrooms.isEmpty {
                filteredEmptyStateView
            } else {
                listView
            }
        }
        .searchable(text: $searchText, prompt: "Search bathrooms…")
        .sheet(item: $selectedBathroom) { bathroom in
            DetailView(
                bathroom: bathroom,
                userLocation: locationManager.userLocation
            )
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

    private var listView: some View {
        List {
            sortPickerRow
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color(.systemGroupedBackground))

            ForEach(displayedBathrooms) { bathroom in
                BathroomRow(
                    bathroom: bathroom,
                    userLocation: locationManager.userLocation
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedBathroom = bathroom
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if supabaseService.isOwner(of: bathroom) {
                        Button(role: .destructive) {
                            bathroomToDelete = bathroom
                            showDeleteAlert  = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await supabaseService.syncAll(context: modelContext, userLocation: nil, force: true)
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: sortOption)
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: searchText)
    }

    // MARK: - Sort Picker Row

    private var sortPickerRow: some View {
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

            Text("\(displayedBathrooms.count) saved")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
            Text("No bathrooms match the current filters.\nTry adjusting or clearing your filters.")
        }
    }

    // MARK: - Sort Logic

    private func sorted(_ list: [Bathroom]) -> [Bathroom] {
        switch sortOption {
        case .distance:
            guard let coord = locationManager.userLocation else { return list }
            let origin = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            return list.sorted { $0.distance(from: origin) < $1.distance(from: origin) }

        case .rating:
            // Highest first; unrated (0) sorts last.
            return list.sorted {
                if $0.rating == $1.rating { return $0.name < $1.name }
                if $0.rating == 0 { return false }
                if $1.rating == 0 { return true }
                return $0.rating > $1.rating
            }

        case .dateAdded:
            return list.sorted { $0.dateCreated > $1.dateCreated }

        case .name:
            return list.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    // MARK: - Delete

    private func deleteBathroom(_ bathroom: Bathroom) {
        let bid       = bathroom.id
        let fileNames = bathroom.imageFileNames
        ImageStorage.deleteAllImages(bathroomID: bid)
        modelContext.delete(bathroom)
        bathroomToDelete = nil
        syncQueue.enqueue(.deleteBathroom(bathroomID: bid, fileNames: fileNames))
        Task { await syncQueue.drain(supabase: supabaseService, context: modelContext) }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ListTabView(locationManager: LocationManager(), filter: BathroomFilter())
            .modelContainer(for: Bathroom.self, inMemory: true)
            .environment(SupabaseService())
    }
}
