//
//  MiniMapPicker.swift
//  Pitstop
//
//  A compact map used in AddBathroomView for pin placement.
//  Uses the "center crosshair" pattern: the pin is fixed at the map center,
//  and the user pans the map to position it (matching how Apple Maps "Drop Pin" works).
//
//  The selected coordinate updates continuously as the user pans so that a
//  debounced reverse-geocode in the parent view stays responsive.
//

import MapKit
import SwiftUI

/// A small interactive map where a fixed center pin indicates the selected location.
///
/// The user pans the map to place the pin. The `selectedCoordinate` binding
/// is updated continuously to reflect the current map center.
///
/// - Important: Disable all map controls here — this is a picker, not a full map.
struct MiniMapPicker: View {

    // MARK: - Binding

    /// The coordinate the user has positioned the pin over. Updated on every camera change.
    @Binding var selectedCoordinate: CLLocationCoordinate2D

    // MARK: - State

    /// Internal camera position initialized to the starting coordinate.
    @State private var position: MapCameraPosition

    // MARK: - Init

    init(selectedCoordinate: Binding<CLLocationCoordinate2D>) {
        _selectedCoordinate = selectedCoordinate
        // Start zoomed in to neighborhood level (~400m radius)
        _position = State(initialValue: .region(
            MKCoordinateRegion(
                center: selectedCoordinate.wrappedValue,
                latitudinalMeters: 400,
                longitudinalMeters: 400
            )
        ))
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .center) {

            // ── Map ────────────────────────────────────────────────────────────
            Map(position: $position)
                // Update the coordinate binding as the user pans
                .onMapCameraChange(frequency: .continuous) { context in
                    selectedCoordinate = context.camera.centerCoordinate
                }
                .mapStyle(.standard)
                // No controls — this is a compact picker, not a navigation map
                .mapControls { }

            // ── Ground Shadow ──────────────────────────────────────────────────
            // Subtle ellipse slightly below center to simulate pin elevation
            Ellipse()
                .fill(.black.opacity(0.18))
                .frame(width: 22, height: 9)
                .blur(radius: 2)
                .offset(y: 26)   // just below the bottom of the 40pt pin circle

            // ── Center Pin ─────────────────────────────────────────────────────
            // Fixed at ZStack center — toilet icon on a blue circle
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 40, height: 40)
                    .shadow(color: .blue.opacity(0.45), radius: 8, y: 3)

                Image(systemName: "toilet.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)   // The map itself conveys position

            // ── Hint Label ─────────────────────────────────────────────────────
            // "Drag to position" label at the bottom of the map
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
