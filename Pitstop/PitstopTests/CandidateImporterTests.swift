import Foundation
import SwiftData
import Testing
@testable import Pitstop

@MainActor
struct CandidateImporterTests {

    let container: ModelContainer
    let context: ModelContext

    init() throws {
        container = try ModelContainer(
            for: Bathroom.self, Candidate.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    // MARK: - Helpers

    private func record(
        _ sourceID: String,
        name: String = "Barnes & Noble",
        latitude: Double = 38.8,
        isOpen24Hours: Bool = false
    ) -> CandidateSeed.Record {
        CandidateSeed.Record(
            sourceID: sourceID,
            brandKey: "barnes_and_noble",
            name: name,
            latitude: latitude,
            longitude: -77.0,
            address: "1 Main St, Town, VA 22305",
            isOpen24Hours: isOpen24Hours,
            openingHours: isOpen24Hours ? "24/7" : nil
        )
    }

    private func apply(version: Int, _ records: [CandidateSeed.Record]) throws {
        try CandidateImporter.apply(CandidateSeed(version: version, records: records), to: context)
        try context.save()
    }

    private func candidates() throws -> [String: Candidate] {
        let all = try context.fetch(FetchDescriptor<Candidate>())
        return Dictionary(uniqueKeysWithValues: all.map { ($0.sourceID, $0) })
    }

    // MARK: - Apply

    @Test func insertsNewRecords() throws {
        try apply(version: 1, [record("a"), record("b", isOpen24Hours: true)])

        let stored = try candidates()
        #expect(Set(stored.keys) == ["a", "b"])
        #expect(stored["b"]?.isOpen24Hours == true)
        #expect(stored["b"]?.openingHours == "24/7")
        #expect(stored["a"]?.seedVersion == 1)
        #expect(stored["a"]?.isDismissed == false)
    }

    @Test func updatesChangedRecordsAndKeepsTheDismissal() throws {
        try apply(version: 1, [record("a")])
        try candidates()["a"]?.isDismissed = true
        try context.save()

        try apply(version: 2, [record("a", name: "Barnes & Noble (Moved)", latitude: 39.0, isOpen24Hours: true)])

        let a = try #require(try candidates()["a"])
        #expect(a.name == "Barnes & Noble (Moved)")
        #expect(a.latitude == 39.0)
        #expect(a.isOpen24Hours)
        #expect(a.seedVersion == 2)
        #expect(a.isDismissed)
    }

    @Test func deletesRecordsMissingFromTheSeed() throws {
        try apply(version: 1, [record("a"), record("b")])
        try apply(version: 2, [record("a")])

        #expect(Set(try candidates().keys) == ["a"])
    }

    @Test func keepsDismissedAndLinkedRecordsMissingFromTheSeed() throws {
        try apply(version: 1, [record("dismissed"), record("linked"), record("gone")])
        try candidates()["dismissed"]?.isDismissed = true
        let bathroom = Bathroom(name: "B&N", latitude: 38.8, longitude: -77.0)
        bathroom.sourceID = "linked"
        context.insert(bathroom)
        try context.save()

        try apply(version: 2, [])

        let stored = try candidates()
        #expect(Set(stored.keys) == ["dismissed", "linked"])
        #expect(stored["dismissed"]?.seedVersion == 1)
    }

    @Test func aDismissalSurvivesTheStoreLeavingTheSeedAndComingBack() throws {
        try apply(version: 1, [record("dismissed"), record("other")])
        try candidates()["dismissed"]?.isDismissed = true
        try context.save()

        try apply(version: 2, [record("other")])
        #expect(try candidates()["dismissed"]?.isDismissed == true)

        try apply(version: 3, [record("dismissed", name: "Barnes & Noble (Reopened)"), record("other")])
        let dismissed = try #require(try candidates()["dismissed"])
        #expect(dismissed.isDismissed)
        #expect(dismissed.name == "Barnes & Noble (Reopened)")
        #expect(dismissed.seedVersion == 3)
        #expect(try candidates().count == 2)
    }

    @Test func undoingADismissalSurvivesARefresh() throws {
        try apply(version: 1, [record("a")])
        try candidates()["a"]?.isDismissed = true
        try context.save()
        try candidates()["a"]?.isDismissed = false
        try context.save()

        try apply(version: 2, [record("a")])

        #expect(try candidates()["a"]?.isDismissed == false)
    }

    @Test func aLinkedCandidateStaysHiddenAcrossRefreshes() throws {
        try apply(version: 1, [record("linked"), record("other")])
        let bathroom = Bathroom(name: "B&N", latitude: 38.8, longitude: -77.0)
        bathroom.sourceID = "linked"
        context.insert(bathroom)
        try context.save()

        func visibleIDs() throws -> Set<String> {
            let all = try context.fetch(FetchDescriptor<Candidate>())
            return Set(all.unlinked(from: try context.fetch(FetchDescriptor<Bathroom>())).map(\.sourceID))
        }
        #expect(try visibleIDs() == ["other"])

        try apply(version: 2, [record("linked", name: "Barnes & Noble (Renamed)"), record("other")])
        #expect(try visibleIDs() == ["other"])

        try apply(version: 3, [record("other")])
        #expect(Set(try candidates().keys) == ["linked", "other"])
        #expect(try visibleIDs() == ["other"])
    }

    @Test func applyingTheSameSeedTwiceChangesNothing() throws {
        let seed = CandidateSeed(version: 1, records: [record("a"), record("b", isOpen24Hours: true)])
        try CandidateImporter.apply(seed, to: context)
        try context.save()

        try CandidateImporter.apply(seed, to: context)

        #expect(!context.hasChanges)
        #expect(Set(try candidates().keys) == ["a", "b"])
    }

    // MARK: - Version gate

    @Test func importsOnlyWhenTheSeedVersionIsNewer() throws {
        let defaults = try #require(UserDefaults(suiteName: "CandidateImporterTests.\(UUID())"))

        #expect(try CandidateImporter.importIfNewer(CandidateSeed(version: 2, records: [record("a")]), into: container, defaults: defaults))
        #expect(defaults.integer(forKey: CandidateImporter.lastImportedVersionKey) == 2)

        #expect(try !CandidateImporter.importIfNewer(CandidateSeed(version: 2, records: []), into: container, defaults: defaults))
        #expect(try !CandidateImporter.importIfNewer(CandidateSeed(version: 1, records: []), into: container, defaults: defaults))
        #expect(Set(try candidates().keys) == ["a"])
    }

    // MARK: - Bundled seed

    @Test func bundledSeedDecodesAndUsesKnownBrands() throws {
        let seed = try CandidateImporter.loadBundledSeed()

        #expect(seed.version >= 1)
        #expect(!seed.records.isEmpty)
        #expect(seed.records.allSatisfy { BrandProfile.table[$0.brandKey] != nil })
    }

    /// The importer keys Candidates by source ID, so two records sharing one would merge two stores.
    @Test func bundledSeedSourceIDsAreUnique() throws {
        let ids = try CandidateImporter.loadBundledSeed().records.map(\.sourceID)
        let repeated = Dictionary(grouping: ids, by: { $0 }).filter { $0.value.count > 1 }.keys

        #expect(repeated.isEmpty, "Repeated source IDs: \(repeated.sorted())")
    }
}
