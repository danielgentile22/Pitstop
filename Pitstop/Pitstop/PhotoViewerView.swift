import SwiftUI

/// Full-screen, swipeable photo viewer. Swipe-down dismiss is disabled while a photo is zoomed.
struct PhotoViewerView: View {

    // MARK: - Input

    let bathroom: Bathroom

    @Binding var selectedIndex: Int

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var dragOffset: CGFloat = 0

    @State private var isZoomed = false

    // MARK: - Derived

    private var backgroundOpacity: Double {
        Double(max(0, 1 - abs(dragOffset) / 250))
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topTrailing) {

            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()

            TabView(selection: $selectedIndex) {
                ForEach(Array(bathroom.imageFileNames.enumerated()), id: \.offset) { index, fileName in
                    ZoomablePhotoPage(
                        bathroomID: bathroom.id,
                        fileName:   fileName,
                        isZoomed:   $isZoomed
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .ignoresSafeArea()
            .offset(y: dragOffset)
            .gesture(dismissDrag)
            .opacity(backgroundOpacity)
            .onChange(of: selectedIndex) { isZoomed = false }

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(.top, 56)
            .padding(.trailing, 20)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Dismiss Drag Gesture

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard !isZoomed else { return }
                guard abs(value.translation.height) > abs(value.translation.width) else { return }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                guard !isZoomed else {
                    dragOffset = 0; return
                }
                if abs(value.translation.height) > 100 {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        dragOffset = 0
                    }
                }
            }
    }
}

// MARK: - ZoomablePhotoPage

/// One page of the viewer: loads the full-size image (local first, then server) and supports pinch-to-zoom.
private struct ZoomablePhotoPage: View {

    let bathroomID: UUID
    let fileName:   String

    @Binding var isZoomed: Bool

    @Environment(SupabaseService.self) private var supabaseService
    @State private var image:     UIImage?
    @State private var zoomScale: CGFloat = 1.0
    @GestureState private var magnifyBy: CGFloat = 1.0

    private var currentZoom: CGFloat { zoomScale * magnifyBy }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(currentZoom)
                    .gesture(
                        MagnificationGesture()
                            .updating($magnifyBy) { value, state, _ in
                                state = value
                            }
                            .onEnded { value in
                                zoomScale = max(1.0, zoomScale * value)
                                isZoomed  = zoomScale > 1.01
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            zoomScale = 1.0
                            isZoomed  = false
                        }
                    }
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: fileName) {
            image = await PhotoResolver.fullSize(
                bathroomID: bathroomID,
                fileName: fileName,
                supabase: supabaseService
            )
        }
        .onDisappear {
            zoomScale = 1.0
            isZoomed  = false
        }
    }
}
