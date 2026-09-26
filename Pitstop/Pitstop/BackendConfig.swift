import Foundation
import os
import Supabase

/// Backend endpoint and publishable key, injected at build time from
/// `Config.xcconfig` through Info.plist. The publishable key is a public
/// project identifier; row-level security on the server is what limits access.
enum BackendConfig {

    static let url: URL = {
        if let value = infoValue("BackendURL"), let url = URL(string: value) {
            return url
        }
        Logger(subsystem: "Pitstop", category: "BackendConfig")
            .error("BackendURL is not set. Copy Config.xcconfig.example to Config.xcconfig.")
        // Lets the app launch without a backend; every network call then fails fast.
        return URL(string: "https://backend.invalid")!
    }()

    static let publishableKey: String = infoValue("BackendPublishableKey") ?? ""

    /// One client for the app's lifetime so auth token storage and refresh are not raced.
    static let client = SupabaseClient(supabaseURL: url, supabaseKey: publishableKey)

    private static func infoValue(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty else { return nil }
        return value
    }
}
