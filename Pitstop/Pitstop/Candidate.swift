import Foundation
import CoreLocation
import SwiftData

extension SchemaV1 {

    /// An unvisited chain location from the bundled seed. Visiting one makes a `Bathroom` with the same `sourceID`.
    @Model
    final class Candidate {

        /// Stable ID from the seed script, prefixed with its source, e.g. `atp:barnes_and_noble_us:2867`.
        @Attribute(.unique) var sourceID: String

        /// Key into `BrandProfile.table`.
        var brandKey: String

        var name:      String
        var latitude:  Double
        var longitude: Double
        var address:   String?

        var isOpen24Hours: Bool

        /// Raw OpenStreetMap opening_hours string. Stored for later use, not shown. Nil when the source has no hours.
        var openingHours: String?

        /// Set by the user, never by the importer.
        var isDismissed: Bool

        /// The seed version this record last appeared in.
        var seedVersion: Int

        init(
            sourceID:      String,
            brandKey:      String,
            name:          String,
            latitude:      Double,
            longitude:     Double,
            address:       String? = nil,
            isOpen24Hours: Bool    = false,
            openingHours:  String? = nil,
            isDismissed:   Bool    = false,
            seedVersion:   Int
        ) {
            self.sourceID      = sourceID
            self.brandKey      = brandKey
            self.name          = name
            self.latitude      = latitude
            self.longitude     = longitude
            self.address       = address
            self.isOpen24Hours = isOpen24Hours
            self.openingHours  = openingHours
            self.isDismissed   = isDismissed
            self.seedVersion   = seedVersion
        }

        /// `isOpen24Hours`, or nil when the source has no hours, so it is unknown.
        var isOpen24HoursIfKnown: Bool? {
            openingHours == nil ? nil : isOpen24Hours
        }

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

        var brand: BrandProfile {
            BrandProfile.profile(forKey: brandKey)
        }
    }
}

extension Sequence<Candidate> {

    /// Drops every Candidate a Bathroom links to: logging a visit hides its Candidate everywhere.
    /// Pass all Bathrooms, not a filtered subset, so a filtered-out visit still hides its store.
    func unlinked(from bathrooms: some Sequence<Bathroom>) -> [Candidate] {
        let linkedIDs = Set(bathrooms.compactMap(\.sourceID))
        return filter { !linkedIDs.contains($0.sourceID) }
    }
}
