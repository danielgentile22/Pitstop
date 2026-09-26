import SwiftData
import SwiftUI

struct ProfileView: View {

    // MARK: - Environment

    @Environment(SupabaseService.self) private var service
    @Environment(SyncQueue.self)       private var syncQueue
    @Environment(\.dismiss)            private var dismiss
    @Environment(\.modelContext)       private var modelContext

    /// Counted locally so adds and deletes show up before the next sync.
    @Query private var allBathrooms: [Bathroom]

    private var myBathroomCount: Int {
        guard let userID = service.currentUserIDString else { return 0 }
        return allBathrooms.filter { $0.ownerID == userID }.count
    }

    // MARK: - State

    @State private var displayName   = ""

    @State private var isEditingName = false

    @State private var isSaving      = false

    @State private var errorMsg      = ""

    @State private var showSignOutConfirm = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {

                Section {
                    HStack(spacing: 16) {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color(red: 0.18, green: 0.44, blue: 0.92),
                                         Color(red: 0.09, green: 0.26, blue: 0.72)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .frame(width: 60, height: 60)
                            .overlay(
                                Text(avatarLetter)
                                    .font(.title.bold())
                                    .foregroundStyle(.white)
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            if isEditingName {
                                TextField("Display name", text: $displayName)
                                    .font(.headline)
                                    .textFieldStyle(.roundedBorder)
                                    .submitLabel(.done)
                                    .onSubmit { Task { await saveName() } }
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .leading)),
                                        removal:   .opacity
                                    ))
                            } else {
                                Text(service.userProfile?.displayName.isEmpty == false
                                     ? service.userProfile!.displayName
                                     : "Unnamed Explorer")
                                    .font(.headline)
                                    .transition(.asymmetric(
                                        insertion: .opacity,
                                        removal:   .opacity.combined(with: .scale(scale: 0.95, anchor: .leading))
                                    ))
                            }
                            Text(service.currentUserEmail ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isEditingName)

                        Spacer()

                        Button(isEditingName ? "Save" : "Edit") {
                            if isEditingName {
                                Task { await saveName() }
                            } else {
                                displayName = service.userProfile?.displayName ?? ""
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                    isEditingName = true
                                }
                            }
                        }
                        .font(.subheadline)
                        .disabled(isSaving)
                    }
                    .padding(.vertical, 8)
                }

                Section("Stats") {
                    Label {
                        HStack {
                            Text("Bathrooms saved")
                            Spacer()
                            Text("\(myBathroomCount)")
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "toilet.fill").foregroundStyle(.blue)
                    }
                }

                if !errorMsg.isEmpty {
                    Section {
                        Text(errorMsg)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showSignOutConfirm = true
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Sign Out?", isPresented: $showSignOutConfirm) {
                Button("Sign Out", role: .destructive) {
                    Task {
                        try? await service.signOut(clearingContext: modelContext, syncQueue: syncQueue)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You will need to sign in again to access your bathrooms.")
            }
        }
    }

    // MARK: - Computed

    /// First letter of the display name, else of the email.
    private var avatarLetter: String {
        let name = service.userProfile?.displayName ?? ""
        if let first = name.first { return String(first).uppercased() }
        if let email = service.currentUserEmail, let first = email.first {
            return String(first).uppercased()
        }
        return "?"
    }

    // MARK: - Save Name

    /// Collapses the text field immediately; a failed save shows in the error section.
    private func saveName() async {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            isSaving      = true
            isEditingName = false
        }
        errorMsg = ""
        defer { isSaving = false }

        do {
            try await service.updateDisplayName(displayName.trimmingCharacters(in: .whitespaces))
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}

// MARK: - Preview

#Preview {
    ProfileView()
        .modelContainer(for: Bathroom.self, inMemory: true)
        .environment(SupabaseService())
        .environment(SyncQueue())
}
