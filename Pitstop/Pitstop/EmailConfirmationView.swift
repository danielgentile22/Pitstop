import SwiftUI

/// Shown after email sign-up. The confirmation link does not deep-link back into the app,
/// so the user confirms in the browser, then signs in here.
struct EmailConfirmationView: View {

    let email: String

    @Environment(SupabaseService.self) private var service

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

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

            VStack(spacing: 14) {
                Button("Back to Sign In") {
                    service.pendingConfirmationEmail = nil
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .padding(.horizontal, 24)

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
