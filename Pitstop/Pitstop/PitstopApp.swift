import SwiftUI
import SwiftData
import os

@main
struct PitstopApp: App {

    // The store is the only copy of the user's data, so a schema change needs a migration, never a wipe.
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Bathroom.self, Candidate.self)
        } catch {
            fatalError("Could not open the SwiftData store: \(error)")
        }
        Self.importBundledSeed(into: container)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
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
