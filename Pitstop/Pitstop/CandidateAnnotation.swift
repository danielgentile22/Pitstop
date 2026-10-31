import SwiftUI

/// Map pin for an unvisited place: dimmed, tinted by brand reliability, with a question mark badge,
/// so it never reads as a bathroom the user has checked. A dismissed place is gray with a red X badge.
struct CandidateAnnotation: View {

    let reliability: Reliability
    let isSelected: Bool
    var isDismissed: Bool = false

    private let baseSize: CGFloat     = 30
    private let selectedSize: CGFloat = 40
    private let badgeSize: CGFloat    = 15

    var body: some View {
        let size = isSelected ? selectedSize : baseSize
        let tint = isDismissed ? Color(.systemGray) : reliability.tint
        let badgeTint = isDismissed ? Color.red : tint

        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(tint.opacity(isSelected ? 0.75 : 0.45))
                .overlay(Circle().strokeBorder(tint, lineWidth: 1.5))
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "toilet")
                        .font(.system(size: size * 0.45, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                }

            Image(systemName: isDismissed ? "xmark" : "questionmark")
                .font(.system(size: badgeSize * 0.6, weight: .heavy))
                .foregroundStyle(badgeTint)
                .frame(width: badgeSize, height: badgeSize)
                .background(Circle().fill(.white))
                .overlay(Circle().strokeBorder(badgeTint, lineWidth: 1))
                .offset(x: badgeSize * 0.3, y: -badgeSize * 0.3)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isSelected)
    }
}

extension Reliability {
    var tint: Color {
        switch self {
        case .reliable:  return .teal
        case .likely:    return .indigo
        case .uncertain: return Color(.systemGray)
        }
    }

    var icon: String {
        switch self {
        case .reliable:  return "checkmark.seal"
        case .likely:    return "hand.thumbsup"
        case .uncertain: return "questionmark.diamond"
        }
    }
}

#Preview("Reliability levels") {
    HStack(spacing: 24) {
        ForEach(Reliability.allCases, id: \.self) { level in
            VStack(spacing: 16) {
                CandidateAnnotation(reliability: level, isSelected: false)
                CandidateAnnotation(reliability: level, isSelected: true)
                CandidateAnnotation(reliability: level, isSelected: false, isDismissed: true)
                BathroomAnnotation(rating: 4, isSelected: false)
            }
        }
    }
    .padding(24)
    .background(Color(.systemGroupedBackground))
}
