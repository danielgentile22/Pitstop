import SwiftUI
import SwiftData

@main
struct PitstopApp: App {

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // The store is the only copy of the user's data, so a schema change needs a migration, never a wipe.
        .modelContainer(for: Bathroom.self)
    }
}
