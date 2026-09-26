import SwiftUI

/// Tappable 1-5 star input. Tapping the current rating clears it back to 0 (unrated).
struct StarRatingInput: View {

    @Binding var rating: Int
    var starSize: CGFloat = 32

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let maxStars = 5

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...maxStars, id: \.self) { star in
                Button {
                    let newRating = (star == rating) ? 0 : star
                    withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.55)) {
                        rating = newRating
                    }
                } label: {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .font(.system(size: starSize))
                        .foregroundStyle(star <= rating ? Color.yellow : Color(.systemGray3))
                        .scaleEffect(star == rating ? 1.15 : 1.0)
                        .animation(
                            reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.5),
                            value: rating
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(star) \(star == 1 ? "star" : "stars")")
                .accessibilityAddTraits(star <= rating ? .isSelected : [])
            }
        }
        // VoiceOver sees one adjustable slider instead of five buttons.
        .accessibilityRepresentation {
            Slider(value: Binding(
                get: { Double(rating) },
                set: { rating = Int($0) }
            ), in: 0...5, step: 1)
            .accessibilityLabel("Rating")
            .accessibilityValue(rating > 0 ? "\(rating) out of 5 stars" : "Unrated")
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var rating = 3
        var body: some View {
            VStack(spacing: 24) {
                StarRatingInput(rating: $rating)
                StarRatingInput(rating: $rating, starSize: 24)
                Text(rating > 0 ? "\(rating) stars selected" : "Unrated")
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
    return PreviewWrapper()
}
