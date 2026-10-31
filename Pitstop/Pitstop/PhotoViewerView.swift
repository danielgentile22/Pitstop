import SwiftUI

/// Full-screen, swipeable photo viewer. Paging and swipe-down dismiss are disabled while a photo is zoomed.
struct PhotoViewerView: View {

    // MARK: - Input

    let bathroom: Bathroom

    @Binding var selectedIndex: Int

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    /// Live dismiss drag. The axis is locked on the first change so a horizontal page swipe never moves the viewer.
    private struct DismissDrag {
        var isVertical: Bool?
        var offset: CGFloat = 0
    }

    @GestureState(resetTransaction: Transaction(animation: .spring(response: 0.3, dampingFraction: 0.7)))
    private var dismissDrag = DismissDrag()

    /// Whether the current drag locked to vertical, read on release (the gesture state has reset by then).
    @State private var dismissAllowed = false

    @State private var isZoomed = false

    @State private var isPinching = false

    // MARK: - Derived

    private var backgroundOpacity: Double {
        Double(max(0, 1 - abs(dismissDrag.offset) / 250))
    }

    // MARK: - Body

    var body: some View {
        let fileNames = bathroom.imageFileNames

        ZStack(alignment: .topTrailing) {

            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()

            // A paging ScrollView rather than a page-style TabView: `scrollDisabled` reliably stops paging here,
            // which a zoomed photo needs so its pan is not taken as a page swipe.
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(fileNames.enumerated()), id: \.offset) { index, fileName in
                        ZoomablePhotoPage(
                            bathroomID: bathroom.id,
                            fileName:   fileName,
                            pageLabel:  "Photo \(index + 1) of \(fileNames.count)",
                            isZoomed:   $isZoomed,
                            isPinching: $isPinching
                        )
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: pagePosition)
            .scrollDisabled(isZoomed)
            .ignoresSafeArea()
            .offset(y: dismissDrag.offset)
            .simultaneousGesture(dismissGesture)
            .opacity(backgroundOpacity)
            .onChange(of: selectedIndex) { isZoomed = false }
            .overlay(alignment: .bottom) { pageDots(count: fileNames.count) }

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

    private var pagePosition: Binding<Int?> {
        Binding(get: { selectedIndex }, set: { if let index = $0 { selectedIndex = index } })
    }

    @ViewBuilder
    private func pageDots(count: Int) -> some View {
        if count > 1 {
            HStack(spacing: 8) {
                ForEach(0..<count, id: \.self) { index in
                    Circle()
                        .fill(.white.opacity(index == selectedIndex ? 1 : 0.35))
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.bottom, 24)
            .opacity(backgroundOpacity)
            .accessibilityHidden(true)
        }
    }

    // MARK: - Dismiss Gesture

    /// Simultaneous so it never takes a swipe from paging. Only a clearly vertical drag counts, and a pinch at any
    /// point cancels it for the rest of the drag.
    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .updating($dismissDrag) { value, state, _ in
                guard !isZoomed, !isPinching else {
                    state.isVertical = false
                    state.offset = 0
                    return
                }
                let t = value.translation
                if state.isVertical == nil {
                    state.isVertical = abs(t.height) > abs(t.width) * 2
                }
                state.offset = state.isVertical == true ? t.height : 0
            }
            .onChanged { _ in
                dismissAllowed = dismissDrag.isVertical == true
            }
            .onEnded { value in
                defer { dismissAllowed = false }
                guard dismissAllowed, !isZoomed, !isPinching else { return }
                if abs(value.translation.height) > 100 {
                    dismiss()
                }
            }
    }
}

// MARK: - ZoomablePhotoPage

/// One page of the viewer: loads the full-size image and supports pinch-to-zoom and panning while zoomed.
private struct ZoomablePhotoPage: View {

    let bathroomID: UUID
    let fileName:   String
    let pageLabel:  String

    @Binding var isZoomed:   Bool
    @Binding var isPinching: Bool

    @State private var image:     UIImage?
    @State private var zoomScale: CGFloat = 1.0
    @State private var offset:    CGSize  = .zero
    @GestureState private var magnifyBy:   CGFloat = 1.0
    @GestureState private var pinchActive: Bool    = false
    @GestureState private var panBy:       CGSize  = .zero

    private static let maxZoom: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let image {
                    zoomableImage(image, in: proxy.size)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pageLabel)
        .accessibilityAddTraits(.isImage)
        .task(id: fileName) {
            image = await ImageStorage.loadImageAsync(bathroomID: bathroomID, fileName: fileName)
        }
        .onChange(of: pinchActive) { _, active in isPinching = active }
        .onDisappear {
            resetZoom()
            isPinching = false
        }
    }

    private func zoomableImage(_ image: UIImage, in container: CGSize) -> some View {
        let scale = zoomScale * magnifyBy
        let liveOffset = clamped(
            CGSize(width: offset.width + panBy.width, height: offset.height + panBy.height),
            scale: scale, imageSize: image.size, container: container
        )

        return Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .offset(liveOffset)
            .gesture(
                MagnifyGesture()
                    .updating($magnifyBy) { value, state, _ in state = value.magnification }
                    .updating($pinchActive) { _, state, _ in state = true }
                    .onEnded { value in
                        zoomScale = min(Self.maxZoom, max(1.0, zoomScale * value.magnification))
                        if zoomScale > 1.01 {
                            offset   = clamped(offset, scale: zoomScale, imageSize: image.size, container: container)
                            isZoomed = true
                        } else {
                            resetZoom()
                        }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .updating($panBy) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        offset = clamped(
                            CGSize(width:  offset.width  + value.translation.width,
                                   height: offset.height + value.translation.height),
                            scale: zoomScale, imageSize: image.size, container: container
                        )
                    },
                including: isZoomed ? .all : .subviews
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    resetZoom()
                }
            }
    }

    private func resetZoom() {
        zoomScale = 1.0
        offset    = .zero
        isZoomed  = false
    }

    /// Keeps the scaled, aspect-fit image covering the container: each edge can move at most until it meets the
    /// container edge, and an axis that fits entirely stays centered.
    private func clamped(_ proposed: CGSize, scale: CGFloat, imageSize: CGSize, container: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let fit  = min(container.width / imageSize.width, container.height / imageSize.height)
        let maxX = max(0, (imageSize.width  * fit * scale - container.width)  / 2)
        let maxY = max(0, (imageSize.height * fit * scale - container.height) / 2)
        return CGSize(
            width:  min(max(proposed.width,  -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }
}
