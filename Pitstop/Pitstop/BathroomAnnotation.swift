import SwiftUI

/// Map pin for a saved bathroom, colored by rating and enlarged when selected.
struct BathroomAnnotation: View {

    let rating: Int   // 0 = unrated
    let isSelected: Bool

    private let baseSize: CGFloat     = 36
    private let selectedSize: CGFloat = 44
    private let baseIconSize: CGFloat = 17

    var body: some View {
        let size     = isSelected ? selectedSize : baseSize
        let iconSize = isSelected ? baseIconSize + 3 : baseIconSize

        ZStack {
            Circle()
                .fill(pinColor)
                .frame(width: size, height: size)
                .shadow(
                    color: pinColor.opacity(0.45),
                    radius: isSelected ? 12 : 5,
                    y: isSelected ? 4 : 2
                )

            Image(systemName: "toilet.fill")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.white)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isSelected)
        .accessibilityLabel(voiceOverLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var pinColor: Color {
        switch rating {
        case 4...5: return .green
        case 3:     return .orange
        case 1...2: return .red
        default:    return Color(.systemGray)
        }
    }

    private var voiceOverLabel: String {
        let ratingText = rating > 0 ? "\(rating) out of 5 stars" : "unrated"
        return "Bathroom pin, \(ratingText)"
    }
}

#Preview("All ratings") {
    VStack(spacing: 20) {
        HStack(spacing: 20) {
            BathroomAnnotation(rating: 5, isSelected: false)
            BathroomAnnotation(rating: 4, isSelected: false)
            BathroomAnnotation(rating: 3, isSelected: false)
            BathroomAnnotation(rating: 2, isSelected: false)
            BathroomAnnotation(rating: 1, isSelected: false)
            BathroomAnnotation(rating: 0, isSelected: false)
        }
        HStack(spacing: 20) {
            BathroomAnnotation(rating: 5, isSelected: true)
            BathroomAnnotation(rating: 3, isSelected: true)
            BathroomAnnotation(rating: 1, isSelected: true)
            BathroomAnnotation(rating: 0, isSelected: true)
        }
        Text("Bottom row: selected state")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .padding(24)
    .background(Color(.systemGroupedBackground))
}
