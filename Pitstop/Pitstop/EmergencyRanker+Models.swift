import Foundation

// Ranker inputs built from stored places, so the ranker itself stays free of SwiftData.

extension EmergencyRanker.VisitedPlace {
    init(_ bathroom: Bathroom) {
        self.init(id: bathroom.id, sourceID: bathroom.sourceID, latitude: bathroom.latitude,
                  longitude: bathroom.longitude, rating: bathroom.rating, isOpen24Hours: bathroom.isOpen24HoursIfKnown)
    }
}

extension EmergencyRanker.UnvisitedPlace {
    init(_ candidate: Candidate) {
        self.init(sourceID: candidate.sourceID, latitude: candidate.latitude, longitude: candidate.longitude,
                  reliability: candidate.brand.reliability, isOpen24Hours: candidate.isOpen24HoursIfKnown,
                  isDismissed: candidate.isDismissed)
    }
}
