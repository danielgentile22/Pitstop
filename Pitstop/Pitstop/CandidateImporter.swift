import Foundation
import SwiftData

/// The bundled `CandidateSeed.json`, written by `scripts/seed/build_seed.py`.
nonisolated struct CandidateSeed: Decodable, Sendable {

    nonisolated struct Record: Decodable, Sendable {
        let sourceID: String
        let brandKey: String
        let name: String
        let latitude: Double
        let longitude: Double
        let address: String?
        let isOpen24Hours: Bool
        let openingHours: String?
    }

    let version: Int
    let records: [Record]
}

/// Applies the bundled seed to the store. Never touches `isDismissed`, and never deletes a dismissed
/// Candidate or one a Bathroom links to, so the user's own knowledge survives every refresh.
nonisolated enum CandidateImporter {

    static let lastImportedVersionKey = "candidateSeedLastImportedVersion"

    static func loadBundledSeed(bundle: Bundle = .main) throws -> CandidateSeed {
        guard let url = bundle.url(forResource: "CandidateSeed", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(CandidateSeed.self, from: Data(contentsOf: url))
    }

    /// Applies `seed` in its own context when its version is newer than the last import.
    /// Records the version only after the save succeeds, so a failed import retries next launch.
    @discardableResult
    static func importIfNewer(_ seed: CandidateSeed, into container: ModelContainer, defaults: UserDefaults) throws -> Bool {
        guard seed.version > defaults.integer(forKey: lastImportedVersionKey) else { return false }
        let context = ModelContext(container)
        try apply(seed, to: context)
        try context.save()
        defaults.set(seed.version, forKey: lastImportedVersionKey)
        return true
    }

    /// Inserts new records, updates changed ones, deletes unprotected ones missing from the seed. Does not save.
    static func apply(_ seed: CandidateSeed, to context: ModelContext) throws {
        let linkedIDs = Set(
            try context.fetch(FetchDescriptor<Bathroom>(predicate: #Predicate { $0.sourceID != nil }))
                .compactMap(\.sourceID)
        )
        var existing = Dictionary(
            try context.fetch(FetchDescriptor<Candidate>()).map { ($0.sourceID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for record in seed.records {
            if let candidate = existing.removeValue(forKey: record.sourceID) {
                update(candidate, from: record, version: seed.version)
            } else {
                context.insert(Candidate(
                    sourceID:      record.sourceID,
                    brandKey:      record.brandKey,
                    name:          record.name,
                    latitude:      record.latitude,
                    longitude:     record.longitude,
                    address:       record.address,
                    isOpen24Hours: record.isOpen24Hours,
                    openingHours:  record.openingHours,
                    seedVersion:   seed.version
                ))
            }
        }

        for candidate in existing.values where !candidate.isDismissed && !linkedIDs.contains(candidate.sourceID) {
            context.delete(candidate)
        }
    }

    /// Assigns only what differs, so applying the same seed again leaves the context unchanged.
    private static func update(_ candidate: Candidate, from record: CandidateSeed.Record, version: Int) {
        func set<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<Candidate, Value>, _ value: Value) {
            if candidate[keyPath: keyPath] != value { candidate[keyPath: keyPath] = value }
        }
        set(\.brandKey, record.brandKey)
        set(\.name, record.name)
        set(\.latitude, record.latitude)
        set(\.longitude, record.longitude)
        set(\.address, record.address)
        set(\.isOpen24Hours, record.isOpen24Hours)
        set(\.openingHours, record.openingHours)
        set(\.seedVersion, version)
    }
}
