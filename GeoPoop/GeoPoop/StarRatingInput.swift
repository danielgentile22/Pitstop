//
//  StarRatingInput.swift
//  GeoPoop
//
//  Interactive 1–5 star rating input used in Add / Edit / Filter screens.
//  Each star is an independent Button — tapping a selected star deselects it
//  (sets rating back to 0, meaning unrated).
//
//  For the read-only display version, see StarRatingView.swift.
//

import SwiftUI

/// A row of five tappable stars that sets a 0–5 rating binding.
///
/// - Tapping an unselected star sets the rating to that value.
/// - Tapping the currently selected star resets the rating to 0 (unrated).
/// - Responds to Reduce Motion: disables the spring animation when enabled.
///
/// Usage:
/// ```swift
/// StarRatingInput(rating: $myRating)
/// ```
struct StarRatingInput: View {

    @Binding var rating: Int
    var starSize: CGFloat = 32

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let maxStars = 5

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...maxStars, id: \.self) { star in
                Button {
                    let newRating = (star == rating) ? 0 : star   // tap same star → deselect
                    withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.55)) {
                        rating = newRating
                    }
                } label: {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .font(.system(size: starSize))
                        .foregroundStyle(star <= rating ? Color.yellow : Color(.systemGray3))
                        // Subtle scale bounce on the tapped star
                        .scaleEffect(star == rating ? 1.15 : 1.0)
                        .animation(
                            reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.5),
                            value: rating
                        )
                }
                .buttonStyle(.plain)   // No system button chrome
                .accessibilityLabel("\(star) \(star == 1 ? "star" : "stars")")
                .accessibilityAddTraits(star <= rating ? .isSelected : [])
            }
        }
        // VoiceOver: treat the whole control as a single adjustable element
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

// MARK: - Preview

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
