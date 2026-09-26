//
//  StarRatingView.swift
//  Pitstop
//
//  Read-only star rating display. Used in DetailView, list rows,
//  and anywhere a rating needs to be shown (not edited).
//
//  The interactive input version (for Add/Edit/Filter) is StarRatingInput.swift,
//  built in Phase 3.
//

import SwiftUI

/// Displays a 1–5 star rating as a row of filled/empty SF Symbol stars.
///
/// Parameters:
/// - `rating`: 0–5. Zero renders all empty stars with an "Unrated" label.
/// - `starSize`: Point size of each star icon (default 16pt).
/// - `showUnratedLabel`: When true and rating == 0, appends a gray "Unrated" text.
struct StarRatingView: View {

    let rating: Int
    var starSize: CGFloat = 16
    var showUnratedLabel: Bool = false

    private let maxStars = 5

    var body: some View {
        HStack(spacing: 4) {
            // Star icons
            HStack(spacing: 3) {
                ForEach(1...maxStars, id: \.self) { position in
                    Image(systemName: position <= rating ? "star.fill" : "star")
                        .font(.system(size: starSize))
                        .foregroundStyle(position <= rating ? Color.yellow : Color(.systemGray3))
                }
            }

            // Optional "Unrated" label when no rating has been given
            if showUnratedLabel && rating == 0 {
                Text("Unrated")
                    .font(.system(size: starSize - 2))
                    .foregroundStyle(.secondary)
            }
        }
        // Expose a single semantic element to VoiceOver
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating")
        .accessibilityValue(rating > 0 ? "\(rating) out of 5 stars" : "Unrated")
    }
}

// MARK: - Preview

#Preview("All states") {
    VStack(alignment: .leading, spacing: 12) {
        StarRatingView(rating: 5)
        StarRatingView(rating: 4)
        StarRatingView(rating: 3)
        StarRatingView(rating: 2)
        StarRatingView(rating: 1)
        StarRatingView(rating: 0, showUnratedLabel: true)
        Divider()
        // Larger size variant
        StarRatingView(rating: 4, starSize: 22)
    }
    .padding()
}
