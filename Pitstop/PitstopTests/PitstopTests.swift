import Testing
@testable import Pitstop

// The app defaults to MainActor isolation, so suites that touch app types run on the main actor.
@MainActor
struct PitstopTests {

    @Test func accessTypeDecodesFromItsStoredRawValue() {
        #expect(BathroomAccess(rawValue: "free") == .free)
    }
}
