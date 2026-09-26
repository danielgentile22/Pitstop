import SwiftUI
import SwiftData

@main
struct PitstopApp: App {

    let container: ModelContainer

    @State private var supabaseService = SupabaseService()

    @State private var networkMonitor = NetworkMonitor()

    @State private var syncQueue = SyncQueue()

    init() {
        let schema = Schema([Bathroom.self])
        let modelConfig = ModelConfiguration(schema: schema)
        do {
            container = try ModelContainer(for: schema, configurations: modelConfig)
        } catch {
            // Schema changed: wipe the local store and recreate it. The next sync repopulates it.
            let storeURL = modelConfig.url
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + "-wal"))
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + "-shm"))
            do {
                container = try ModelContainer(for: schema, configurations: modelConfig)
            } catch {
                fatalError("Failed to create ModelContainer: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if supabaseService.currentUser != nil {
                    ContentView()
                } else if let email = supabaseService.pendingConfirmationEmail {
                    EmailConfirmationView(email: email)
                } else {
                    LoginView()
                }
            }
            .environment(supabaseService)
            .environment(networkMonitor)
            .environment(syncQueue)
            .modelContainer(container)
            .animation(.easeInOut(duration: 0.3), value: supabaseService.currentUser == nil)
            .onChange(of: networkMonitor.isConnected) { _, isConnected in
                guard isConnected else { return }
                Task {
                    let context = ModelContext(container)
                    await syncQueue.drain(supabase: supabaseService, context: context)
                }
            }
            .task {
                // Signs out locally if the user revoked Sign in with Apple for this app in Settings.
                await supabaseService.checkAppleCredentialState()
            }
        }
    }
}
