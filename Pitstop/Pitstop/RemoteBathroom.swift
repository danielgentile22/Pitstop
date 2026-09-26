import Foundation

/// Wire format for the backend `bathrooms` table. Kept separate from the SwiftData model so the
/// server schema can change without forcing a local migration.
struct RemoteBathroom: Codable {

    // MARK: - Identity

    var id:      UUID   // same UUID as the local record
    var ownerID: UUID

    // MARK: - Location

    var name:      String
    var latitude:  Double
    var longitude: Double
    var address:   String?

    // MARK: - Rating & Notes

    var rating: Int
    var notes:  String

    // MARK: - Access & Hours

    var accessType:          String
    var requiresReceiptCode: Bool
    var isOpen24Hours:       Bool

    // MARK: - Layout

    var stallType:              String
    var genderType:             String
    var isIndoor:               Bool
    var isWheelchairAccessible: Bool

    // MARK: - Toilet Paper

    var hasToiletPaper:      Bool
    var hasExtraToiletPaper: Bool
    var dispenserRating:     Int     // 0 = no dispenser, 1-5 = rating

    // MARK: - Fixtures

    var hasHeatedSeat:   Bool
    var bidetType:       String
    var hasChangingTable: Bool

    // MARK: - Hygiene

    var hasSoap:        Bool
    var hasDryingOption: Bool
    var waitTime:        String

    // MARK: - Photos & Privacy

    var photoPaths: [String]  // storage object names
    var isPrivate:  Bool

    // MARK: - Community Verification

    /// Optional because rows that predate this column decode it as nil.
    var verificationCount: Int?

    var lastVerifiedAt: Date?

    // MARK: - Dates

    var dateVisited: Date
    var createdAt:   Date
    var updatedAt:   Date

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case id, name, latitude, longitude, address, rating, notes
        case ownerID                = "owner_id"
        case accessType             = "access_type"
        case requiresReceiptCode    = "requires_receipt_code"
        case isOpen24Hours          = "is_open_24_hours"
        case stallType              = "stall_type"
        case genderType             = "gender_type"
        case isIndoor               = "is_indoor"
        case isWheelchairAccessible = "is_wheelchair_accessible"
        case hasToiletPaper         = "has_toilet_paper"
        case hasExtraToiletPaper    = "has_extra_toilet_paper"
        case dispenserRating        = "dispenser_rating"
        case hasHeatedSeat          = "has_heated_seat"
        case bidetType              = "bidet_type"
        case hasChangingTable       = "has_changing_table"
        case hasSoap                = "has_soap"
        case hasDryingOption        = "has_drying_option"
        case waitTime               = "wait_time"
        case photoPaths             = "photo_paths"
        case isPrivate              = "is_private"
        case verificationCount      = "verification_count"
        case lastVerifiedAt         = "last_verified_at"
        case dateVisited            = "date_visited"
        case createdAt              = "created_at"
        case updatedAt              = "updated_at"
    }

    // MARK: - Convenience Init

    init(bathroom b: Bathroom, ownerID: UUID) {
        self.id                     = b.id
        self.ownerID                = ownerID
        self.name                   = b.name
        self.latitude               = b.latitude
        self.longitude              = b.longitude
        self.address                = b.address
        self.rating                 = b.rating
        self.accessType             = b.accessType.rawValue
        self.requiresReceiptCode    = b.requiresReceiptCode
        self.isOpen24Hours          = b.isOpen24Hours
        self.stallType              = b.stallType.rawValue
        self.genderType             = b.genderType.rawValue
        self.isIndoor               = b.isIndoor
        self.isWheelchairAccessible = b.isWheelchairAccessible
        self.hasToiletPaper         = b.hasToiletPaper
        self.hasExtraToiletPaper    = b.hasExtraToiletPaper
        self.dispenserRating        = b.dispenserRating
        self.hasHeatedSeat          = b.hasHeatedSeat
        self.bidetType              = b.bidetType.rawValue
        self.hasChangingTable       = b.hasChangingTable
        self.hasSoap                = b.hasSoap
        self.hasDryingOption        = b.hasDryingOption
        self.waitTime               = b.waitTime.rawValue
        self.notes                  = b.notes
        self.photoPaths             = b.imageFileNames
        self.isPrivate              = b.isPrivate
        self.verificationCount      = b.verificationCount
        self.lastVerifiedAt         = b.lastVerifiedAt
        self.dateVisited            = b.dateVisited
        self.createdAt              = b.dateCreated
        self.updatedAt              = b.dateModified
    }
}
