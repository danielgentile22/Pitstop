//
//  BathroomAnnotation.swift
//  Pitstop
//
//  Custom map pin displayed for each saved bathroom.
//  Size and glow animate on selection; color encodes quality at a glance.
//
//  Color key:
//    Green  → 4–5 stars (excellent)
//    Orange → 3 stars   (decent)
//    Red    → 1–2 stars (poor)
//    Gray   → unrated   (no data)
//

import SwiftUI

/// The visual pin placed on the map for a saved bathroom.
///
/// Embed this inside a MapKit `Annotation` content closure:
/// ```swift
/// Annotation(bathroom.name, coordinate: bathroom.coordinate) {
///     BathroomAnnotation(rating: bathroom.rating, isSelected: isThisOneSelected)
///         .onTapGesture { ... }
/// }
/// ```
struct BathroomAnnotation: View {

    // MARK: - Input

    /// Star rating 0–5 (0 = unrated).
    let rating: Int

    /// When true, the pin grows and its glow intensifies to indicate selection.
    let isSelected: Bool

    // MARK: - Layout Constants

    private let baseSize: CGFloat     = 36
    private let selectedSize: CGFloat = 44
    private let baseIconSize: CGFloat = 17

    // MARK: - Body

    var body: some View {
        let size     = isSelected ? selectedSize : baseSize
        let iconSize = isSelected ? baseIconSize + 3 : baseIconSize

        ZStack {
            // Colored background — rating-coded
            Circle()
                .fill(pinColor)
                .frame(width: size, height: size)
                .shadow(
                    color: pinColor.opacity(0.45),
                    radius: isSelected ? 12 : 5,
                    y: isSelected ? 4 : 2
                )

            // Toilet icon (SF Symbols)
            Image(systemName: "toilet.fill")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.white)
        }
        // Spring-driven size and glow animate smoothly on selection change
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isSelected)
        // VoiceOver
        .accessibilityLabel(voiceOverLabel)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Helpers

    /// Pin color derived from the star rating.
    private var pinColor: Color {
        switch rating {
        case 4...5: return .green
        case 3:     return .orange
        case 1...2: return .red
        default:    return Color(.systemGray)   // 0 = unrated
        }
    }

    /// Full description read aloud by VoiceOver.
    private var voiceOverLabel: String {
        let ratingText = rating > 0 ? "\(rating) out of 5 stars" : "unrated"
        return "Bathroom pin, \(ratingText)"
    }
}

// MARK: - Preview

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
