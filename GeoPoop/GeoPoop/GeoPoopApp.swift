//
//  GeoPoopApp.swift
//  GeoPoop
//
//  App entry point. Owns long-lived singletons:
//    • ModelContainer  — the SwiftData database (local persistence)
//    • SupabaseService — auth + cloud sync
//    • NetworkMonitor  — connectivity state; triggers syncQueue drain on reconnect
//    • SyncQueue       — persistent offline operation queue
//
//  Auth gate:
//    The root WindowGroup switches between three states:
//      1. currentUser != nil           → ContentView  (main app)
//      2. pendingConfirmationEmail != nil → EmailConfirmationView (await email click)
//      3. Otherwise                    → LoginView    (sign in / sign up)
//
//    Because SupabaseService is @Observable, SwiftUI automatically re-renders
//    the gate when auth state changes — no manual navigation stack needed.
//
//  Why @State for service singletons?
//    In a SwiftUI App struct, `@State` persists the stored value across body
//    re-evaluations (similar to how @StateObject works for ObservableObject).
//    Using a plain `let` or `var` would recreate the instance each time SwiftUI
//    rebuilds the App struct, resetting all auth state.
//
//  Offline sync drain:
//    When NetworkMonitor transitions from offline → online, any pending operations
//    stored in SyncQueue are retried automatically via .onChange(of: isConnected).
//

import SwiftUI
import SwiftData

@main
struct GeoPoopApp: App {

    // MARK: - Singletons

    /// SwiftData store. Created in init() so it's ready before any view renders.
    let container: ModelContainer

    /// Cloud service singleton — @State keeps the same instance alive forever.
    @State private var supabaseService = SupabaseService()

    /// Network connectivity monitor — drives offline banner and auto-drain trigger.
    @State private var networkMonitor = NetworkMonitor()

    /// Persistent offline operation queue — retried when connectivity is restored.
    @State private var syncQueue = SyncQueue()

    // MARK: - Init

    init() {
        let schema = Schema([Bathroom.self])
        let modelConfig = ModelConfiguration(schema: schema)
        do {
            container = try ModelContainer(for: schema, configurations: modelConfig)
        } catch {
            // Schema changed — wipe the local store and recreate.
            // Supabase will re-sync cloud data on the next launch.
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

    // MARK: - Scene

    var body: some Scene {
        WindowGroup {
            Group {
                if supabaseService.currentUser != nil {
                    // Signed in — show the main app
                    ContentView()
                } else if let email = supabaseService.pendingConfirmationEmail {
                    // Signed up but email not yet confirmed
                    EmailConfirmationView(email: email)
                } else {
                    // Not signed in — show login / sign-up / forgot-password
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
                // Drain pending offline operations as soon as we're back online
                Task {
                    let context = ModelContext(container)
                    await syncQueue.drain(supabase: supabaseService, context: context)
                }
            }
            .task {
                // Check whether the user's Apple credential is still valid.
                // If they revoked the app in Settings → Apple ID → Sign in with
                // Apple, this will sign them out locally before the app loads.
                await supabaseService.checkAppleCredentialState()
            }
        }
    }
}
