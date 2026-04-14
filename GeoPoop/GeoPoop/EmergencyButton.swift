//
//  EmergencyButton.swift
//  GeoPoop
//
//  The red "panic button" FAB (Floating Action Button) that appears at the
//  bottom-right corner of every screen. Tapping it finds the nearest saved
//  bathroom and opens Apple Maps with walking directions to it.
//
//  Why a FAB?
//    The emergency use-case ("I need a bathroom RIGHT NOW") is time-critical.
//    A persistent floating button means one tap from any screen, with no
//    navigation required.
//
//  Animation:
//    The button gently pulses (shadow radius oscillates) while visible to
//    draw attention without being obnoxious. The pulse is suppressed when
//    the user has Reduce Motion enabled in Accessibility settings.
//
//  Loading state:
//    When isLoading is true (cloud emergency query in flight), the icon
//    is replaced with a ProgressView so the user knows the tap registered.
//    The button is disabled during loading to prevent duplicate requests.
//
//  The actual logic for finding the nearest bathroom and opening Maps lives
//  in ContentView.handleEmergencyTap(), keeping this view purely presentational.
//

import SwiftUI

/// Red pulsing FAB that invokes the emergency nearest-bathroom flow.
///
/// Place this inside a `ZStack` overlay at the bottom-trailing corner:
/// ```swift
/// VStack { Spacer()
///     HStack { Spacer()
///         EmergencyButton(onTap: handleEmergencyTap)
///             .padding(20)
///     }
/// }
/// ```
struct EmergencyButton: View {

    // MARK: - Dependencies

    /// Called when the button is tapped. Implemented in ContentView.
    var onTap: () -> Void

    /// When true, replaces the icon with a spinner (cloud query in flight).
    var isLoading: Bool = false

    // MARK: - State

    /// Drives the pulsing shadow animation. Toggled by the repeat animation.
    @State private var isPulsing = false

    /// Respects the system Reduce Motion accessibility setting.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Layout Constants

    private let buttonSize: CGFloat = 56   // Diameter of the circle
    private let iconSize: CGFloat   = 24   // SF Symbol point size

    // MARK: - Body

    var body: some View {
        Button(action: onTap) {
            Group {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.1)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: iconSize, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: buttonSize, height: buttonSize)
            .background(
                Circle()
                    .fill(Color.red)
                    // Shadow radius oscillates between 6 and 12 to create the pulse
                    .shadow(color: .red.opacity(0.4), radius: isPulsing ? 12 : 6, y: 4)
            )
            .clipShape(Circle())
        }
        .disabled(isLoading)
        .accessibilityLabel("Emergency: find nearest bathroom")
        .onAppear {
            // Skip animation entirely if the user prefers reduced motion
            guard !reduceMotion else { return }
            // Infinite ease-in-out loop: shadow grows and shrinks smoothly
            withAnimation(
                .easeInOut(duration: 1.5)
                .repeatForever(autoreverses: true)
            ) {
                isPulsing = true
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.gray.opacity(0.2).ignoresSafeArea()
        VStack {
            Spacer()
            HStack {
                Spacer()
                EmergencyButton { print("Emergency tapped") }
                    .padding(20)
            }
        }
    }
}
