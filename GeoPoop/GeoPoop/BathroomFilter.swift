//
//  BathroomFilter.swift
//  GeoPoop
//
//  Value type describing the active filter state for the bathroom list.
//  Plain struct so it can live as @State in ContentView and flow down
//  to ListTabView as a value parameter — no extra state management needed.
//

import Foundation

// MARK: - MaxDistance

/// Distance radius options for the list filter.
enum MaxDistance: Double, CaseIterable, Equatable {
    case halfMile  =  804.67   // 0.5 miles in metres
    case oneMile   = 1609.34   // 1 mile
    case fiveMiles = 8046.72   // 5 miles
    case tenMiles  = 16093.44  // 10 miles

    var displayName: String {
        switch self {
        case .halfMile:  return "½ mi"
        case .oneMile:   return "1 mi"
        case .fiveMiles: return "5 mi"
        case .tenMiles:  return "10 mi"
        }
    }
}

// MARK: - BathroomFilter

struct BathroomFilter: Equatable {

    // MARK: - Rating

    /// Minimum overall star rating. 0 = any (no filter).
    var minimumRating: Int = 0

    // MARK: - Access

    /// Only show bathrooms with one of these access types. Empty = any.
    var accessTypes: Set<BathroomAccess> = []

    // MARK: - Layout

    /// Only show bathrooms matching one of these stall types. Empty = any.
    var stallTypes: Set<StallType> = []

    /// Only show bathrooms matching one of these gender designations. Empty = any.
    var genderTypes: Set<GenderType> = []

    // MARK: - Boolean Must-Haves

    var requiresOpen24Hours:          Bool = false
    var requiresIndoor:               Bool = false
    var requiresWheelchairAccessible: Bool = false
    var requiresChangingTable:        Bool = false
    var requiresToiletPaper:          Bool = false
    var requiresHeatedSeat:           Bool = false
    var requiresBidet:                Bool = false
    var requiresSoap:                 Bool = false
    var requiresDryingOption:         Bool = false

    // MARK: - Wait Time

    /// Only show bathrooms with one of these typical wait times. Empty = any.
    var waitTimes: Set<WaitTime> = []

    // MARK: - Distance

    /// Maximum distance from the user's location. nil = no limit.
    /// Applied separately in ListTabView (requires live user location).
    var maxDistance: MaxDistance? = nil

    // MARK: - Derived

    /// True when any criterion differs from its default value.
    var isActive: Bool {
        minimumRating > 0
        || !accessTypes.isEmpty
        || !stallTypes.isEmpty
        || !genderTypes.isEmpty
        || requiresOpen24Hours
        || requiresIndoor
        || requiresWheelchairAccessible
        || requiresChangingTable
        || requiresToiletPaper
        || requiresHeatedSeat
        || requiresBidet
        || requiresSoap
        || requiresDryingOption
        || !waitTimes.isEmpty
        || maxDistance != nil
    }

    // MARK: - Application

    /// Returns true when `bathroom` passes every active criterion.
    ///
    /// Note: `maxDistance` is NOT evaluated here because it requires a
    /// live CLLocation, which this value type doesn't own. It is applied
    /// as a separate step in ListTabView.displayedBathrooms.
    func applies(to bathroom: Bathroom) -> Bool {

        if minimumRating > 0 {
            guard bathroom.rating >= minimumRating else { return false }
        }
        if !accessTypes.isEmpty {
            guard accessTypes.contains(bathroom.accessType) else { return false }
        }
        if !stallTypes.isEmpty {
            guard stallTypes.contains(bathroom.stallType) else { return false }
        }
        if !genderTypes.isEmpty {
            guard genderTypes.contains(bathroom.genderType) else { return false }
        }
        if requiresOpen24Hours          { guard bathroom.isOpen24Hours          else { return false } }
        if requiresIndoor               { guard bathroom.isIndoor               else { return false } }
        if requiresWheelchairAccessible { guard bathroom.isWheelchairAccessible else { return false } }
        if requiresChangingTable        { guard bathroom.hasChangingTable        else { return false } }
        if requiresToiletPaper          { guard bathroom.hasToiletPaper          else { return false } }
        if requiresHeatedSeat           { guard bathroom.hasHeatedSeat           else { return false } }
        if requiresBidet                { guard bathroom.bidetType != .none      else { return false } }
        if requiresSoap                 { guard bathroom.hasSoap                 else { return false } }
        if requiresDryingOption         { guard bathroom.hasDryingOption         else { return false } }
        if !waitTimes.isEmpty           { guard waitTimes.contains(bathroom.waitTime) else { return false } }

        return true
    }

    // MARK: - Reset

    mutating func reset() {
        self = BathroomFilter()
    }
}
