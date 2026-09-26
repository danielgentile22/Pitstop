import MapKit
import SwiftUI

/// Compact location picker: the pin stays fixed at the center and the user pans the map under it.
/// `selectedCoordinate` tracks the map center continuously.
struct MiniMapPicker: View {

    @Binding var selectedCoordinate: CLLocationCoordinate2D

    @State private var position: MapCameraPosition

    init(selectedCoordinate: Binding<CLLocationCoordinate2D>) {
        _selectedCoordinate = selectedCoordinate
        _position = State(initialValue: .region(
            MKCoordinateRegion(
                center: selectedCoordinate.wrappedValue,
                latitudinalMeters: 400,
                longitudinalMeters: 400
            )
        ))
    }

    var body: some View {
        ZStack(alignment: .center) {

            Map(position: $position)
                .onMapCameraChange(frequency: .continuous) { context in
                    selectedCoordinate = context.camera.centerCoordinate
                }
                .mapStyle(.standard)
                .mapControls { }

            Ellipse()
                .fill(.black.opacity(0.18))
                .frame(width: 22, height: 9)
                .blur(radius: 2)
                .offset(y: 26)   // just below the 40pt pin circle

            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 40, height: 40)
                    .shadow(color: .blue.opacity(0.45), radius: 8, y: 3)

                Image(systemName: "toilet.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)

            VStack {
                Spacer()
                Text("Drag map to position pin")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.45))
                    .clipShape(Capsule())
                    .padding(.bottom, 12)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var coord = CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855)
        var body: some View {
            VStack {
                MiniMapPicker(selectedCoordinate: $coord)
                    .frame(height: 220)
                Text("Lat: \(coord.latitude, specifier: "%.5f")")
                Text("Lon: \(coord.longitude, specifier: "%.5f")")
            }
            .padding(.horizontal)
        }
    }
    return PreviewWrapper()
}
