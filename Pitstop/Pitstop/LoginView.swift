import AuthenticationServices
import SwiftUI

struct LoginView: View {

    // MARK: - Modes

    private enum Mode { case signIn, createAccount, forgotPassword }

    // MARK: - Environment

    @Environment(SupabaseService.self) private var service
    @Environment(\.colorScheme)        private var colorScheme

    // MARK: - State

    @State private var mode: Mode = .signIn
    @State private var email        = ""
    @State private var password     = ""
    @State private var isLoading    = false
    @State private var errorMsg     = ""
    @State private var resetSent    = false
    @State private var appeared     = false

    @FocusState private var focused: Field?
    private enum Field { case email, password }

    // MARK: - Derived

    private var isSignUp: Bool { mode == .createAccount }
    private var isForgot: Bool { mode == .forgotPassword }

    // MARK: - Body

    var body: some View {
        // Scrollable so small phones never clip the Apple button; minHeight lets Spacers fill tall screens.
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer(minLength: 24)

                    VStack(spacing: 10) {
                        Image(systemName: "toilet.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.white)
                            .frame(width: 96, height: 96)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 0.18, green: 0.44, blue: 0.92),
                                             Color(red: 0.09, green: 0.26, blue: 0.72)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                            .scaleEffect(appeared ? 1 : 0.55)
                            .opacity(appeared ? 1 : 0)

                        Text("Pitstop")
                            .font(.largeTitle.bold())
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 10)

                        Text("Find and share the world's best bathrooms")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 10)
                    }
                    .onAppear {
                        withAnimation(.spring(response: 0.65, dampingFraction: 0.72)) {
                            appeared = true
                        }
                    }

                    Spacer(minLength: 32).frame(maxHeight: 40)

                    Group {
                        if isForgot {
                            forgotPasswordForm
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
                                    removal:   .opacity
                                ))
                        } else {
                            mainForm
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
                                    removal:   .opacity
                                ))
                        }
                    }
                    .animation(.spring(response: 0.42, dampingFraction: 0.85), value: isForgot)

                    Spacer(minLength: 16)

                    Text("By signing in you agree to use Pitstop\nfor its intended purpose.")
                        .font(.caption2)
                        .foregroundStyle(Color(.systemGray4))
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 16)
                }
                .frame(minHeight: geo.size.height)
            }
        }
    }

    // MARK: - Main Form (Sign In / Create Account)

    private var mainForm: some View {
        VStack(spacing: 14) {

            Picker("Mode", selection: $mode) {
                Text("Sign In").tag(Mode.signIn)
                Text("Create Account").tag(Mode.createAccount)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .onChange(of: mode) { errorMsg = "" }

            VStack(spacing: 10) {
                emailField

                HStack {
                    Image(systemName: "lock").foregroundStyle(.secondary).frame(width: 20)
                    SecureField("Password", text: $password)
                        .focused($focused, equals: .password)
                        .submitLabel(.done)
                        .onSubmit { Task { await submit() } }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 24)

            if !errorMsg.isEmpty {
                Text(errorMsg)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            Button {
                Task { await submit() }
            } label: {
                Group {
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text(isSignUp ? "Create Account" : "Sign In")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .animation(.easeInOut(duration: 0.18), value: isLoading)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isLoading || email.isEmpty || password.isEmpty)
            .padding(.horizontal, 24)

            if !isSignUp {
                Button("Forgot Password?") {
                    mode      = .forgotPassword
                    errorMsg  = ""
                    resetSent = false
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            orDivider.padding(.horizontal, 24)

            AppleSignInButtonView(
                style: colorScheme == .dark ? .white : .black,
                onSuccess: { credential, rawNonce in
                    guard
                        let tokenData = credential.identityToken,
                        let idToken   = String(data: tokenData, encoding: .utf8)
                    else {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
                            errorMsg = "Sign in with Apple failed. Please try again."
                        }
                        return
                    }
                    Task {
                        isLoading = true
                        defer { isLoading = false }
                        do {
                            try await service.signInWithApple(
                                idToken:     idToken,
                                rawNonce:    rawNonce,
                                appleUserID: credential.user,
                                fullName:    credential.fullName
                            )
                        } catch {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
                                errorMsg = error.localizedDescription
                            }
                        }
                    }
                },
                onFailure: { error in
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
                        errorMsg = error.localizedDescription
                    }
                }
            )
            .frame(height: 50)
            .disabled(isLoading)
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Forgot Password Form

    private var forgotPasswordForm: some View {
        VStack(spacing: 14) {

            VStack(spacing: 6) {
                Text("Reset Password")
                    .font(.headline)
                Text("Enter your email and we'll send you a reset link.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            emailField.padding(.horizontal, 24)

            if !errorMsg.isEmpty {
                Text(errorMsg)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            if resetSent {
                Label("Reset link sent! Check your inbox.", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 32)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            Button {
                Task { await sendReset() }
            } label: {
                Group {
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Send Reset Link")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .animation(.easeInOut(duration: 0.18), value: isLoading)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isLoading || email.isEmpty || resetSent)
            .padding(.horizontal, 24)

            Button("Back to Sign In") {
                mode      = .signIn
                errorMsg  = ""
                resetSent = false
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - "or" Divider

    private var orDivider: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 0.5)
            Text("or")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 0.5)
        }
    }

    // MARK: - Shared Email Field

    private var emailField: some View {
        HStack {
            Image(systemName: "envelope").foregroundStyle(.secondary).frame(width: 20)
            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focused, equals: .email)
                .submitLabel(isForgot ? .done : .next)
                .onSubmit {
                    if isForgot { Task { await sendReset() } }
                    else        { focused = .password }
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Submit (Sign In / Sign Up)

    private func submit() async {
        errorMsg  = ""
        isLoading = true
        focused   = nil
        defer { isLoading = false }

        do {
            let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
            if isSignUp {
                try await service.signUp(email: trimmedEmail, password: password)
            } else {
                try await service.signIn(email: trimmedEmail, password: password)
            }
            // On success the auth gate in PitstopApp swaps the root view.
        } catch {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
                errorMsg = error.localizedDescription
            }
        }
    }

    // MARK: - Send Password Reset

    private func sendReset() async {
        guard !email.isEmpty else { return }
        errorMsg  = ""
        isLoading = true
        focused   = nil
        defer { isLoading = false }

        do {
            try await service.resetPassword(email: email.trimmingCharacters(in: .whitespaces))
            withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
                resetSent = true
            }
        } catch {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
                errorMsg = error.localizedDescription
            }
        }
    }
}

// MARK: - Preview

#Preview {
    LoginView()
        .environment(SupabaseService())
}
