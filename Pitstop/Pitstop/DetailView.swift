import SwiftUI
import SwiftData
import MapKit

/// Detail sheet for a saved bathroom, shown at the medium detent and draggable to large.
struct DetailView: View {

    // MARK: - Input

    let bathroom: Bathroom
    let userLocation: CLLocationCoordinate2D?

    // MARK: - Environment

    @Environment(\.dismiss)            private var dismiss
    @Environment(\.modelContext)       private var modelContext

    // MARK: - State

    @State private var showDeleteAlert = false
    @State private var showEditView    = false
    @State private var deleteError: BathroomSaver.SaveError?

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                headerSection
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 20)

                if !bathroom.imageFileNames.isEmpty {
                    Divider()
                    PhotoCarousel(bathroom: bathroom)
                        .padding(.vertical, 16)
                }

                DetailSection("Location") {
                    if let address = bathroom.address, !address.isEmpty {
                        MetaRow(icon: "location.fill", color: .red, text: address)
                    }
                    MetaRow(
                        icon: "calendar",
                        color: .blue,
                        text: bathroom.dateVisited.formatted(date: .long, time: .omitted)
                    )
                    if let dist = formattedDistance {
                        MetaRow(icon: "figure.walk", color: .green, text: dist)
                    }
                }

                DetailSection("Access") {
                    MetaRow(
                        icon: bathroom.accessType.icon,
                        color: bathroom.accessType.color,
                        text: bathroom.accessType.displayName
                    )
                    if bathroom.requiresReceiptCode {
                        MetaRow(icon: "doc.text", color: .blue,
                                text: "Code printed on receipt")
                    }
                    MetaRow(
                        icon: bathroom.isOpen24Hours ? "clock.fill" : "clock",
                        color: bathroom.isOpen24Hours ? .blue : Color(.systemGray3),
                        text: bathroom.isOpen24Hours ? "Open 24 hours" : "Standard hours"
                    )
                    if bathroom.waitTime != .unknown {
                        MetaRow(
                            icon: bathroom.waitTime.icon,
                            color: bathroom.waitTime.color,
                            text: bathroom.waitTime.displayName
                        )
                    }
                }

                DetailSection("Facilities") {
                    MetaRow(
                        icon: bathroom.stallType.icon,
                        color: .purple,
                        text: bathroom.stallType.displayName
                    )
                    MetaRow(
                        icon: bathroom.genderType.icon,
                        color: .indigo,
                        text: bathroom.genderType.displayName
                    )
                    MetaRow(
                        icon: bathroom.isIndoor ? "building.2" : "tree",
                        color: bathroom.isIndoor ? .blue : .green,
                        text: bathroom.isIndoor ? "Indoor" : "Outdoor"
                    )
                    MetaRow(
                        icon: "figure.roll",
                        color: bathroom.isWheelchairAccessible ? .blue : Color(.systemGray3),
                        text: bathroom.isWheelchairAccessible
                            ? "Wheelchair accessible" : "Not wheelchair accessible"
                    )
                    MetaRow(
                        icon: "figure.and.child.holdinghands",
                        color: bathroom.hasChangingTable ? .green : Color(.systemGray3),
                        text: bathroom.hasChangingTable
                            ? "Changing table available" : "No changing table"
                    )
                }

                DetailSection("Toilet Paper") {
                    MetaRow(
                        icon: "roll",
                        color: bathroom.hasToiletPaper ? .brown : Color(.systemGray3),
                        text: bathroom.hasToiletPaper ? "Toilet paper available" : "No toilet paper"
                    )
                    if bathroom.hasToiletPaper {
                        MetaRow(
                            icon: bathroom.hasExtraToiletPaper ? "plus.circle.fill" : "plus.circle",
                            color: bathroom.hasExtraToiletPaper ? .brown : Color(.systemGray3),
                            text: bathroom.hasExtraToiletPaper
                                ? "Extra rolls stocked" : "Only one roll (bring backup)"
                        )
                    }
                    if bathroom.dispenserRating == 0 {
                        MetaRow(icon: "cylinder", color: Color(.systemGray3),
                                text: "No dedicated dispenser")
                    } else {
                        metaRowWithStars(
                            icon: "cylinder.fill",
                            color: .brown,
                            label: "Dispenser quality",
                            rating: bathroom.dispenserRating
                        )
                    }
                }

                DetailSection("Amenities") {
                    MetaRow(
                        icon: "thermometer.medium",
                        color: bathroom.hasHeatedSeat ? .orange : Color(.systemGray3),
                        text: bathroom.hasHeatedSeat ? "Heated seat" : "No heated seat"
                    )
                    if bathroom.bidetType != .none {
                        MetaRow(
                            icon: bathroom.bidetType.icon,
                            color: .cyan,
                            text: "Bidet: \(bathroom.bidetType.displayName)"
                        )
                    } else {
                        MetaRow(icon: "xmark.circle", color: Color(.systemGray3), text: "No bidet")
                    }
                    MetaRow(
                        icon: "hands.sparkles",
                        color: bathroom.hasSoap ? .teal : Color(.systemGray3),
                        text: bathroom.hasSoap ? "Soap available" : "No soap"
                    )
                    MetaRow(
                        icon: "wind",
                        color: bathroom.hasDryingOption ? .teal : Color(.systemGray3),
                        text: bathroom.hasDryingOption
                            ? "Hand drying available" : "No paper towels or dryer"
                    )
                }

                if !bathroom.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    DetailSection("Notes") {
                        Text(bathroom.notes)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider()
                actionsSection
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
            }
        }
        .fullScreenCover(isPresented: $showEditView) {
            AddBathroomView(userLocation: userLocation, editing: bathroom)
        }
        .alert("Delete Bathroom?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) { deleteBathroom() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\"\(bathroom.name)\" and all its photos will be permanently deleted.")
        }
        .alert("Couldn't Delete", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError?.errorDescription ?? "")
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(bathroom.name)
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                StarRatingView(rating: bathroom.rating, showUnratedLabel: true)
            }
            Spacer()
            Button { showEditView = true } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 36, height: 36)
                    .background(Color(.secondarySystemFill))
                    .clipShape(Circle())
            }
            .accessibilityLabel("Edit this bathroom")
        }
    }

    // MARK: - Metadata Row Helpers

    private func metaRowWithStars(icon: String, color: Color, label: String, rating: Int) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 20)
            Text(label)
                .font(.subheadline)
            StarRatingView(rating: rating, starSize: 12)
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: 12) {
            Button { openInMaps() } label: {
                Label("Open in Maps", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.blue)

            Button(role: .destructive) { showDeleteAlert = true } label: {
                Label("Delete", systemImage: "trash.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.red)
        }
    }

    // MARK: - Helpers

    private var formattedDistance: String? {
        Distance.formatted(from: userLocation, to: bathroom.coordinate)
    }

    private func openInMaps() {
        MapURLHelper.openDirections(toLatitude: bathroom.latitude, longitude: bathroom.longitude)
    }

    private func deleteBathroom() {
        do {
            try BathroomSaver.delete(bathroom, from: modelContext)
            dismiss()
        } catch {
            deleteError = error as? BathroomSaver.SaveError ?? .deleteFailed
        }
    }
}

// MARK: - Preview

#Preview {
    let bathroom = Bathroom(
        name: "Starbucks on Main",
        latitude: 37.7749, longitude: -122.4194,
        address: "123 Main St, San Francisco, CA 94105",
        rating: 4,
        accessType: .purchaseRequired,
        requiresReceiptCode: true,
        stallType: .single,
        genderType: .allGender,
        hasExtraToiletPaper: true,
        dispenserRating: 4,
        hasHeatedSeat: false,
        bidetType: .electronic,
        hasChangingTable: true,
        waitTime: .usuallyEmpty,
        notes: "Second floor, past the register. Usually very clean during the day."
    )
    DetailView(
        bathroom: bathroom,
        userLocation: CLLocationCoordinate2D(latitude: 37.7751, longitude: -122.4180)
    )
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
}
