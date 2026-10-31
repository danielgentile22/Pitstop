import SwiftData

// The app's model names always mean the latest schema version. A new version copies the models
// into its own enum, freezes the old copy, and adds a stage to the plan.

typealias Bathroom  = SchemaV1.Bathroom
typealias Candidate = SchemaV1.Candidate

/// The schema the app shipped with before versioning. Matches the store already on users' devices.
nonisolated enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Bathroom.self, Candidate.self] }
}

nonisolated enum PitstopMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
