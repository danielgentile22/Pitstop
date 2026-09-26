import SwiftUI

/// Filter sheet for the bathroom list. Edits apply live; there is no Apply button.
struct FilterSheetView: View {

    @Binding var filter: BathroomFilter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    sectionHeader("Minimum Rating")
                    ratingPicker
                        .padding(.horizontal, 20).padding(.bottom, 24)

                    divider

                    sectionHeader("Max Distance")
                    Text("Requires location access. Only shows bathrooms within the selected radius.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                    distanceChips
                        .padding(.horizontal, 20).padding(.bottom, 24)

                    divider

                    sectionHeader("Access Type")
                    Text("Show bathrooms with any of the selected access types.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                    accessChips
                        .padding(.horizontal, 20).padding(.bottom, 24)

                    divider

                    sectionHeader("Stall Type")
                    stallChips
                        .padding(.horizontal, 20).padding(.bottom, 24)

                    divider

                    sectionHeader("Gender")
                    genderChips
                        .padding(.horizontal, 20).padding(.bottom, 24)

                    divider

                    sectionHeader("Wait Time")
                    Text("Show bathrooms with any of the selected typical wait times.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                    waitTimeChips
                        .padding(.horizontal, 20).padding(.bottom, 24)

                    divider

                    sectionHeader("Must Have")
                    mustHaveToggles
                        .padding(.horizontal, 20).padding(.bottom, 36)
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear All") {
                        withAnimation(.easeInOut(duration: 0.2)) { filter.reset() }
                    }
                    .disabled(!filter.isActive)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 12)
    }

    private var divider: some View {
        Divider().padding(.horizontal, 20)
    }

    // MARK: - Rating Picker

    private var ratingPicker: some View {
        HStack(spacing: 10) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                        filter.minimumRating = (filter.minimumRating == star) ? 0 : star
                    }
                } label: {
                    Image(systemName: star <= filter.minimumRating ? "star.fill" : "star")
                        .font(.system(size: 30))
                        .foregroundStyle(star <= filter.minimumRating ? .yellow : Color(.systemGray3))
                        .scaleEffect(star <= filter.minimumRating ? 1.05 : 1.0)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(star) star minimum")
            }
            Spacer()
            Text(filter.minimumRating == 0 ? "Any" : "\(filter.minimumRating)★ & up")
                .font(.subheadline).foregroundStyle(.secondary)
                .animation(.easeInOut(duration: 0.15), value: filter.minimumRating)
        }
    }

    // MARK: - Distance Chips

    private var distanceChips: some View {
        FlowLayout(spacing: 8) {
            ForEach(MaxDistance.allCases, id: \.rawValue) { dist in
                let on = filter.maxDistance == dist
                filterChip(label: dist.displayName, icon: "location.circle", color: .blue, isOn: on) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        filter.maxDistance = on ? nil : dist
                    }
                }
            }
        }
    }

    // MARK: - Access Chips

    private var accessChips: some View {
        FlowLayout(spacing: 8) {
            ForEach(BathroomAccess.allCases) { access in
                let on = filter.accessTypes.contains(access)
                filterChip(
                    label: access.shortName,
                    icon: access.icon,
                    color: access.color,
                    isOn: on
                ) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        if on { filter.accessTypes.remove(access) }
                        else  { filter.accessTypes.insert(access) }
                    }
                }
            }
        }
    }

    // MARK: - Stall Chips

    private var stallChips: some View {
        FlowLayout(spacing: 8) {
            ForEach(StallType.allCases, id: \.rawValue) { stall in
                let on = filter.stallTypes.contains(stall)
                filterChip(label: stall.displayName, icon: stall.icon, color: .purple, isOn: on) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        if on { filter.stallTypes.remove(stall) }
                        else  { filter.stallTypes.insert(stall) }
                    }
                }
            }
        }
    }

    // MARK: - Gender Chips

    private var genderChips: some View {
        FlowLayout(spacing: 8) {
            ForEach(GenderType.allCases, id: \.rawValue) { gender in
                let on = filter.genderTypes.contains(gender)
                filterChip(label: gender.displayName, icon: gender.icon, color: .indigo, isOn: on) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        if on { filter.genderTypes.remove(gender) }
                        else  { filter.genderTypes.insert(gender) }
                    }
                }
            }
        }
    }

    // MARK: - Wait Time Chips

    private var waitTimeChips: some View {
        FlowLayout(spacing: 8) {
            ForEach(WaitTime.allCases, id: \.rawValue) { wait in
                let on = filter.waitTimes.contains(wait)
                filterChip(label: wait.displayName, icon: wait.icon, color: wait.color, isOn: on) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        if on { filter.waitTimes.remove(wait) }
                        else  { filter.waitTimes.insert(wait) }
                    }
                }
            }
        }
    }

    // MARK: - Must-Have Toggles

    private var mustHaveToggles: some View {
        VStack(spacing: 0) {
            mustHaveRow("Open 24 Hours",        icon: "clock",                         color: .blue,   isOn: $filter.requiresOpen24Hours)
            mustHaveRow("Indoor",               icon: "building.2",                    color: .blue,   isOn: $filter.requiresIndoor)
            mustHaveRow("Wheelchair Accessible",icon: "figure.roll",                   color: .blue,   isOn: $filter.requiresWheelchairAccessible)
            mustHaveRow("Changing Table",       icon: "figure.and.child.holdinghands", color: .green,  isOn: $filter.requiresChangingTable)
            mustHaveRow("Toilet Paper",         icon: "roll",                          color: .brown,  isOn: $filter.requiresToiletPaper)
            mustHaveRow("Heated Seat",          icon: "thermometer.medium",            color: .orange, isOn: $filter.requiresHeatedSeat)
            mustHaveRow("Bidet",                icon: "drop",                          color: .cyan,   isOn: $filter.requiresBidet)
            mustHaveRow("Soap",                 icon: "hands.sparkles",                color: .teal,   isOn: $filter.requiresSoap)
            mustHaveRow("Hand Drying",          icon: "wind",                          color: .teal,   isOn: $filter.requiresDryingOption)
        }
    }

    private func mustHaveRow(
        _ label: String,
        icon: String,
        color: Color,
        isOn: Binding<Bool>
    ) -> some View {
        VStack(spacing: 0) {
            Toggle(isOn: isOn.animation(.easeInOut(duration: 0.2))) {
                Label {
                    Text(label).font(.subheadline)
                } icon: {
                    Image(systemName: icon).foregroundStyle(color)
                }
            }
            .tint(.blue)
            .padding(.vertical, 10)
            Divider()
        }
    }

    // MARK: - Reusable Filter Chip

    private func filterChip(
        label: String,
        icon: String,
        color: Color,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: isOn ? "checkmark" : icon)
                    .font(.caption.weight(.semibold))
                Text(label)
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(isOn ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(isOn ? color : Color(.secondarySystemFill))
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isOn)
    }
}

// MARK: - Preview

#Preview {
    FilterSheetView(filter: .constant(BathroomFilter()))
}
