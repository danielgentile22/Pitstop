import SwiftUI

/// Floating button that triggers the nearest-bathroom flow in ContentView.
struct EmergencyButton: View {

    var onTap: () -> Void

    @State private var isPulsing = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let buttonSize: CGFloat = 56
    private let iconSize: CGFloat   = 24

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: iconSize, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: buttonSize, height: buttonSize)
                .background(
                    Circle()
                        .fill(Color.red)
                        .shadow(color: .red.opacity(0.4), radius: isPulsing ? 12 : 6, y: 4)
                )
                .clipShape(Circle())
        }
        .accessibilityLabel("Emergency: find nearest bathroom")
        .onAppear {
            guard !reduceMotion else { return }
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
                EmergencyButton {}
                    .padding(20)
            }
        }
    }
}
