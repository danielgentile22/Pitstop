import CoreLocation
import Foundation
import SwiftData
import UIKit

/// Saves the add and edit form. The store is the only copy of the user's data, so the order is fixed:
/// resolve the address, refuse a duplicate visit, write new photos, apply the form, commit,
/// and only then delete photos the user removed. A failure removes this attempt's files,
/// rolls the context back, and throws, so the form can stay open.
struct BathroomSaver {

    enum Target {
        /// A new Bathroom, logged from `candidate` when non-nil.
        case new(from: Candidate?)
        case edit(Bathroom)
    }

    struct PhotoChanges {
        /// Existing file names still in the form, in order. Any other stored file is deleted after the commit.
        var kept:  [String]  = []
        var added: [UIImage] = []
    }

    enum SaveError: LocalizedError, Equatable {
        case alreadyLogged
        case photoWriteFailed
        case commitFailed
        case deleteFailed

        var errorDescription: String? {
            switch self {
            case .alreadyLogged:    return "You already logged a visit to this place."
            case .photoWriteFailed: return "A photo couldn't be saved, so nothing was changed. Try again."
            case .commitFailed:     return "The bathroom couldn't be saved, so nothing was changed. Try again."
            case .deleteFailed:     return "The bathroom couldn't be deleted. Try again."
            }
        }
    }

    let context: ModelContext
    var photoRoot: URL = ImageStorage.defaultRoot
    let geocode: (CLLocationCoordinate2D) async -> String?
    var geocodeTimeout: Duration = .seconds(2)
    var commit: (ModelContext) throws -> Void = { try $0.save() }

    // MARK: - Save

    /// `fallbackAddress` is used when the pin moved and reverse geocoding fails or times out.
    @discardableResult
    func save(
        _ form: BathroomForm,
        to target: Target,
        photos: PhotoChanges,
        fallbackAddress: String? = nil
    ) async throws -> Bathroom {
        let address = await resolveAddress(for: form, target: target) ?? fallbackAddress

        let bathroom: Bathroom
        let removed: [String]
        switch target {
        case .edit(let existing):
            bathroom = existing
            removed  = existing.imageFileNames.filter { !photos.kept.contains($0) }
        case .new(let candidate):
            if let candidate, try isLogged(candidate) { throw SaveError.alreadyLogged }
            bathroom = Bathroom(name: form.name, latitude: form.latitude, longitude: form.longitude)
            removed  = []
        }

        var written: [String] = []
        do {
            for photo in photos.added {
                written.append(try await ImageStorage.saveImageAsync(photo, bathroomID: bathroom.id, root: photoRoot))
            }
        } catch {
            discard(written, of: bathroom)
            throw SaveError.photoWriteFailed
        }

        form.apply(to: bathroom)
        bathroom.address        = address
        bathroom.imageFileNames = photos.kept + written
        if case .new(let candidate) = target {
            bathroom.sourceID = candidate?.sourceID
            // Logging a visit is the user's answer to "no public restroom here".
            candidate?.isDismissed = false
            context.insert(bathroom)
        }

        do {
            try commit(context)
        } catch {
            context.rollback()
            discard(written, of: bathroom)
            throw SaveError.commitFailed
        }

        discard(removed, of: bathroom)
        return bathroom
    }

    // MARK: - Delete

