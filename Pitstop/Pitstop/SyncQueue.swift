import Foundation
import Observation
import os
import SwiftData

private let logger = Logger(subsystem: "Pitstop", category: "SyncQueue")

// MARK: - PendingOperation

enum PendingOperation: Codable, Identifiable, Hashable {
    case upsertBathroom(bathroomID: UUID)
    case deleteBathroom(bathroomID: UUID, fileNames: [String])
    case uploadPhoto(bathroomID:    UUID, fileName:  String)
    case deletePhotos(bathroomID:   UUID, fileNames: [String])

    /// Derived from the parameters, so re-enqueueing the same operation replaces the pending one.
    var id: String {
        switch self {
        case .upsertBathroom(let id):
            return "upsert-\(id)"
        case .deleteBathroom(let id, _):
            return "delete-\(id)"
        case .uploadPhoto(let id, let name):
            return "upload-\(id)-\(name)"
        case .deletePhotos(let id, let names):
            return "delphotos-\(id)-\(names.sorted().joined(separator: ","))"
        }
    }
}

// MARK: - SyncQueue

/// Cloud operations that failed while offline, persisted to disk and replayed on reconnect.
@Observable
final class SyncQueue {

    // MARK: - Observed State

    private(set) var pendingCount: Int = 0

    // MARK: - Private Storage

    private var operations: [PendingOperation] = [] {
        didSet {
            pendingCount = operations.count
            persist()
        }
    }

    private static let fileName = "sync_queue.json"

    private static var queueFileURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    // MARK: - Init

    init() { load() }

    // MARK: - Enqueue

    func enqueue(_ operation: PendingOperation) {
        operations.removeAll { $0.id == operation.id }
        operations.append(operation)
    }

    // MARK: - Drain

    /// Runs every queued operation; failures stay queued for the next drain.
    /// Overlapping drains may replay an operation twice. That is safe because every
    /// operation is an upsert or a delete, so repeating it leaves the server unchanged.
    func drain(supabase: SupabaseService, context: ModelContext) async {
        guard !operations.isEmpty else { return }

        var remaining: [PendingOperation] = []
        // Snapshot so operations enqueued mid-drain survive the final merge.
        let snapshot = operations

        for operation in snapshot {
            let succeeded = await execute(operation, supabase: supabase, context: context)
            if !succeeded { remaining.append(operation) }
        }

        let drainedIDs = Set(snapshot.map(\.id))
        let newlyEnqueued = operations.filter { !drainedIDs.contains($0.id) }
        operations = remaining + newlyEnqueued
    }

    // MARK: - Clear

    /// Called on sign-out so the next user never pushes the previous user's data.
    func clear() {
        operations = []
    }

    // MARK: - Execute

    private func execute(
        _ operation: PendingOperation,
        supabase: SupabaseService,
        context: ModelContext
    ) async -> Bool {
        do {
            switch operation {

            case .upsertBathroom(let bathroomID):
                let descriptor = FetchDescriptor<Bathroom>(
                    predicate: #Predicate { $0.id == bathroomID }
                )
                // Deleted locally since enqueueing: drop the operation.
                guard let bathroom = (try? context.fetch(descriptor))?.first else { return true }
                try await supabase.upsertRemote(bathroom)

            case .deleteBathroom(let bathroomID, let fileNames):
                await supabase.deleteWithPhotos(bathroomID: bathroomID, fileNames: fileNames)

            case .uploadPhoto(let bathroomID, let fileName):
                // Deleted locally since enqueueing: drop the operation.
                guard let image = await ImageStorage.loadImageAsync(
                    bathroomID: bathroomID, fileName: fileName
                ) else { return true }
                try await supabase.uploadPhoto(image, bathroomID: bathroomID, fileName: fileName)

            case .deletePhotos(let bathroomID, let fileNames):
                try await supabase.deletePhotos(bathroomID: bathroomID, fileNames: fileNames)
            }
            return true

        } catch {
            logger.error("Operation \(operation.id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Persistence

    private func persist() {
        do {
            let data = try JSONEncoder().encode(operations)
            try data.write(to: Self.queueFileURL, options: .atomic)
        } catch {
            logger.error("Persist failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func load() {
        guard
            let data   = try? Data(contentsOf: Self.queueFileURL),
            let loaded = try? JSONDecoder().decode([PendingOperation].self, from: data)
        else { return }
        operations   = loaded
        pendingCount = loaded.count
    }
}
