import SwiftUI

/// Read-only star rating. For the editable control see `StarRatingInput`.
struct StarRatingView: View {

    let rating: Int   // 0-5, 0 = unrated
    var starSize: CGFloat = 16
    var showUnratedLabel: Bool = false

    private let maxStars = 5

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 3) {
                ForEach(1...maxStars, id: \.self) { position in
                    Image(systemName: position <= rating ? "star.fill" : "star")
                        .font(.system(size: starSize))
                        .foregroundStyle(position <= rating ? Color.yellow : Color(.systemGray3))
                }
            }

            if showUnratedLabel && rating == 0 {
                Text("Unrated")
                    .font(.system(size: starSize - 2))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating")
        .accessibilityValue(rating > 0 ? "\(rating) out of 5 stars" : "Unrated")
    }
}

#Preview("All states") {
    VStack(alignment: .leading, spacing: 12) {
        StarRatingView(rating: 5)
        StarRatingView(rating: 4)
        StarRatingView(rating: 3)
        StarRatingView(rating: 2)
        StarRatingView(rating: 1)
        StarRatingView(rating: 0, showUnratedLabel: true)
        Divider()
        StarRatingView(rating: 4, starSize: 22)
    }
    .padding()
}
