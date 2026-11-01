import SwiftUI
import SwiftData
import os

@main
struct PitstopApp: App {

    // The store is the only copy of the user's data, so a schema change needs a migration, never a wipe.
    private let store: Result<ModelContainer, StoreOpenFailure>

    init() {
        let configuration = ModelConfiguration()
        do {
            let container = try ModelContainer(
                for: Schema(versionedSchema: LatestSchema.self),
                migrationPlan: PitstopMigrationPlan.self,
                configurations: configuration
            )
            store = .success(container)
            Self.importBundledSeed(into: container)
            Self.sweepOrphanedPhotos(in: container)
        } catch {
            store = .failure(StoreRecovery.recover(storeAt: configuration.url, from: error))
        }
    }

    var body: some Scene {
        WindowGroup {
            switch store {
            case .success(let container):
                ContentView()
                    .modelContainer(container)
            case .failure(let failure):
                StoreOpenFailureView(failure: failure)
            }
        }
    }

    /// Once per launch, off the main thread. Files written after launch belong to a save in flight, so they stay.
    private static func sweepOrphanedPhotos(in container: ModelContainer) {
        let root = ImageStorage.defaultRoot
        let launched = Date()
        Task.detached(priority: .background) {
            do {
                try BathroomSaver.sweepOrphanedPhotos(in: container, root: root, writtenBefore: launched)
            } catch {
                Logger(subsystem: "com.danielgentile.GeoPoop", category: "PhotoSweep")
                    .error("Photo sweep failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Once per launch, off the main thread so a large seed never blocks launch.
    private static func importBundledSeed(into container: ModelContainer) {
        Task.detached(priority: .utility) {
            do {
                let seed = try CandidateImporter.loadBundledSeed()
                try CandidateImporter.importIfNewer(seed, into: container, defaults: .standard)
            } catch {
                Logger(subsystem: "com.danielgentile.GeoPoop", category: "CandidateImporter")
                    .error("Seed import failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
