//
//  RemoteBathroom.swift
//  Pitstop
//
//  Codable Data Transfer Object (DTO) that mirrors the `bathrooms` table in
//  Supabase. Used exclusively for encoding outbound upserts and decoding
//  inbound SELECT results.
//
//  Why a separate struct instead of making Bathroom itself Codable?
//    The SwiftData `Bathroom` model uses camelCase Swift property names, while
//    Postgres uses snake_case column names. CodingKeys handles that translation
//    here. Keeping the DTO separate also means the cloud schema can evolve
//    independently from the local model without breaking SwiftData migrations.
//
//  Data flow:
//    Upload:  Bathroom (SwiftData) → RemoteBathroom.init(bathroom:ownerID:) → Supabase upsert
//    Download: Supabase SELECT → Decodable init → SupabaseService.upsertLocal() → Bathroom
//
//  Date columns:
//    The Supabase table uses `created_at` / `updated_at` (Postgres convention).
//    These map to `dateCreated` / `dateModified` on the local Bathroom model.
//    supabase-swift decodes TIMESTAMPTZ columns as Swift Date automatically.
//

import Foundation

struct RemoteBathroom: Codable {

    // MARK: - Identity

    var id:      UUID   // Primary key — same UUID as the local SwiftData record
    var ownerID: UUID   // auth.users.id of the person who created this entry

    // MARK: - Location

    var name:      String
    var latitude:  Double
    var longitude: Double
    var address:   String?  // May be nil if reverse geocoding failed

    // MARK: - Rating & Notes

    var rating: Int
    var notes:  String

    // MARK: - Access & Hours

    var accessType:          String  // Raw value of BathroomAccess enum
    var requiresReceiptCode: Bool
    var isOpen24Hours:       Bool

    // MARK: - Layout

    var stallType:              String  // Raw value of StallType enum
    var genderType:             String  // Raw value of GenderType enum
    var isIndoor:               Bool
    var isWheelchairAccessible: Bool

    // MARK: - Toilet Paper

    var hasToiletPaper:      Bool
    var hasExtraToiletPaper: Bool
    var dispenserRating:     Int     // 0 = no dispenser; 1–5 = quality rating

    // MARK: - Fixtures

    var hasHeatedSeat:   Bool
    var bidetType:       String  // Raw value of BidetType enum
    var hasChangingTable: Bool

    // MARK: - Hygiene

    var hasSoap:        Bool
    var hasDryingOption: Bool
    var waitTime:        String  // Raw value of WaitTime enum

    // MARK: - Photos & Privacy

    var photoPaths: [String]  // File names of photos in Supabase Storage
    var isPrivate:  Bool      // If true, only the owner sees this in the cloud

    // MARK: - Community Verification

    /// Number of users who confirmed this bathroom still exists.
    /// Optional so rows created before this column was added decode to nil → 0.
    var verificationCount: Int?

    /// When this bathroom was last verified by any user.
    var lastVerifiedAt: Date?

    // MARK: - Dates

    var dateVisited: Date   // When the user visited the bathroom
    var createdAt:   Date   // Row creation timestamp (set by Postgres default)
    var updatedAt:   Date   // Last modification timestamp (sent by the app on upsert)

    // MARK: - CodingKeys
    // Maps Swift camelCase properties to Postgres snake_case column names.

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

    /// Builds a remote DTO from a local SwiftData bathroom, ready to upsert.
    ///
    /// All enum values are sent as their raw String values so Postgres stores
    /// them as TEXT columns (e.g. `"free"`, `"single"`, `"none"`).
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
        self.updatedAt              = b.dateModified  // Sends current mod time so server stays in sync
    }
}
