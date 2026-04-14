//
//  ListTabView.swift
//  GeoPoop
//
//  Scrollable list of all saved bathrooms with search, sort, tap-to-detail,
//  and swipe-to-delete. Presents DetailView as a sheet on row tap.
//
//  Architecture notes:
//  - @Query fetches all bathrooms; filtering/sorting is done in Swift after
//    the query because distance sort requires a runtime CLLocation value.
//  - LocationManager is passed in (not owned here) so distance calculations
//    share the same live coordinate as the map view.
//

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

    /// Shared location manager — used for live distance calculations.
    var locationManager: LocationManager

    /// Active filter — passed in from ContentView, applied to displayedBathrooms.
    var filter: BathroomFilter

    // MARK: - Data

    /// All saved bathrooms from SwiftData.
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

    /// Bathrooms after search, filter (including distance), and sort — what the list displays.
    private var displayedBathrooms: [Bathroom] {
        let afterSearch = searchText.isEmpty
            ? bathrooms
            : bathrooms.filter { $0.name.localizedCaseInsensitiveContains(searchText) }

        var afterFilter = filter.isActive
            ? afterSearch.filter { filter.applies(to: $0) }
            : afterSearch

        // Apply maxDistance filter — requires live user location, so handled here
        // rather than inside BathroomFilter.applies(to:).
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
                // No bathrooms saved at all
                emptyStateView
            } else if displayedBathrooms.isEmpty && !searchText.isEmpty {
                // Bathrooms exist but search matched nothing
                ContentUnavailableView.search(text: searchText)
            } else if displayedBathrooms.isEmpty {
                // Bathrooms exist but the active filter matched nothing
                filteredEmptyStateView
            } else {
                listView
            }
        }
        .searchable(text: $searchText, prompt: "Search bathrooms…")
        // Detail sheet on row tap
        .sheet(item: $selectedBathroom) { bathroom in
            DetailView(
                bathroom: bathroom,
                userLocation: locationManager.userLocation
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        // Delete confirmation
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
            // ── Sort Picker ────────────────────────────────────────────────
            sortPickerRow
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color(.systemGroupedBackground))

            // ── Bathroom Rows ──────────────────────────────────────────────
            ForEach(displayedBathrooms) { bathroom in
                BathroomRow(
                    bathroom: bathroom,
                    userLocation: locationManager.userLocation
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedBathroom = bathroom
                }
                // Swipe left to delete — only for bathrooms the user owns
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
        // Animate list reorder when sort option changes
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: sortOption)
        // Animate filter changes as the user types
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
                        // Distance option is unavailable if location is denied
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

    /// Returns `list` sorted by the current `sortOption`.
    private func sorted(_ list: [Bathroom]) -> [Bathroom] {
        switch sortOption {
        case .distance:
            guard let coord = locationManager.userLocation else { return list }
            let origin = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            return list.sorted { $0.distance(from: origin) < $1.distance(from: origin) }

        case .rating:
            // Descending rating; unrated (0) goes to the end
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
