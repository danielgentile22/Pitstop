//
//  EmailConfirmationView.swift
//  GeoPoop
//
//  Shown when a user signs up with email/password and Supabase requires them
//  to verify their email address before their session becomes active.
//
//  GeoPoopApp mounts this view when `supabaseService.pendingConfirmationEmail`
//  is non-nil. Once the user has clicked the confirmation link in their email,
//  they tap "Sign In" here, which clears the pending state and returns them to
//  the standard login form where they can enter their credentials.
//
//  Why not auto-detect confirmation?
//    After clicking the confirmation link, Supabase redirects the user to a
//    URL that ideally deep-links back into the app. Handling that redirect
//    requires registered URL schemes and SceneDelegate work that is outside
//    the scope of the current auth implementation. In the meantime, the user
//    clicks "Done" here and signs in normally — clean and reliable.
//

import SwiftUI

struct EmailConfirmationView: View {

    // MARK: - Input

    let email: String

    // MARK: - Environment

    @Environment(SupabaseService.self) private var service

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // ── Illustration ─────────────────────────────────────────────
            VStack(spacing: 16) {
                Image(systemName: "envelope.badge.checkmark")
                    .font(.system(size: 72))
                    .foregroundStyle(.blue)

                Text("Check your inbox")
                    .font(.title2.bold())

                VStack(spacing: 6) {
                    Text("We sent a confirmation link to")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(email)
                        .font(.subheadline.weight(.semibold))

                    Text("Tap the link in the email, then come back and sign in.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            }

            Spacer().frame(height: 48)

            // ── Actions ──────────────────────────────────────────────────
            VStack(spacing: 14) {
                // Primary action: dismiss and return to login form
                Button("Done — Take me to Sign In") {
                    service.pendingConfirmationEmail = nil
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .padding(.horizontal, 24)

                // Secondary: try a different email
                Button("Use a different email") {
                    service.pendingConfirmationEmail = nil
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text("Didn't get the email? Check your spam folder.")
                .font(.caption2)
                .foregroundStyle(Color(.systemGray4))
                .multilineTextAlignment(.center)
                .padding(.bottom, 16)
        }
    }
}

// MARK: - Preview

#Preview {
    EmailConfirmationView(email: "daniel@example.com")
        .environment(SupabaseService())
}
