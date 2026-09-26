//
//  ProfileView.swift
//  Pitstop
//
//  Shows the current user's profile: display name (editable), email,
//  bathroom count, and a sign-out button.
//  Presented as a sheet from the ContentView toolbar.
//
//  ── Sheet Purpose ─────────────────────────────────────────────────────────
//
//  ProfileView is a secondary, non-destructive settings surface. It is
//  intentionally a sheet (not a full-screen cover or pushed view) because:
//    • The user can quickly peek at their stats and dismiss back to the map.
//    • Sheet presentation signals "temporary / lightweight" to the user vs.
//      a full-screen modal which implies a multi-step task.
//    • @Environment(\.dismiss) lets the Done button and post-sign-out code
//      both close the sheet with a single call, regardless of how it was
//      presented.
//
//  ── Display Name Editing Flow ─────────────────────────────────────────────
//
//  The name field uses an in-place edit pattern rather than a separate edit
//  screen:
//    1. The user taps the "Edit" button next to their name.
//    2. isEditingName flips to true, which swaps the static Text for a
//       TextField pre-filled with the current display name.
//    3. Tapping "Save" (same button, label changed) or pressing the keyboard
//       Return key calls saveName(), which:
//         a. Flips isEditingName back to false immediately (optimistic UI —
//            the spinner replaces the Save button while the write is pending).
//         b. Calls SupabaseService.updateDisplayName(), which writes to
//            Supabase and updates the local userProfile observable.
//         c. On failure, sets errorMsg so the red error section appears.
//    4. Because SupabaseService.userProfile is @Observable, the name Text
//       and avatar letter update automatically once the write completes.
//
//  ── Sign-Out Confirmation ─────────────────────────────────────────────────
//
//  Sign-out is a destructive action (the user must re-authenticate to see
//  their bathrooms again) so it is guarded by a confirmation alert.
//  The alert uses the .destructive role on the "Sign Out" button to render
//  it in red on iOS, giving a clear visual warning.
//  After a successful sign-out, dismiss() closes the sheet before
//  PitstopApp has a chance to swap the root view — this prevents a brief
//  flash of an empty ContentView before LoginView mounts.
//

import SwiftData
import SwiftUI

struct ProfileView: View {

    // MARK: - Environment

    @Environment(SupabaseService.self) private var service
    @Environment(SyncQueue.self)       private var syncQueue
    @Environment(\.dismiss)            private var dismiss
    @Environment(\.modelContext)       private var modelContext

    /// Live count of bathrooms owned by the current user, queried directly
    /// from SwiftData. More accurate than the profile's cached bathroomCount
    /// field because it reflects local adds/deletes immediately.
    @Query private var allBathrooms: [Bathroom]

    private var myBathroomCount: Int {
        guard let userID = service.currentUserIDString else { return 0 }
        return allBathrooms.filter { $0.ownerID == userID }.count
    }

    // MARK: - State

    /// Holds the in-progress display name while isEditingName is true.
    /// Initialised from service.userProfile?.displayName when the user taps Edit,
    /// so the field always starts with the current saved value.
    @State private var displayName   = ""

    /// When true, the name Text is replaced with an editable TextField.
    @State private var isEditingName = false

    /// True while updateDisplayName() is in-flight. Disables the Save button
    /// to prevent double-submission and provides implicit loading feedback.
    @State private var isSaving      = false

    /// Non-empty when a save attempt threw an error.
    /// Shown in a red Section below the stats area.
    @State private var errorMsg      = ""

    /// Controls the sign-out confirmation alert.
    @State private var showSignOutConfirm = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {

                // ── Avatar + name ─────────────────────────────────────────
                // The avatar is a gradient circle with an initial letter rather
                // than a real profile photo — this avoids photo library
                // permissions and storage complexity for an MVP. The gradient
                // colours match the app icon for visual consistency.
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
                            // Conditional swap: TextField (editing) vs. Text (display).
                            // .onSubmit fires when the keyboard Return key is pressed,
                            // giving a keyboard-driven path to save without reaching
                            // up to tap the button.
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
                                // Fall back to "Unnamed Explorer" if the user has never
                                // set a display name, so the row is never blank.
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

                        // Edit / Save toggle button.
                        // When tapping Edit: pre-fill displayName from the current
                        // saved value before flipping isEditingName, so the
                        // TextField doesn't start empty.
                        // When tapping Save: delegate to saveName() which handles
                        // the async write and state transitions.
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

                // ── Stats ─────────────────────────────────────────────────
                // bathroomCount is maintained by SupabaseService after each
                // sync — it reflects the total number of bathrooms the
                // current user has added to the cloud database, not just
                // what is cached locally.
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

                // ── Error ─────────────────────────────────────────────────
                // Conditionally shown — the Section is absent when there is
                // no error, keeping the list compact in the happy path.
                if !errorMsg.isEmpty {
                    Section {
                        Text(errorMsg)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                // ── Sign Out ──────────────────────────────────────────────
                // Tapping Sign Out only raises the confirmation alert —
                // the actual sign-out happens inside the alert's destructive
                // button action. This two-step approach prevents accidental
                // sign-outs from a mis-tap.
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
                // Done button closes the sheet without any changes.
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Sign Out?", isPresented: $showSignOutConfirm) {
                // Destructive role renders the button in red on iOS, giving
                // a strong visual signal that this cannot be undone easily.
                Button("Sign Out", role: .destructive) {
                    Task {
                        // try? intentionally silences errors — if signOut()
                        // fails (e.g., no network) the local session token is
                        // still cleared by the Supabase SDK, so the user is
                        // effectively signed out locally regardless.
                        try? await service.signOut(clearingContext: modelContext, syncQueue: syncQueue)
                        // Dismiss the sheet before PitstopApp reacts to the
                        // currentUser becoming nil, preventing a brief flash
                        // of an empty ContentView behind the sheet.
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

    /// The single uppercase letter displayed in the avatar circle.
    ///
    /// Priority order:
    ///   1. First character of the display name (preferred — more personal).
    ///   2. First character of the email address (fallback before a name is set).
    ///   3. "?" if neither is available (should not occur in practice once
    ///      auth succeeds, but guards against optional-chain edge cases).
    private var avatarLetter: String {
        let name = service.userProfile?.displayName ?? ""
        if let first = name.first { return String(first).uppercased() }
        if let email = service.currentUserEmail, let first = email.first {
            return String(first).uppercased()
        }
        return "?"
    }

    // MARK: - Save Name

    /// Persists the edited display name to Supabase.
    ///
    /// Sets isEditingName = false immediately (optimistic) so the TextField
    /// collapses before the network call completes, giving snappy feedback.
    /// If the write fails, errorMsg is set and the user can try again by
    /// tapping Edit once more.
    private func saveName() async {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            isSaving      = true
            isEditingName = false
        }
        errorMsg = ""
        defer { isSaving = false }

        do {
            // Trim whitespace so a name of "  Daniel  " is stored as "Daniel".
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
