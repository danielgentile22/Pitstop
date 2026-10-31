import CoreLocation
import Foundation

/// Every field of the add and edit form, pin included, as one value.
/// The form keeps the snapshot it opened with and compares against it to decide whether Cancel must ask.
nonisolated struct BathroomForm: Equatable {

    /// A pin closer than this to where it started counts as unmoved: it absorbs the mini map
    /// re-centering itself on first layout, and keeps the stored address.
    static let pinTolerance: CLLocationDistance = 10

    var name        = ""
    var rating      = 0
    var notes       = ""
    var dateVisited = Date()

    var accessType          = BathroomAccess.free
    var requiresReceiptCode = false
    /// Nil while the hours are unknown; setting the toggle makes them known.
    var isOpen24Hours: Bool? = false

    var stallType              = StallType.single
    var genderType             = GenderType.allGender
    var isIndoor               = true
    var isWheelchairAccessible = false

    var hasToiletPaper      = true
    var hasExtraToiletPaper = false
    var hasDispenser        = false   // form-only; persisted as dispenserRating > 0
    var dispenserRating     = 0       // 1-5 when hasDispenser is true

    var hasHeatedSeat    = false
    var bidetType        = BidetType.none
    var hasChangingTable = false

    var hasSoap         = true
    var hasDryingOption = true
    var waitTime        = WaitTime.unknown

    var latitude:  Double
    var longitude: Double

    // MARK: - Init

    init(coordinate: CLLocationCoordinate2D) {
        latitude  = coordinate.latitude
        longitude = coordinate.longitude
    }

    @MainActor init(candidate: Candidate) {
        self.init(coordinate: candidate.coordinate)
        name          = candidate.name
        isOpen24Hours = candidate.isOpen24HoursIfKnown
    }

    @MainActor init(bathroom b: Bathroom) {
        self.init(coordinate: b.coordinate)
        name                   = b.name
        rating                 = b.rating
        notes                  = b.notes
        dateVisited            = b.dateVisited
        accessType             = b.accessType
        requiresReceiptCode    = b.requiresReceiptCode
        isOpen24Hours          = b.isOpen24HoursIfKnown
        stallType              = b.stallType
        genderType             = b.genderType
        isIndoor               = b.isIndoor
        isWheelchairAccessible = b.isWheelchairAccessible
        hasToiletPaper         = b.hasToiletPaper
        hasExtraToiletPaper    = b.hasExtraToiletPaper
        hasDispenser           = b.dispenserRating > 0
        dispenserRating        = b.dispenserRating
        hasHeatedSeat          = b.hasHeatedSeat
        bidetType              = b.bidetType
        hasChangingTable       = b.hasChangingTable
        hasSoap                = b.hasSoap
        hasDryingOption        = b.hasDryingOption
        waitTime               = b.waitTime
    }

    // MARK: - Pin

    var coordinate: CLLocationCoordinate2D {
        get { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
        set { latitude = newValue.latitude; longitude = newValue.longitude }
    }

    /// True when the pin sits more than `pinTolerance` from `origin`.
    func pinMoved(from origin: CLLocationCoordinate2D) -> Bool {
        Distance.meters(from: origin, to: coordinate) > Self.pinTolerance
    }

    // MARK: - Changes

    /// Any field differs from `original`, or the pin moved beyond the tolerance.
    func hasChanges(from original: BathroomForm) -> Bool {
        if pinMoved(from: original.coordinate) { return true }
        var unpinned = self
        unpinned.coordinate = original.coordinate
        return unpinned != original
    }

    // MARK: - Apply

    @MainActor func apply(to bathroom: Bathroom) {
        bathroom.name                   = name.trimmingCharacters(in: .whitespacesAndNewlines)
        bathroom.latitude               = latitude
        bathroom.longitude              = longitude
        bathroom.rating                 = rating
        bathroom.accessType             = accessType
        bathroom.requiresReceiptCode    = requiresReceiptCode
        bathroom.isOpen24Hours          = isOpen24Hours ?? false
        bathroom.isOpen24HoursKnown     = isOpen24Hours != nil
        bathroom.stallType              = stallType
        bathroom.genderType             = genderType
        bathroom.isIndoor               = isIndoor
        bathroom.isWheelchairAccessible = isWheelchairAccessible
        bathroom.hasToiletPaper         = hasToiletPaper
        bathroom.hasExtraToiletPaper    = hasExtraToiletPaper
        bathroom.dispenserRating        = hasDispenser ? max(1, dispenserRating) : 0
        bathroom.hasHeatedSeat          = hasHeatedSeat
        bathroom.bidetType              = bidetType
        bathroom.hasChangingTable       = hasChangingTable
        bathroom.hasSoap                = hasSoap
        bathroom.hasDryingOption        = hasDryingOption
        bathroom.waitTime               = waitTime
        bathroom.notes                  = notes
        bathroom.dateVisited            = dateVisited
        bathroom.dateModified           = Date()
    }
}
