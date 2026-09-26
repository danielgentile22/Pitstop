import SwiftUI

struct ReportView: View {

    // MARK: - Input

    let bathroom: Bathroom

    // MARK: - Environment

    @Environment(\.dismiss)            private var dismiss
    @Environment(SupabaseService.self) private var supabaseService

    // MARK: - State

    @State private var selectedReason: ReportReason = .incorrectInfo
    @State private var notes      = ""
    @State private var isSubmitting = false
    @State private var submitted    = false
    @State private var errorMsg     = ""

    // MARK: - Body

    var body: some View {
        NavigationStack {
            if submitted {
                successView
            } else {
                formView
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Form View

    private var formView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                VStack(alignment: .leading, spacing: 4) {
                    Text("Reporting".uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .tracking(0.6)
                    Text(bathroom.name)
                        .font(.title3.bold())
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Reason".uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .tracking(0.6)

                    ForEach(ReportReason.allCases) { reason in
                        reasonRow(reason)
                    }
                }
                .padding(.horizontal, 20)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Additional Notes (optional)".uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .tracking(0.6)

                    TextEditor(text: $notes)
                        .frame(minHeight: 80, maxHeight: 120)
                        .padding(8)
                        .background(Color(.secondarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .font(.body)
                }
                .padding(.horizontal, 20)

                if !errorMsg.isEmpty {
                    Text(errorMsg)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 20)
                }

                Button {
                    Task { await submit() }
                } label: {
                    Group {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Text("Submit Report")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.orange)
                .disabled(isSubmitting)
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Report Bathroom")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    // MARK: - Reason Row

    private func reasonRow(_ reason: ReportReason) -> some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                selectedReason = reason
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: reason.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(selectedReason == reason ? .white : .secondary)
                    .frame(width: 24)

                Text(reason.displayName)
                    .font(.subheadline)
                    .foregroundStyle(selectedReason == reason ? .white : .primary)

                Spacer()

                if selectedReason == reason {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selectedReason == reason ? Color.orange : Color(.secondarySystemFill))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .symbolEffect(.bounce)

            Text("Report Submitted")
                .font(.title2.bold())

            Text("Thank you for helping keep Pitstop accurate. We'll review this report shortly.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
    }

    // MARK: - Submit

    private func submit() async {
        isSubmitting = true
        errorMsg     = ""
        defer { isSubmitting = false }

        do {
            try await supabaseService.submitReport(
                bathroomID: bathroom.id,
                reason:     selectedReason,
                notes:      notes.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            withAnimation { submitted = true }
        } catch {
            errorMsg = "Failed to submit report. Please try again."
        }
    }
}

// MARK: - Preview

#Preview {
    ReportView(bathroom: Bathroom(
        name: "Starbucks on Main",
        latitude: 37.7749,
        longitude: -122.4194
    ))
    .environment(SupabaseService())
}
