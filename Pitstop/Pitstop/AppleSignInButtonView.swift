import AuthenticationServices
import SwiftUI
import UIKit

struct AppleSignInButtonView: UIViewRepresentable {

    let style: ASAuthorizationAppleIDButton.Style
    var onSuccess: (ASAuthorizationAppleIDCredential, String) -> Void
    var onFailure: (Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSuccess: onSuccess, onFailure: onFailure)
    }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(
            authorizationButtonType:  .signIn,
            authorizationButtonStyle: style
        )
        button.cornerRadius = 12
        button.addTarget(
            context.coordinator,
            action: #selector(Coordinator.handleTap),
            for: .touchUpInside
        )
        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.onSuccess = onSuccess
        context.coordinator.onFailure = onFailure
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject,
                             ASAuthorizationControllerDelegate,
                             ASAuthorizationControllerPresentationContextProviding {

        var onSuccess: (ASAuthorizationAppleIDCredential, String) -> Void
        var onFailure: (Error) -> Void

        // Held from handleTap() until the delegate callback; the backend needs the unhashed value.
        private var rawNonce: String?

        init(
            onSuccess: @escaping (ASAuthorizationAppleIDCredential, String) -> Void,
            onFailure: @escaping (Error) -> Void
        ) {
            self.onSuccess = onSuccess
            self.onFailure = onFailure
        }

        // MARK: Button tap

        @objc func handleTap() {
            let raw = NonceCrypto.generateRawNonce()
            rawNonce = raw

            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce           = NonceCrypto.sha256(raw)

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate                = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }

        // MARK: ASAuthorizationControllerDelegate

        func authorizationController(
            controller: ASAuthorizationController,
            didCompleteWithAuthorization authorization: ASAuthorization
        ) {
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let nonce      = rawNonce
            else { return }
            onSuccess(credential, nonce)
        }

        func authorizationController(
            controller: ASAuthorizationController,
            didCompleteWithError error: Error
        ) {
            let appleError = error as? ASAuthorizationError
            guard appleError?.code != .canceled else { return }
            onFailure(error)
        }

        // MARK: ASAuthorizationControllerPresentationContextProviding

        func presentationAnchor(
            for controller: ASAuthorizationController
        ) -> ASPresentationAnchor {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let keyWindow = scenes
                .first(where: { $0.activationState == .foregroundActive })?
                .windows
                .first(where: \.isKeyWindow) {
                return keyWindow
            }
            guard let scene = scenes.first else {
                preconditionFailure("Sign in with Apple presented with no connected window scene")
            }
            return UIWindow(windowScene: scene)
        }
    }
}
