import SwiftUI
import SwiftData
import MapKit

/// Detail sheet for an unvisited place. "I went here" logs it as a Bathroom; "No public restroom here"
/// dismisses it, and a dismissed place offers the undo.
struct CandidateDetailView: View {

    // MARK: - Environment

    @Environment(\.dismiss)      private var dismiss
    @Environment(\.modelContext) private var modelContext

    // MARK: - Input

    let candidate: Candidate
    let userLocation: CLLocationCoordinate2D?

    // MARK: - State

    @State private var showAddView = false

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
                VStack(spacing: 12) {
                    Button { openDirections() } label: {
                        Label("Directions", systemImage: "car.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)

                    Button { showAddView = true } label: {
                        Label("I went here", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)

                    if candidate.isDismissed {
                        Button { candidate.isDismissed = false } label: {
                            Label("Undo: has a public restroom", systemImage: "arrow.uturn.backward.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    } else {
                        // The pin disappears unless "Show dismissed" is on, so close the sheet with it.
                        Button {
                            candidate.isDismissed = true
                            dismiss()
                        } label: {
                            Label("No public restroom here", systemImage: "xmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
                .controlSize(.large)
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
        }
        // Once saved, this place is a Bathroom and its pin is gone, so close the sheet too.
        .fullScreenCover(isPresented: $showAddView, onDismiss: { if isLinked { dismiss() } }) {
            AddBathroomView(userLocation: userLocation, candidate: candidate)
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
                if candidate.isDismissed {
                    Label("No public restroom", systemImage: "xmark.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                } else {
                    Label("Not visited yet", systemImage: "questionmark.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(brand.reliability.tint)
                }
            }
        }
    }

    // MARK: - Helpers

    private var isLinked: Bool {
        let sourceID = candidate.sourceID
        let linked = FetchDescriptor<Bathroom>(predicate: #Predicate { $0.sourceID == sourceID })
        return ((try? modelContext.fetchCount(linked)) ?? 0) > 0
    }

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
