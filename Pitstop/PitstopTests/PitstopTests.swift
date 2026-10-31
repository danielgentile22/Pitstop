import Foundation
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
        #expect(latest == SchemaV2.self)
        #expect(LatestSchema.self == SchemaV2.self)
        #expect(Bathroom.self == SchemaV2.Bathroom.self)
        #expect(Candidate.self == SchemaV1.Candidate.self)
    }

    @Test func containerOpensThroughTheMigrationPlan() throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: LatestSchema.self),
            migrationPlan: PitstopMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        context.insert(Bathroom(name: "Test", latitude: 1, longitude: 2))
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Bathroom>()) == 1)
    }

    @Test func versionOneStoreMigratesWithKnownHours() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SchemaMigration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("store.sqlite")

        do {
            let v1 = try ModelContainer(for: Schema(versionedSchema: SchemaV1.self),
                                        configurations: ModelConfiguration(url: url))
            let context = ModelContext(v1)
            context.insert(SchemaV1.Bathroom(name: "Closes", latitude: 1, longitude: 2, isOpen24Hours: false))
            context.insert(SchemaV1.Bathroom(name: "All night", latitude: 1, longitude: 2, isOpen24Hours: true))
            try context.save()
        }

        let v2 = try ModelContainer(for: Schema(versionedSchema: SchemaV2.self),
                                    migrationPlan: PitstopMigrationPlan.self,
                                    configurations: ModelConfiguration(url: url))
        let migrated = try ModelContext(v2).fetch(FetchDescriptor<Bathroom>(sortBy: [SortDescriptor(\.name)]))
        #expect(migrated.map(\.name) == ["All night", "Closes"])
        #expect(migrated.map(\.isOpen24HoursKnown) == [nil, nil])
        #expect(migrated.map(\.isOpen24HoursIfKnown) == [true, false])
    }
}
