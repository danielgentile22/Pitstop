import CoreLocation
import Foundation
import SwiftData
import Testing
import UIKit
@testable import Pitstop

@MainActor
struct BathroomSaverTests {

    let container: ModelContainer
    let context: ModelContext
    let photoRoot: URL

    init() throws {
        container = try ModelContainer(
            for: Bathroom.self, Candidate.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
        photoRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("BathroomSaverTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: photoRoot, withIntermediateDirectories: true)
    }

    // MARK: - Helpers

    private static let origin = CLLocationCoordinate2D(latitude: 38.8, longitude: -77.0)

    private struct CommitFailed: Error {}

    private func saver(
        geocode: @escaping (CLLocationCoordinate2D) async -> String? = { _ in "Geocoded St" },
        geocodeTimeout: Duration = .seconds(2),
        root: URL? = nil,
        commit: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) -> BathroomSaver {
        BathroomSaver(
            context: context,
            photoRoot: root ?? photoRoot,
            geocode: geocode,
            geocodeTimeout: geocodeTimeout,
            commit: commit
        )
    }

    private func photo() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    private func form(name: String = "Cafe", at coordinate: CLLocationCoordinate2D = origin) -> BathroomForm {
        var form = BathroomForm(coordinate: coordinate)
        form.name = name
        return form
    }

    /// A committed Bathroom with two photos on disk.
    private func storedBathroom(address: String? = "1 Main St") throws -> Bathroom {
        let bathroom = Bathroom(name: "Cafe", latitude: Self.origin.latitude, longitude: Self.origin.longitude, address: address, rating: 3)
        bathroom.imageFileNames = [
            try ImageStorage.saveImage(photo(), bathroomID: bathroom.id, root: photoRoot),
            try ImageStorage.saveImage(photo(), bathroomID: bathroom.id, root: photoRoot),
        ]
        context.insert(bathroom)
        try context.save()
        return bathroom
    }

    private func files(of bathroom: Bathroom) throws -> Set<String> {
        let dir = photoRoot.appendingPathComponent(bathroom.id.uuidString)
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
        return Set(try FileManager.default.contentsOfDirectory(atPath: dir.path))
    }

    private func fileExists(_ name: String, of bathroom: Bathroom) -> Bool {
        FileManager.default.fileExists(atPath: photoRoot.appendingPathComponent(bathroom.id.uuidString).appendingPathComponent(name).path)
    }

    /// Reads through a second context, so it sees only what was committed.
    private func committedBathrooms() throws -> [Bathroom] {
        try ModelContext(container).fetch(FetchDescriptor<Bathroom>())
    }

    private func moved(_ coordinate: CLLocationCoordinate2D, meters: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: coordinate.latitude + meters / 111_000, longitude: coordinate.longitude)
    }

    // MARK: - Commit and photos

    @Test func newBathroomIsCommittedWithItsPhotos() async throws {
        let bathroom = try await saver().save(form(), to: .new(from: nil), photos: .init(added: [photo()]))

        let stored = try committedBathrooms()
        #expect(stored.map(\.id) == [bathroom.id])
        #expect(stored.first?.imageFileNames.count == 1)
        #expect(try files(of: bathroom).count == 2)   // full size and thumbnail
    }

    @Test func photosAreStoredAtTheirIntendedPixelSize() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let large = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 2000), format: format).image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 3000, height: 2000))
        }

        let bathroom = try await saver().save(form(), to: .new(from: nil), photos: .init(added: [large]))

        let dir = photoRoot.appendingPathComponent(bathroom.id.uuidString)
        let name = try #require(bathroom.imageFileNames.first)
        let full  = try #require(UIImage(contentsOfFile: dir.appendingPathComponent(name).path)?.cgImage)
        let thumb = try #require(UIImage(contentsOfFile: dir.appendingPathComponent(name.replacingOccurrences(of: ".jpg", with: "_thumb.jpg")).path)?.cgImage)
        #expect(full.width == 1200 && full.height == 800)
        #expect(thumb.width == 200 && thumb.height == 133)
    }

    @Test func editCommitsBeforeDeletingRemovedPhotos() async throws {
        let bathroom = try storedBathroom()
        let kept = bathroom.imageFileNames[0]
        let removed = bathroom.imageFileNames[1]
        var removedExistedAtCommit = false

        let saver = saver(commit: { context in
            removedExistedAtCommit = fileExists(removed, of: bathroom)
            try context.save()
        })
        try await saver.save(BathroomForm(bathroom: bathroom), to: .edit(bathroom), photos: .init(kept: [kept]))

        #expect(removedExistedAtCommit)
        #expect(!fileExists(removed, of: bathroom))
        #expect(fileExists(kept, of: bathroom))
        #expect(try committedBathrooms().first?.imageFileNames == [kept])
    }

    @Test func failedCommitLeavesStoreAndFilesUnchanged() async throws {
        let bathroom = try storedBathroom()
        let before = try files(of: bathroom)
        var edited = BathroomForm(bathroom: bathroom)
        edited.rating = 5

        await #expect(throws: BathroomSaver.SaveError.commitFailed) {
            _ = try await saver(commit: { _ in throw CommitFailed() })
                .save(edited, to: .edit(bathroom), photos: .init(kept: [bathroom.imageFileNames[0]], added: [photo()]))
        }

        #expect(try files(of: bathroom) == before)
        #expect(bathroom.rating == 3)
        #expect(bathroom.imageFileNames.count == 2)
        #expect(!context.hasChanges)
        #expect(try committedBathrooms().first?.rating == 3)
    }

    @Test func failedNewBathroomCommitInsertsNothing() async throws {
        await #expect(throws: BathroomSaver.SaveError.commitFailed) {
            _ = try await saver(commit: { _ in throw CommitFailed() })
                .save(form(), to: .new(from: nil), photos: .init(added: [photo(), photo()]))
        }

        #expect(try context.fetchCount(FetchDescriptor<Bathroom>()) == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: photoRoot.path).allSatisfy { name in
            (try? FileManager.default.contentsOfDirectory(atPath: photoRoot.appendingPathComponent(name).path))?.isEmpty ?? true
        })
    }

    @Test func failedPhotoWriteSavesNothing() async throws {
        // A regular file where the photo folder should be makes every write fail.
        let blocked = photoRoot.appendingPathComponent("not-a-folder")
        try Data().write(to: blocked)

        await #expect(throws: BathroomSaver.SaveError.photoWriteFailed) {
            _ = try await saver(root: blocked).save(form(), to: .new(from: nil), photos: .init(added: [photo()]))
        }
        #expect(try context.fetchCount(FetchDescriptor<Bathroom>()) == 0)
        #expect(try committedBathrooms().isEmpty)
    }

    @Test func failedThumbnailWriteRemovesFullSizeFile() throws {
        let id = UUID()
        let dir = photoRoot.appendingPathComponent(id.uuidString)
        // A folder at the thumbnail's path makes only the thumbnail write fail.
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("img_x_thumb.jpg"), withIntermediateDirectories: true)

        #expect(throws: (any Error).self) {
            try ImageStorage.saveImage(photo(), bathroomID: id, root: photoRoot, fileName: "img_x.jpg")
        }
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("img_x.jpg").path))
    }

    // MARK: - Candidates

    @Test func loggingACandidateTwiceIsRefused() async throws {
        let candidate = Candidate(sourceID: "atp:a", brandKey: "target", name: "Target", latitude: 38.8, longitude: -77.0, seedVersion: 1)
        context.insert(candidate)
        let existing = Bathroom(name: "Target", latitude: 38.8, longitude: -77.0)
        existing.sourceID = "atp:a"
        context.insert(existing)
        try context.save()

        await #expect(throws: BathroomSaver.SaveError.alreadyLogged) {
            _ = try await saver().save(BathroomForm(candidate: candidate), to: .new(from: candidate), photos: .init(added: [photo()]))
        }
        #expect(try context.fetchCount(FetchDescriptor<Bathroom>()) == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: photoRoot.path).isEmpty)
    }

    @Test func concurrentSavesOfOneCandidateLogOneVisit() async throws {
        let candidate = Candidate(sourceID: "atp:a", brandKey: "target", name: "Target", latitude: 38.8, longitude: -77.0, seedVersion: 1)
        context.insert(candidate)
        try context.save()
        // A slow geocode keeps both saves past the first duplicate check before either inserts.
        let saver = saver(geocode: { _ in try? await Task.sleep(for: .milliseconds(100)); return "Geocoded St" })
        let photos = BathroomSaver.PhotoChanges(added: [photo()])

        func attempt() async -> BathroomSaver.SaveError? {
            do { try await saver.save(BathroomForm(candidate: candidate), to: .new(from: candidate), photos: photos); return nil }
            catch { return error as? BathroomSaver.SaveError }
        }
        let first  = Task { await attempt() }
        let second = Task { await attempt() }
        let errors = [await first.value, await second.value]

        #expect(errors.filter { $0 == nil }.count == 1)
        #expect(errors.contains(.alreadyLogged))
        let committed = try committedBathrooms()
        #expect(committed.count == 1)
        // The refused save removed its photos, so every file on disk belongs to the logged Bathroom.
        let folders = try FileManager.default.contentsOfDirectory(atPath: photoRoot.path)
        let stored = try folders.flatMap { try FileManager.default.contentsOfDirectory(atPath: photoRoot.appendingPathComponent($0).path) }
        #expect(Set(stored) == (try files(of: committed[0])))
        #expect(stored.count == 2)
    }

    @Test func loggingACandidateLinksItAndClearsItsDismissal() async throws {
        let candidate = Candidate(sourceID: "atp:a", brandKey: "target", name: "Target", latitude: 38.8, longitude: -77.0,
                                  address: "2 Store Rd", isDismissed: true, seedVersion: 1)
        context.insert(candidate)
        try context.save()

        let bathroom = try await saver().save(BathroomForm(candidate: candidate), to: .new(from: candidate), photos: .init())

        #expect(bathroom.sourceID == "atp:a")
        #expect(bathroom.address == "2 Store Rd")
        let committed = try ModelContext(container).fetch(FetchDescriptor<Candidate>())
        #expect(committed.first?.isDismissed == false)
    }

    @Test(arguments: [
        (openingHours: String?.none, toggle: Bool?.none, expected: Bool?.none),
        (openingHours: String?.none, toggle: Bool?.some(false), expected: Bool?.some(false)),
        (openingHours: String?.none, toggle: Bool?.some(true), expected: Bool?.some(true)),
        (openingHours: String?.some("24/7"), toggle: Bool?.none, expected: Bool?.some(true)),
    ])
    func loggingACandidateKeepsItsHoursUntilTheToggleIsSet(openingHours: String?, toggle: Bool?, expected: Bool?) async throws {
        let candidate = Candidate(sourceID: "atp:a", brandKey: "target", name: "Target", latitude: 38.8, longitude: -77.0,
                                  isOpen24Hours: openingHours != nil, openingHours: openingHours, seedVersion: 1)
        context.insert(candidate)
        try context.save()

        var form = BathroomForm(candidate: candidate)
        if let toggle { form.isOpen24Hours = toggle }
        try await saver().save(form, to: .new(from: candidate), photos: .init())

        #expect(try committedBathrooms().first?.isOpen24HoursIfKnown == expected)
    }

    @Test func editingABathroomWithUnknownHoursKeepsThemUnknown() async throws {
        let bathroom = try storedBathroom()
        bathroom.isOpen24HoursKnown = false
        try context.save()

        var form = BathroomForm(bathroom: bathroom)
        form.rating = 5
        try await saver().save(form, to: .edit(bathroom), photos: .init(kept: bathroom.imageFileNames))

        #expect(try committedBathrooms().first?.isOpen24HoursIfKnown == nil)
    }

    // MARK: - Delete

    private func linkedCandidate(seedVersion: Int, isDismissed: Bool = false, to bathroom: Bathroom) throws -> Candidate {
        let candidate = Candidate(sourceID: "atp:a", brandKey: "target", name: "Target", latitude: 38.8, longitude: -77.0,
                                  isDismissed: isDismissed, seedVersion: seedVersion)
        context.insert(candidate)
        bathroom.sourceID = candidate.sourceID
        try context.save()
        return candidate
    }

    private func committedCandidates() throws -> [Candidate] {
        try ModelContext(container).fetch(FetchDescriptor<Candidate>())
    }

    @Test func deleteCommitsBeforeRemovingPhotos() throws {
        let bathroom = try storedBathroom()
        var photosExistedAtCommit = false

        try BathroomSaver.delete(bathroom, from: context, photoRoot: photoRoot, lastImportedVersion: 1, commit: { context in
            photosExistedAtCommit = try !files(of: bathroom).isEmpty
            try context.save()
        })

        #expect(photosExistedAtCommit)
        #expect(try committedBathrooms().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: photoRoot.appendingPathComponent(bathroom.id.uuidString).path))
    }

    @Test func failedDeleteKeepsBathroomAndPhotos() throws {
        let bathroom = try storedBathroom()
        let before = try files(of: bathroom)

        #expect(throws: BathroomSaver.SaveError.deleteFailed) {
            try BathroomSaver.delete(bathroom, from: context, photoRoot: photoRoot, lastImportedVersion: 1,
                                     commit: { _ in throw CommitFailed() })
        }

        #expect(try committedBathrooms().count == 1)
        #expect(try files(of: bathroom) == before)
        #expect(!context.hasChanges)
    }

    @Test func deletingABathroomLinkedToADroppedCandidateDeletesTheCandidate() throws {
        let bathroom = try storedBathroom()
        _ = try linkedCandidate(seedVersion: 1, to: bathroom)

        try BathroomSaver.delete(bathroom, from: context, photoRoot: photoRoot, lastImportedVersion: 2)

        #expect(try committedCandidates().isEmpty)
    }

    @Test func deletingABathroomLinkedToACandidateStillInTheSeedKeepsTheCandidate() throws {
        let bathroom = try storedBathroom()
        _ = try linkedCandidate(seedVersion: 2, to: bathroom)

        try BathroomSaver.delete(bathroom, from: context, photoRoot: photoRoot, lastImportedVersion: 2)

        #expect(try committedCandidates().map(\.sourceID) == ["atp:a"])
        #expect(try committedCandidates().first?.isDismissed == false)
    }

    @Test func deletingABathroomLinkedToADismissedCandidateKeepsItDismissed() throws {
        let bathroom = try storedBathroom()
        _ = try linkedCandidate(seedVersion: 1, isDismissed: true, to: bathroom)

        try BathroomSaver.delete(bathroom, from: context, photoRoot: photoRoot, lastImportedVersion: 2)

        #expect(try committedCandidates().map(\.sourceID) == ["atp:a"])
        #expect(try committedCandidates().first?.isDismissed == true)
    }

    // MARK: - Orphan sweep

    @Test func sweepRemovesOrphanedFoldersAndUnlistedFiles() throws {
        let bathroom = try storedBathroom()
        let listed = bathroom.imageFileNames[0]
        let unlisted = bathroom.imageFileNames[1]
        bathroom.imageFileNames = [listed]
        try context.save()
        let orphanID = UUID()
        _ = try ImageStorage.saveImage(photo(), bathroomID: orphanID, root: photoRoot)

        try BathroomSaver.sweepOrphanedPhotos(in: container, root: photoRoot, writtenBefore: .distantFuture)

        #expect(!FileManager.default.fileExists(atPath: photoRoot.appendingPathComponent(orphanID.uuidString).path))
        #expect(fileExists(listed, of: bathroom))
        #expect(fileExists(listed.replacingOccurrences(of: ".jpg", with: "_thumb.jpg"), of: bathroom))
        #expect(!fileExists(unlisted, of: bathroom))
        #expect(!fileExists(unlisted.replacingOccurrences(of: ".jpg", with: "_thumb.jpg"), of: bathroom))
    }

    @Test func sweepLeavesFilesWrittenAfterItStarted() throws {
        let orphanID = UUID()
        _ = try ImageStorage.saveImage(photo(), bathroomID: orphanID, root: photoRoot)

        try BathroomSaver.sweepOrphanedPhotos(in: container, root: photoRoot, writtenBefore: .distantPast)

        #expect(FileManager.default.fileExists(atPath: photoRoot.appendingPathComponent(orphanID.uuidString).path))
    }

    // MARK: - Address

    @Test func editKeepsStoredAddressWhenPinStaysWithinTolerance() async throws {
        let bathroom = try storedBathroom(address: "1 Main St")
        var geocoded = false
        var edited = BathroomForm(bathroom: bathroom)
        edited.coordinate = moved(Self.origin, meters: 5)

        try await saver(geocode: { _ in geocoded = true; return "Worse St" })
            .save(edited, to: .edit(bathroom), photos: .init(kept: bathroom.imageFileNames))

        #expect(!geocoded)
        #expect(bathroom.address == "1 Main St")
    }

    @Test func editGeocodesWhenPinMoves() async throws {
        let bathroom = try storedBathroom(address: "1 Main St")
        var edited = BathroomForm(bathroom: bathroom)
        edited.coordinate = moved(Self.origin, meters: 100)

        try await saver(geocode: { _ in "9 New Ave" })
            .save(edited, to: .edit(bathroom), photos: .init(kept: bathroom.imageFileNames))

        #expect(bathroom.address == "9 New Ave")
    }

    @Test func slowGeocodeFallsBackAfterTheTimeout() async throws {
        let slow = saver(
            geocode: { _ in try? await Task.sleep(for: .seconds(30)); return "Too Late St" },
            geocodeTimeout: .milliseconds(200)
        )
        let clock = ContinuousClock()
        let start = clock.now
        let bathroom = try await slow.save(form(), to: .new(from: nil), photos: .init(), fallbackAddress: "Last Known St")

        // Well under the 30 s geocode, with room for a slow CI runner.
        #expect(clock.now - start < .seconds(10))
        #expect(bathroom.address == "Last Known St")
    }

    // MARK: - Unsaved changes

    @Test func unchangedFormHasNoChangesEvenIfThePinDriftsSlightly() {
        let original = form()
        var drifted = original
        drifted.coordinate = moved(Self.origin, meters: 2)
        #expect(!drifted.hasChanges(from: original))
    }

    @Test(arguments: [
        { (f: inout BathroomForm) in f.name = "Other" },
        { (f: inout BathroomForm) in f.requiresReceiptCode = true },
        { (f: inout BathroomForm) in f.stallType = .multi },
        { (f: inout BathroomForm) in f.hasExtraToiletPaper = true },
        { (f: inout BathroomForm) in f.dispenserRating = 3 },
        { (f: inout BathroomForm) in f.waitTime = .usuallyBusy },
        { (f: inout BathroomForm) in f.dateVisited = .distantPast },
        { (f: inout BathroomForm) in f.coordinate.latitude += 0.001 },
    ] as [@Sendable (inout BathroomForm) -> Void])
    func anyChangedFieldCountsAsUnsaved(change: @Sendable (inout BathroomForm) -> Void) {
        let original = form()
        var edited = original
        change(&edited)
        #expect(edited.hasChanges(from: original))
    }
}
