import SwiftUI
import SwiftData
import MapKit

/// Read-only detail sheet for an unvisited place.
struct CandidateDetailView: View {

    // MARK: - Input

    let candidate: Candidate
    let userLocation: CLLocationCoordinate2D?

    // MARK: - Body

    var body: some View {
        let brand = candidate.brand

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                headerSection(brand: brand)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 20)

                DetailSection("Location") {
                    if let address = candidate.address, !address.isEmpty {
                        MetaRow(icon: "location.fill", color: .red, text: address)
                    }
                    if let dist = formattedDistance {
                        MetaRow(icon: "ruler", color: .green, text: dist)
                    }
                }

                DetailSection("Reliability") {
                    MetaRow(
                        icon: brand.reliability.icon,
                        color: brand.reliability.tint,
                        text: "\(brand.reliability.displayName): \(brand.reliability.explanation)"
                    )
                    MetaRow(
                        icon: brand.expectedAccess.icon,
                        color: brand.expectedAccess.color,
                        text: "Expected: \(brand.expectedAccess.displayName)"
                    )
                }

                DetailSection("Hours") {
                    MetaRow(
                        icon: candidate.isOpen24Hours ? "clock.fill" : "clock",
                        color: candidate.isOpen24Hours ? .blue : Color(.systemGray3),
                        text: candidate.isOpen24Hours ? "Open 24 hours" : "Not open 24 hours"
                    )
                }

                Divider()
                Button { openDirections() } label: {
                    Label("Directions", systemImage: "car.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.blue)
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
        }
    }

    // MARK: - Header Section

    private func headerSection(brand: BrandProfile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(candidate.name)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text(brand.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Label("Not visited yet", systemImage: "questionmark.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(brand.reliability.tint)
            }
        }
    }

    // MARK: - Helpers

    private func openDirections() {
        MapURLHelper.openDirections(toLatitude: candidate.latitude, longitude: candidate.longitude, mode: .driving)
    }

    /// Straight-line distance, as a rough guide before driving there.
    private var formattedDistance: String? {
        guard let userLocation else { return nil }
        let origin = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
        let place = CLLocation(latitude: candidate.latitude, longitude: candidate.longitude)
        let formatter = MKDistanceFormatter()
        formatter.unitStyle = .abbreviated
        return "\(formatter.string(fromDistance: place.distance(from: origin))) away"
    }
}

// MARK: - Preview

#Preview {
    CandidateDetailView(
        candidate: Candidate(
            sourceID: "atp:barnes_and_noble_us:2867",
            brandKey: "barnes_and_noble",
            name: "Barnes & Noble (Potomac Yard)",
            latitude: 38.837931,
            longitude: -77.051482,
            address: "3651 Richmond Hwy, Alexandria, VA 22305",
            openingHours: "Mo-Sa 09:00-21:00; Su 11:00-19:00",
            seedVersion: 1
        ),
        userLocation: CLLocationCoordinate2D(latitude: 38.8977, longitude: -77.0365)
    )
    .modelContainer(for: [Bathroom.self, Candidate.self], inMemory: true)
}
