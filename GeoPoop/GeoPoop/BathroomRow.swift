//
//  BathroomRow.swift
//  GeoPoop
//
//  A single row in the bathroom list.
//  Shows a photo thumbnail (or icon placeholder), name, access type,
//  star rating, distance, and key amenity indicators.
//
//  Photo loading uses PhotoResolver, which tries the local cache/disk first
//  and falls back to downloading from Supabase Storage for community bathrooms.
//

import CoreLocation
import MapKit
import SwiftUI

struct BathroomRow: View {

    // MARK: - Input

    let bathroom: Bathroom
    let userLocation: CLLocationCoordinate2D?

    // MARK: - Environment

    @Environment(SupabaseService.self) private var supabaseService

    // MARK: - Constants

    private let thumbSize: CGFloat   = 72
    private let thumbRadius: CGFloat = 10

    // MARK: - Async Image State

    @State private var thumbnailImage: UIImage?

    // MARK: - Body

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail
            details
            Spacer()
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .task(id: bathroom.id) {
            guard let fileName = bathroom.imageFileNames.first else {
                thumbnailImage = nil; return
            }
            thumbnailImage = await PhotoResolver.thumbnail(
                bathroomID: bathroom.id,
                fileName: fileName,
                supabase: supabaseService
            )
        }
    }

    // MARK: - Thumbnail

    private var thumbnail: some View {
        ZStack {
            // Placeholder always rendered underneath
            Color(.secondarySystemFill)
                .overlay(
                    Image(systemName: "toilet.fill")
                        .font(.title2)
                        .foregroundStyle(Color(.systemGray3))
                        .opacity(thumbnailImage == nil ? 1 : 0)
                )

            // Loaded image fades in on top
            if let image = thumbnailImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .frame(width: thumbSize, height: thumbSize)
        .clipShape(RoundedRectangle(cornerRadius: thumbRadius, style: .continuous))
        .animation(.easeInOut(duration: 0.28), value: thumbnailImage != nil)
    }

    // MARK: - Details

    private var details: some View {
        VStack(alignment: .leading, spacing: 5) {

            // Name
            Text(bathroom.name)
                .font(.headline)
                .lineLimit(1)

            // Access badge + rating + distance
            HStack(spacing: 6) {
                Label(bathroom.accessType.shortName, systemImage: bathroom.accessType.icon)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(bathroom.accessType.color)
                    .lineLimit(1)

                if bathroom.rating > 0 {
                    Text("·").font(.caption).foregroundStyle(Color(.systemGray3))
                    StarRatingView(rating: bathroom.rating, starSize: 11)
                }

                if let dist = formattedDistance {
                    Text("·").font(.caption).foregroundStyle(Color(.systemGray3))
                    Text(dist).font(.caption).foregroundStyle(.secondary)
                }
            }

            amenityIcons
        }
    }

    // MARK: - Amenity Icons

    private var amenityIcons: some View {
        HStack(spacing: 10) {
            if bathroom.isOpen24Hours {
                amenityIcon("clock.fill", color: .blue, label: "24 hours")
            }
            if bathroom.stallType == .single {
                amenityIcon("person.fill", color: .purple, label: "Single stall")
            }
            if bathroom.isWheelchairAccessible {
                amenityIcon("figure.roll", color: .blue, label: "Accessible")
            }
            if bathroom.hasChangingTable {
                amenityIcon("figure.and.child.holdinghands", color: .green, label: "Changing table")
            }
            if bathroom.bidetType != .none {
                amenityIcon("drop.fill", color: .cyan, label: "Bidet")
            }
            if bathroom.hasHeatedSeat {
                amenityIcon("thermometer.medium", color: .orange, label: "Heated seat")
            }
            if !bathroom.hasSoap {
                amenityIcon("hands.sparkles", color: .secondary, label: "No soap")
                    .opacity(0.5)
            }
            if !bathroom.hasToiletPaper {
                amenityIcon("roll", color: .secondary, label: "No TP")
                    .opacity(0.5)
            }
        }
    }

    private func amenityIcon(_ symbol: String, color: Color, label: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(color)
            .accessibilityLabel(label)
    }

    // MARK: - Distance

    private var formattedDistance: String? {
        guard let userLocation else { return nil }
        let origin = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
        let formatter = MKDistanceFormatter()
        formatter.unitStyle = .abbreviated
        return formatter.string(fromDistance: bathroom.distance(from: origin))
    }
}

// MARK: - Preview

#Preview {
    let rich = Bathroom(
        name: "Whole Foods Market",
        latitude: 37.7749, longitude: -122.4194,
        address: "399 4th St, SF",
        rating: 4,
        accessType: .purchaseRequired,
        isOpen24Hours: false,
        stallType: .single,
        isWheelchairAccessible: true,
        hasExtraToiletPaper: true,
        dispenserRating: 3,
        bidetType: .electronic,
        hasChangingTable: true,
        waitTime: .usuallyEmpty
    )
    let simple = Bathroom(
        name: "Dolores Park",
        latitude: 37.7596, longitude: -122.4269,
        rating: 2,
        accessType: .free,
        stallType: .multi,
        isIndoor: false,
        hasToiletPaper: false,
        hasSoap: false
    )
    List {
        BathroomRow(bathroom: rich,   userLocation: CLLocationCoordinate2D(latitude: 37.7751, longitude: -122.4180))
        BathroomRow(bathroom: simple, userLocation: nil)
    }
    .listStyle(.plain)
    .environment(SupabaseService())
}
