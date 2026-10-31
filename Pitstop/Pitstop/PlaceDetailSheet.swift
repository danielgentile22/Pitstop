import CoreLocation
import SwiftData
import SwiftUI

/// The detail sheet for a tapped place, shared by the Map and List tabs. It looks the place up by its
/// stable key, so a place deleted while the sheet is open (by the background seed import) closes the sheet
/// instead of leaving it reading a deleted model.
struct PlaceDetailSheet: View {

    let place: PlaceKey
    let userLocation: CLLocationCoordinate2D?

    var body: some View {
        Group {
            switch place {
            case .bathroom(let id):
                BathroomDetailLookup(id: id, userLocation: userLocation)
            case .candidate(let sourceID):
                CandidateDetailLookup(sourceID: sourceID, userLocation: userLocation)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct BathroomDetailLookup: View {

    @Query private var matches: [Bathroom]
    @Environment(\.dismiss) private var dismiss
    let userLocation: CLLocationCoordinate2D?

    init(id: UUID, userLocation: CLLocationCoordinate2D?) {
        _matches = Query(filter: #Predicate<Bathroom> { $0.id == id })
        self.userLocation = userLocation
    }

    var body: some View {
        if let bathroom = matches.first, !bathroom.isDeleted {
            DetailView(bathroom: bathroom, userLocation: userLocation)
        } else {
            Color.clear.onAppear { dismiss() }
        }
    }
}

private struct CandidateDetailLookup: View {

    @Query private var matches: [Candidate]
    @Environment(\.dismiss) private var dismiss
    let userLocation: CLLocationCoordinate2D?

    init(sourceID: String, userLocation: CLLocationCoordinate2D?) {
        _matches = Query(filter: #Predicate<Candidate> { $0.sourceID == sourceID })
        self.userLocation = userLocation
    }

    var body: some View {
        if let candidate = matches.first, !candidate.isDeleted {
            CandidateDetailView(candidate: candidate, userLocation: userLocation)
        } else {
            Color.clear.onAppear { dismiss() }
        }
    }
}
