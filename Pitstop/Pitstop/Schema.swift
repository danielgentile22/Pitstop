import SwiftData

// The app's model names always mean the latest schema version. A new version copies the models it changes
// into its own enum, freezes the old copy, and adds a stage to the plan. Unchanged models are reused.

typealias LatestSchema = SchemaV2
typealias Bathroom     = SchemaV2.Bathroom
typealias Candidate    = SchemaV1.Candidate

/// The schema the app shipped with before versioning. Matches the store already on users' devices.
nonisolated enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Bathroom.self, Candidate.self] }
}

/// Adds `Bathroom.isOpen24HoursKnown`, so a visit logged from a Candidate with no hours keeps unknown hours.
nonisolated enum SchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [Bathroom.self, SchemaV1.Candidate.self] }
}

nonisolated enum PitstopMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }
    // V1 to V2 adds one optional field, so existing rows get nil, which means known hours.
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)]
    }
}
