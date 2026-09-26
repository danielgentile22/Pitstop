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
    @Environment(SupabaseService.self) private var supabaseService
    @Environment(SyncQueue.self)       private var syncQueue

    // MARK: - State

    @State private var showDeleteAlert = false
    @State private var showEditView    = false
    @State private var showReportView  = false
    @State private var isVerifying     = false
    @State private var verifyError     = ""

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

                detailSection("Location") {
                    if let address = bathroom.address, !address.isEmpty {
                        metaRow(icon: "location.fill", color: .red, text: address)
                    }
                    metaRow(
                        icon: "calendar",
                        color: .blue,
                        text: bathroom.dateVisited.formatted(date: .long, time: .omitted)
                    )
                    if let dist = formattedDistance {
                        metaRow(icon: "figure.walk", color: .green, text: dist)
                    }
                }

                detailSection("Access") {
                    metaRow(
                        icon: bathroom.accessType.icon,
                        color: bathroom.accessType.color,
                        text: bathroom.accessType.displayName
                    )
                    if bathroom.requiresReceiptCode {
                        metaRow(icon: "doc.text", color: .blue,
                                text: "Code printed on receipt")
                    }
                    metaRow(
                        icon: bathroom.isOpen24Hours ? "clock.fill" : "clock",
                        color: bathroom.isOpen24Hours ? .blue : Color(.systemGray3),
                        text: bathroom.isOpen24Hours ? "Open 24 hours" : "Standard hours"
                    )
                    if bathroom.waitTime != .unknown {
                        metaRow(
                            icon: bathroom.waitTime.icon,
                            color: bathroom.waitTime.color,
                            text: bathroom.waitTime.displayName
                        )
                    }
                }

                detailSection("Facilities") {
                    metaRow(
                        icon: bathroom.stallType.icon,
                        color: .purple,
                        text: bathroom.stallType.displayName
                    )
                    metaRow(
                        icon: bathroom.genderType.icon,
                        color: .indigo,
                        text: bathroom.genderType.displayName
                    )
                    metaRow(
                        icon: bathroom.isIndoor ? "building.2" : "tree",
                        color: bathroom.isIndoor ? .blue : .green,
                        text: bathroom.isIndoor ? "Indoor" : "Outdoor"
                    )
                    metaRow(
                        icon: "figure.roll",
                        color: bathroom.isWheelchairAccessible ? .blue : Color(.systemGray3),
                        text: bathroom.isWheelchairAccessible
                            ? "Wheelchair accessible" : "Not wheelchair accessible"
                    )
                    metaRow(
                        icon: "figure.and.child.holdinghands",
                        color: bathroom.hasChangingTable ? .green : Color(.systemGray3),
                        text: bathroom.hasChangingTable
                            ? "Changing table available" : "No changing table"
                    )
                }

                detailSection("Toilet Paper") {
                    metaRow(
                        icon: "roll",
                        color: bathroom.hasToiletPaper ? .brown : Color(.systemGray3),
                        text: bathroom.hasToiletPaper ? "Toilet paper available" : "No toilet paper"
                    )
                    if bathroom.hasToiletPaper {
                        metaRow(
                            icon: bathroom.hasExtraToiletPaper ? "plus.circle.fill" : "plus.circle",
                            color: bathroom.hasExtraToiletPaper ? .brown : Color(.systemGray3),
                            text: bathroom.hasExtraToiletPaper
                                ? "Extra rolls stocked" : "Only one roll (bring backup)"
                        )
                    }
                    if bathroom.dispenserRating == 0 {
                        metaRow(icon: "cylinder", color: Color(.systemGray3),
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

                detailSection("Amenities") {
                    metaRow(
                        icon: "thermometer.medium",
                        color: bathroom.hasHeatedSeat ? .orange : Color(.systemGray3),
                        text: bathroom.hasHeatedSeat ? "Heated seat" : "No heated seat"
                    )
                    if bathroom.bidetType != .none {
                        metaRow(
                            icon: bathroom.bidetType.icon,
                            color: .cyan,
                            text: "Bidet: \(bathroom.bidetType.displayName)"
                        )
                    } else {
                        metaRow(icon: "xmark.circle", color: Color(.systemGray3), text: "No bidet")
                    }
                    metaRow(
                        icon: "hands.sparkles",
                        color: bathroom.hasSoap ? .teal : Color(.systemGray3),
                        text: bathroom.hasSoap ? "Soap available" : "No soap"
                    )
                    metaRow(
                        icon: "wind",
                        color: bathroom.hasDryingOption ? .teal : Color(.systemGray3),
                        text: bathroom.hasDryingOption
                            ? "Hand drying available" : "No paper towels or dryer"
                    )
                }

                if !bathroom.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    detailSection("Notes") {
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
        .sheet(isPresented: $showReportView) {
            ReportView(bathroom: bathroom)
        }
        .alert("Delete Bathroom?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) { deleteBathroom() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\"\(bathroom.name)\" and all its photos will be permanently deleted.")
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(bathroom.name)
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    StarRatingView(rating: bathroom.rating, showUnratedLabel: true)
                    if bathroom.isPrivate {
                        Label("Private", systemImage: "lock.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.red.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                verificationBadge
            }
            Spacer()
            if supabaseService.isOwner(of: bathroom) {
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
    }

    private var verificationBadge: some View {
        Group {
            if bathroom.verificationCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("\(bathroom.verificationCount) verification\(bathroom.verificationCount == 1 ? "" : "s")")
                    if let lastVerified = bathroom.lastVerifiedAt {
                        Text("·")
                        Text(lastVerified, format: .relative(presentation: .named))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "questionmark.circle")
                    Text("Not yet verified")
                }
                .font(.caption)
                .foregroundStyle(Color(.systemGray3))
            }
        }
    }

    // MARK: - Section Container

    private func detailSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                Text(title.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.8)
                content()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Metadata Row Helpers

    private func metaRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

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

            Button {
                Task { await verifyBathroom() }
            } label: {
                Group {
                    if isVerifying {
                        ProgressView().tint(.green)
                    } else {
                        Label("Still Here? Verify", systemImage: "checkmark.seal")
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
                .animation(.easeInOut(duration: 0.2), value: isVerifying)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.green)
            .disabled(isVerifying)

            if !verifyError.isEmpty {
                Text(verifyError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            if !supabaseService.isOwner(of: bathroom) {
                Button { showReportView = true } label: {
                    Label("Report an Issue", systemImage: "flag")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.orange)
            }

            if supabaseService.isOwner(of: bathroom) {
                Button(role: .destructive) { showDeleteAlert = true } label: {
                    Label("Delete", systemImage: "trash.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.red)
            }
        }
    }

    // MARK: - Helpers

    private var formattedDistance: String? {
        guard let userLocation else { return nil }
        let origin = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
        let formatter = MKDistanceFormatter()
        formatter.unitStyle = .abbreviated
        return formatter.string(fromDistance: bathroom.distance(from: origin))
    }

    private func openInMaps() {
        MapURLHelper.openDirections(toLatitude: bathroom.latitude, longitude: bathroom.longitude)
    }

    private func deleteBathroom() {
        let bid       = bathroom.id
        let fileNames = bathroom.imageFileNames
        ImageStorage.deleteAllImages(bathroomID: bid)
        modelContext.delete(bathroom)
        dismiss()
        syncQueue.enqueue(.deleteBathroom(bathroomID: bid, fileNames: fileNames))
        Task { await syncQueue.drain(supabase: supabaseService, context: modelContext) }
    }

    private func verifyBathroom() async {
        withAnimation(.easeInOut(duration: 0.2)) { isVerifying = true }
        verifyError = ""
        defer { withAnimation(.easeInOut(duration: 0.2)) { isVerifying = false } }
        do {
            try await supabaseService.verifyBathroom(bathroom)
        } catch {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                verifyError = "Couldn't submit verification. Please try again."
            }
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
    .environment(SupabaseService())
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
}
