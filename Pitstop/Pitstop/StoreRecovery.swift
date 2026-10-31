import SwiftUI
import os

/// Why the app is showing the failure screen instead of the user's data.
struct StoreOpenFailure: Error {
    /// False when the backup copy failed too; the store itself is still in place.
    let isBackedUp: Bool
}

/// Handles a store that won't open: logs, copies it aside, never deletes it.
enum StoreRecovery {

    private static let logger = Logger(subsystem: "com.danielgentile.GeoPoop", category: "StoreRecovery")

    /// Documents survives app updates and sits next to the photos, so the copy outlives a fixed build.
    private static let backupsFolderName = "StoreBackups"

    static func recover(storeAt storeURL: URL, from error: Error) -> StoreOpenFailure {
        logger.error("Could not open the SwiftData store at \(storeURL.path, privacy: .public): \(String(describing: error), privacy: .public)")
        do {
            let folder = try backUpStoreFiles(at: storeURL)
            logger.notice("Backed up the store to \(folder.path, privacy: .public)")
            return StoreOpenFailure(isBackedUp: true)
        } catch {
            logger.error("Could not back up the store: \(String(describing: error), privacy: .public)")
            return StoreOpenFailure(isBackedUp: false)
        }
    }

    /// Copies the SQLite file and its `-wal` and `-shm` siblings into `Documents/StoreBackups/{timestamp}/`.
    private static func backUpStoreFiles(at storeURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let timestamp = Date.now.ISO8601Format(.iso8601.dateSeparator(.dash).timeSeparator(.omitted))
        let folder = ImageStorage.documentsURL
            .appendingPathComponent(backupsFolderName)
            .appendingPathComponent(timestamp)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        let storeFiles = ["", "-wal", "-shm"]
            .map { URL(fileURLWithPath: storeURL.path + $0) }
            .filter { fileManager.fileExists(atPath: $0.path) }
        for file in storeFiles {
            try fileManager.copyItem(at: file, to: folder.appendingPathComponent(file.lastPathComponent))
        }
        return folder
    }
}

struct StoreOpenFailureView: View {

    let failure: StoreOpenFailure

    var body: some View {
        ContentUnavailableView {
            Label("Pitstop Can't Open Your Data", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            if failure.isBackedUp {
                Text("Your saved bathrooms couldn't be loaded. Nothing was deleted, and a backup copy was saved on this iPhone. Please don't delete the app until an update fixes this.")
            } else {
                Text("Your saved bathrooms couldn't be loaded, and the backup copy failed too. Nothing was deleted. Please don't delete the app until an update fixes this.")
            }
        }
    }
}
