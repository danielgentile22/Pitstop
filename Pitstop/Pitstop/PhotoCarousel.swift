//
//  PhotoCarousel.swift
//  Pitstop
//
//  Horizontally scrolling photo strip shown in DetailView.
//  Tapping a thumbnail opens PhotoViewerView at full size.
//  Renders nothing (EmptyView) when there are no photos.
//
//  ThumbnailCell uses PhotoResolver so community bathroom photos are
//  downloaded from Supabase Storage on first access and cached locally
//  for all subsequent views.
//

import SwiftUI

struct PhotoCarousel: View {

    let bathroom: Bathroom

    // MARK: - State

    @State private var viewerIndex: Int? = nil

    // MARK: - Layout Constants

    private let thumbSize: CGFloat         = 80
    private let cornerRadius: CGFloat      = 10
    private let horizontalPadding: CGFloat = 20

    // MARK: - Body

    var body: some View {
        if bathroom.imageFileNames.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(bathroom.imageFileNames.enumerated()), id: \.offset) { index, fileName in
                        thumbnail(index: index, fileName: fileName)
                            .onTapGesture { viewerIndex = index }
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 4)
            }
            .fullScreenCover(isPresented: Binding(
                get: { viewerIndex != nil },
                set: { if !$0 { viewerIndex = nil } }
            )) {
                if let index = viewerIndex {
                    PhotoViewerView(
                        bathroom: bathroom,
                        selectedIndex: Binding(
                            get: { viewerIndex ?? index },
                            set: { viewerIndex = $0 }
                        )
                    )
                }
            }
        }
    }

    // MARK: - Thumbnail

    private func thumbnail(index: Int, fileName: String) -> some View {
        ThumbnailCell(
            bathroomID:  bathroom.id,
            fileName:    fileName,
            size:        thumbSize,
            radius:      cornerRadius,
            label:       "Photo \(index + 1) of \(bathroom.imageFileNames.count)"
        )
    }
}

// MARK: - ThumbnailCell

/// A single thumbnail in the carousel.
/// Loads the image via PhotoResolver — local cache first, then Supabase Storage.
private struct ThumbnailCell: View {

    let bathroomID: UUID
    let fileName:   String
    let size:       CGFloat
    let radius:     CGFloat
    let label:      String

    @Environment(SupabaseService.self) private var supabaseService
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            // Placeholder always rendered underneath
            Rectangle()
                .fill(Color(.systemGray5))
                .overlay(
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(Color(.systemGray3))
                        .opacity(image == nil ? 1 : 0)
                )

            // Loaded image fades in on top
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .animation(.easeInOut(duration: 0.28), value: image != nil)
        .accessibilityLabel(label)
        .accessibilityAddTraits([.isImage, .isButton])
        .task(id: fileName) {
            image = await PhotoResolver.thumbnail(
                bathroomID: bathroomID,
                fileName: fileName,
                supabase: supabaseService
            )
        }
    }
}
