import CoreLocation
import MapKit
import SwiftUI

/// List row for an unvisited place. Uses the map's dimmed question-mark pin as its thumbnail
/// so it never reads as a bathroom the user has checked.
struct CandidateRow: View {

    // MARK: - Input

    let candidate: Candidate
    let userLocation: CLLocationCoordinate2D?

    // MARK: - Constants

    private let thumbSize: CGFloat   = 72
    private let thumbRadius: CGFloat = 10

    // MARK: - Body

    var body: some View {
        let brand = candidate.brand

        HStack(alignment: .top, spacing: 12) {
            CandidateAnnotation(reliability: brand.reliability, isSelected: false, isDismissed: candidate.isDismissed)
                .frame(width: thumbSize, height: thumbSize)
                .background(Color(.secondarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: thumbRadius, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {

                Text(candidate.name)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Label(candidate.isDismissed ? "Dismissed" : "Unvisited",
                          systemImage: candidate.isDismissed ? "xmark.circle" : "questionmark.circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(candidate.isDismissed ? .red : brand.reliability.tint)
                        .lineLimit(1)

                    Text("·").font(.caption).foregroundStyle(Color(.systemGray3))
                    Text(brand.reliability.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let dist = formattedDistance {
                        Text("·").font(.caption).foregroundStyle(Color(.systemGray3))
                        Text(dist).font(.caption).foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 6) {
                    switch candidate.isOpen24HoursIfKnown {
                    case true?:
                        Image(systemName: "clock.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.blue)
                            .accessibilityLabel("24 hours")
                    case false?:
                        EmptyView()
                    case nil:
                        Text("Hours unknown")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                    if let address = candidate.address, !address.isEmpty {
                        Text(address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Distance

    private var formattedDistance: String? {
        Distance.formatted(from: userLocation, to: candidate.coordinate)
    }
}

// MARK: - Preview

#Preview {
    let target = Candidate(
        sourceID: "atp:target:1", brandKey: "target", name: "Target",
        latitude: 38.80, longitude: -77.05,
        address: "3101 Jefferson Davis Hwy, Alexandria, VA 22305",
        seedVersion: 1
    )
    let walmart = Candidate(
        sourceID: "atp:walmart:1", brandKey: "walmart", name: "Walmart Supercenter",
        latitude: 38.66, longitude: -77.25,
        isOpen24Hours: true, seedVersion: 1
    )
    List {
        CandidateRow(candidate: target,  userLocation: CLLocationCoordinate2D(latitude: 38.81, longitude: -77.05))
        CandidateRow(candidate: walmart, userLocation: nil)
    }
    .listStyle(.plain)
}
