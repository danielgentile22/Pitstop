//
//  SyncQueue.swift
//  GeoPoop
//
//  Persistent queue of cloud operations that failed because the device was
//  offline. Operations are written atomically to a JSON file in the app's
//  Documents directory so the queue survives app restarts and crashes.
//
//  The queue is drained automatically by ContentView whenever the device
//  regains network connectivity (observed via NetworkMonitor).
//
//  ── Supported Operations ──────────────────────────────────────────────────
//
//    upsertBathroom  — push a modified local Bathroom to the cloud.
//    deleteBathroom  — remove a bathroom row and its photos from the cloud.
//    uploadPhoto     — upload a single photo file to Supabase Storage.
//    deletePhotos    — remove a set of photo files from Supabase Storage.
//
//  ── Idempotency ───────────────────────────────────────────────────────────
//
//  Each operation carries a stable string `id` computed from its parameters.
//  Re-enqueueing an already-pending operation replaces the existing entry
//  rather than appending a duplicate, so rapid offline edits collapse to a
//  single pending upsert.
//
//  ── Drain Strategy ────────────────────────────────────────────────────────
//
//  Operations are attempted sequentially. Any that fail (still no network,
//  server error) remain in the queue for the next drain. Operations whose
//  local prerequisite no longer exists (bathroom deleted, photo deleted) are
//  silently discarded — they are considered stale.
//

import Foundation
import Observation
import SwiftData

// MARK: - PendingOperation

enum PendingOperation: Codable, Identifiable, Hashable {
    case upsertBathroom(bathroomID: UUID)
    case deleteBathroom(bathroomID: UUID, fileNames: [String])
    case uploadPhoto(bathroomID:    UUID, fileName:  String)
    case deletePhotos(bathroomID:   UUID, fileNames: [String])

    /// Stable identifier used for deduplication on re-enqueue.
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

@Observable
final class SyncQueue {

    // MARK: - Observed State

    /// Number of operations waiting to be pushed to the cloud.
    /// Exposed so the toolbar can show a badge when > 0.
    private(set) var pendingCount: Int = 0

    // MARK: - Private Storage

    /// The live operation list. Every mutation persists to disk automatically.
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

    /// Adds an operation to the queue, replacing any existing entry with the same ID.
    func enqueue(_ operation: PendingOperation) {
        operations.removeAll { $0.id == operation.id }
        operations.append(operation)
    }

    // MARK: - Drain

    /// Attempts to execute every queued operation against the cloud.
    ///
    /// Successful operations are removed. Failed operations stay in the queue
    /// for the next drain. The drain is non-blocking — a single failure does
    /// not stop subsequent operations from being attempted.
    ///
    /// Safe to call concurrently; if called while already draining, pending
    /// operations may interleave — this is acceptable because all operations
    /// are idempotent on the server (upsert + delete).
    func drain(supabase: SupabaseService, context: ModelContext) async {
        guard !operations.isEmpty else { return }

        var remaining: [PendingOperation] = []
        // Snapshot the current list so new enqueues during drain don't get lost
        let snapshot = operations

        for operation in snapshot {
            let succeeded = await execute(operation, supabase: supabase, context: context)
            if !succeeded { remaining.append(operation) }
        }

        // Merge: keep operations that were enqueued during the drain AND any that failed
        let drainedIDs = Set(snapshot.map(\.id))
        let newlyEnqueued = operations.filter { !drainedIDs.contains($0.id) }
        operations = remaining + newlyEnqueued
    }

    // MARK: - Clear

    /// Discards all pending operations. Called on sign-out so a subsequent
    /// user doesn't accidentally push the previous user's queued data.
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
                // If the bathroom was deleted locally since it was enqueued, discard
                guard let bathroom = (try? context.fetch(descriptor))?.first else { return true }
                try await supabase.upsertRemote(bathroom)

            case .deleteBathroom(let bathroomID, let fileNames):
                await supabase.deleteWithPhotos(bathroomID: bathroomID, fileNames: fileNames)

            case .uploadPhoto(let bathroomID, let fileName):
                // If the image was deleted locally since enqueueing, discard
                guard let image = await ImageStorage.loadImageAsync(
                    bathroomID: bathroomID, fileName: fileName
                ) else { return true }
                try await supabase.uploadPhoto(image, bathroomID: bathroomID, fileName: fileName)

            case .deletePhotos(let bathroomID, let fileNames):
                try await supabase.deletePhotos(bathroomID: bathroomID, fileNames: fileNames)
            }
            return true

        } catch {
            print("[SyncQueue] failed: \(operation.id) — \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Persistence

    private func persist() {
        do {
            let data = try JSONEncoder().encode(operations)
            try data.write(to: Self.queueFileURL, options: .atomic)
        } catch {
            print("[SyncQueue] persist error: \(error)")
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
