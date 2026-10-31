import SwiftData
import Testing
@testable import Pitstop

// The app defaults to MainActor isolation, so suites that touch app types run on the main actor.
@MainActor
struct StoredEnumRawValueTests {

    // These raw values are on disk. A failure here means a rename would stop existing rows decoding.

    @Test func bathroomAccessRawValues() {
        #expect(BathroomAccess.allCases.map(\.rawValue) == [
            "free", "paid_entry", "paid_venue", "purchase", "key_required", "private",
        ])
    }

    @Test func stallTypeRawValues() {
        #expect(StallType.allCases.map(\.rawValue) == ["single", "multi", "unknown"])
    }

    @Test func genderTypeRawValues() {
        #expect(GenderType.allCases.map(\.rawValue) == ["all_gender", "men", "women", "family"])
    }

    @Test func bidetTypeRawValues() {
        #expect(BidetType.allCases.map(\.rawValue) == ["none", "handheld", "electronic"])
    }

    @Test func waitTimeRawValues() {
        #expect(WaitTime.allCases.map(\.rawValue) == ["unknown", "empty", "sometimes_busy", "usually_busy"])
    }
}

@MainActor
struct SchemaVersionTests {

    @Test func currentModelsAreTheLatestSchemaVersion() {
        let latest = PitstopMigrationPlan.schemas.last
        #expect(latest == SchemaV1.self)
        #expect(Bathroom.self == SchemaV1.Bathroom.self)
        #expect(Candidate.self == SchemaV1.Candidate.self)
    }

    @Test func containerOpensThroughTheMigrationPlan() throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: SchemaV1.self),
            migrationPlan: PitstopMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        context.insert(Bathroom(name: "Test", latitude: 1, longitude: 2))
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Bathroom>()) == 1)
    }
}