    /// Deletes `bathroom`, commits, and only then removes its photo folder. A Candidate it was logged from
    /// is deleted too when a newer seed already dropped it (not dismissed, last seen before the latest import),
    /// since the importer never deletes a linked Candidate and a closed store must not come back.
    static func delete(
        _ bathroom: Bathroom,
        from context: ModelContext,
        photoRoot: URL = ImageStorage.defaultRoot,
        lastImportedVersion: Int = UserDefaults.standard.integer(forKey: CandidateImporter.lastImportedVersionKey),
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        let id = bathroom.id
        do {
            if let sourceID = bathroom.sourceID {
                let dropped = try context.fetch(FetchDescriptor<Candidate>(predicate: #Predicate {
                    $0.sourceID == sourceID && !$0.isDismissed && $0.seedVersion < lastImportedVersion
                }))
                dropped.forEach(context.delete)
            }
            context.delete(bathroom)
            try commit(context)
        } catch {
            context.rollback()
            throw SaveError.deleteFailed
        }
        ImageStorage.deleteAllImages(bathroomID: id, root: photoRoot)
    }

    // MARK: - Orphan Sweep

    /// Removes photo folders with no matching Bathroom and files a Bathroom no longer lists. Skips anything
    /// created at or after `cutoff`, so a save in flight while the sweep runs keeps its new files.
    /// Runs in its own context so it can be called off the main thread.
    nonisolated static func sweepOrphanedPhotos(in container: ModelContainer, root: URL, writtenBefore cutoff: Date) throws {
        let listed = Dictionary(
            try ModelContext(container).fetch(FetchDescriptor<Bathroom>()).map { bathroom in
                (bathroom.id.uuidString, Set(bathroom.imageFileNames.flatMap { [$0, ImageStorage.thumbnailName(for: $0)] }))
            },
            uniquingKeysWith: { first, _ in first }
        )

        let fileManager = FileManager.default
        func isOld(_ url: URL) -> Bool {
            guard let created = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate else { return false }
            return created < cutoff
        }
        func contents(of url: URL) -> [URL] {
            (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.creationDateKey])) ?? []
        }

        for folder in contents(of: root) {
            guard let names = listed[folder.lastPathComponent] else {
                if isOld(folder) { try? fileManager.removeItem(at: folder) }
                continue
            }
            for file in contents(of: folder) where !names.contains(file.lastPathComponent) && isOld(file) {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    // MARK: - Helpers

    private func isLogged(_ candidate: Candidate) throws -> Bool {
        let sourceID: String? = candidate.sourceID
        return try context.fetchCount(FetchDescriptor<Bathroom>(predicate: #Predicate { $0.sourceID == sourceID })) > 0
    }

    private func discard(_ fileNames: [String], of bathroom: Bathroom) {
        for fileName in fileNames {
            ImageStorage.deleteImage(bathroomID: bathroom.id, fileName: fileName, root: photoRoot)
        }
    }

    /// The stored address while the pin has not moved from where it started; otherwise a reverse geocode,
    /// waiting at most `geocodeTimeout`. Nil when neither is available.
    private func resolveAddress(for form: BathroomForm, target: Target) async -> String? {
        let origin: (coordinate: CLLocationCoordinate2D, address: String?)?
        switch target {
        case .edit(let bathroom):   origin = (bathroom.coordinate, bathroom.address)
        case .new(let candidate?):  origin = (candidate.coordinate, candidate.address)
        case .new(nil):             origin = nil
        }
        if let origin, let address = origin.address, !address.isEmpty, !form.pinMoved(from: origin.coordinate) {
            return address
        }
        return await geocodeWithTimeout(form.coordinate)
    }

    private func geocodeWithTimeout(_ coordinate: CLLocationCoordinate2D) async -> String? {
        let geocode = geocode
        let timeout = geocodeTimeout
        return await withCheckedContinuation { continuation in
            let race   = FirstResult(continuation)
            let lookup = Task { race.finish(await geocode(coordinate)) }
            let timer  = Task {
                try? await Task.sleep(for: timeout)
                race.finish(nil)
            }
            race.onFinish = { lookup.cancel(); timer.cancel() }
        }
    }
}

/// Resumes a continuation with whichever of two tasks finishes first. Main-actor isolated, so no lock.
private final class FirstResult {
    private var continuation: CheckedContinuation<String?, Never>?
    var onFinish: () -> Void = {}

    init(_ continuation: CheckedContinuation<String?, Never>) {
        self.continuation = continuation
    }

    func finish(_ value: String?) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: value)
        onFinish()
    }
}
