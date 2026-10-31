import Foundation
import SwiftData

// Frozen: the Bathroom model exactly as SchemaV1 shipped it. Never edit; migrations read stores written with it.
// Candidate is unchanged since V1, so SchemaV1.Candidate lives in Candidate.swift and later versions reuse it.

extension SchemaV1 {

    @Model
    final class Bathroom {

        // MARK: - Identity

        /// Also the folder name for this bathroom's photos: `Documents/BathroomImages/{id}/`.
        @Attribute(.unique) var id: UUID

        // MARK: - Location

        var name:      String
        var latitude:  Double
        var longitude: Double

        /// Reverse-geocoded address. Nil if geocoding failed or was never attempted; the UI falls back to coordinates.
        var address: String?

        // MARK: - Dates

        var dateVisited:  Date
        var dateCreated:  Date
        var dateModified: Date

        // MARK: - Overall Rating

        /// 1-5 stars; 0 = unrated.
        var rating: Int

        // MARK: - Access & Availability

        var accessType: BathroomAccess
        var requiresReceiptCode: Bool
        var isOpen24Hours: Bool

        // MARK: - Layout

        var stallType: StallType
        var genderType: GenderType
        var isIndoor: Bool
        var isWheelchairAccessible: Bool

        // MARK: - Toilet Paper

        var hasToiletPaper: Bool
        var hasExtraToiletPaper: Bool

        /// 1-5; 0 = no dispenser or unknown.
        var dispenserRating: Int

        // MARK: - Fixtures

        var hasHeatedSeat: Bool
        var bidetType: BidetType
        var hasChangingTable: Bool

        // MARK: - Hygiene

        var hasSoap: Bool
        var hasDryingOption: Bool
        var waitTime: WaitTime

        // MARK: - Notes & Photos

        var notes: String

        /// File names only, not paths: the sandbox Documents path can change across app updates,
        /// so the full path is rebuilt at read time.
        var imageFileNames: [String]

        // MARK: - Source

        /// The `Candidate.sourceID` this bathroom was logged from, if any. Hides that Candidate everywhere.
        var sourceID: String? = nil

        // MARK: - Init

        init(
            id:                     UUID           = UUID(),
            name:                   String,
            latitude:               Double,
            longitude:              Double,
            address:                String?        = nil,
            rating:                 Int            = 0,
            accessType:             BathroomAccess = .free,
            requiresReceiptCode:    Bool           = false,
            isOpen24Hours:          Bool           = false,
            stallType:              StallType      = .single,
            genderType:             GenderType     = .allGender,
            isIndoor:               Bool           = true,
            isWheelchairAccessible: Bool           = false,
            hasToiletPaper:         Bool           = true,
            hasExtraToiletPaper:    Bool           = false,
            dispenserRating:        Int            = 0,
            hasHeatedSeat:          Bool           = false,
            bidetType:              BidetType      = .none,
            hasChangingTable:       Bool           = false,
            hasSoap:                Bool           = true,
            hasDryingOption:        Bool           = true,
            waitTime:               WaitTime       = .unknown,
            notes:                  String         = "",
            dateVisited:            Date           = Date(),
            dateCreated:            Date?          = nil,
            imageFileNames:         [String]       = []
        ) {
            self.id                     = id
            self.name                   = name
            self.latitude               = latitude
            self.longitude              = longitude
            self.address                = address
            self.rating                 = rating
            self.accessType             = accessType
            self.requiresReceiptCode    = requiresReceiptCode
            self.isOpen24Hours          = isOpen24Hours
            self.stallType              = stallType
            self.genderType             = genderType
            self.isIndoor               = isIndoor
            self.isWheelchairAccessible = isWheelchairAccessible
            self.hasToiletPaper         = hasToiletPaper
            self.hasExtraToiletPaper    = hasExtraToiletPaper
            self.dispenserRating        = dispenserRating
            self.hasHeatedSeat          = hasHeatedSeat
            self.bidetType              = bidetType
            self.hasChangingTable       = hasChangingTable
            self.hasSoap                = hasSoap
            self.hasDryingOption        = hasDryingOption
            self.waitTime               = waitTime
            self.notes                  = notes
            self.dateVisited            = dateVisited
            self.dateCreated            = dateCreated ?? Date()
            self.dateModified           = Date()
            self.imageFileNames         = imageFileNames
        }
    }
}
