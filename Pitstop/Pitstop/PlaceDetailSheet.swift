
import CoreLocation
import SwiftUI

/// The detail sheet for a tapped place, shared by the Map and List tabs.
struct PlaceDetailSheet: View {

    let place: MapSelection
    let userLocation: CLLocationCoordinate2D?

    var body: some View {
        Group {
            switch place {
            case .bathroom(let bathroom):
                DetailView(bathroom: bathroom, userLocation: userLocation)
            case .candidate(let candidate):
                CandidateDetailView(candidate: candidate, userLocation: userLocation)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
