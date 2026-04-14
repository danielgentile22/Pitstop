//
//  SupabaseConfig.swift
//  GeoPoop
//
//  Single source of truth for Supabase project credentials.
//
//  Security note:
//    The `publishableKey` (formerly called "anon key") is intentionally safe
//    to ship in the app binary. It is a project identifier, not a secret.
//    Row Level Security (RLS) policies in Supabase enforce what this key can
//    actually read/write — the key alone grants nothing beyond what RLS allows.
//
//    The SECRET key (found in Supabase dashboard → Settings → API → Secret)
//    must NEVER appear in client code. It bypasses RLS entirely.
//
//  The shared `client` is a static singleton intentionally — SupabaseClient
//  manages its own connection pool and auth token storage. Creating multiple
//  instances would waste memory and cause token-refresh races.
//

import Foundation
import Supabase

enum SupabaseConfig {

    /// The URL of our Supabase project. Found in Settings → API.
    static let projectURL    = URL(string: "https://xrxkbnigywknnbvaxcsx.supabase.co")!

    /// The publishable (anon) key. Safe to be public. RLS is the security layer.
    static let publishableKey = "sb_publishable_UQ_mFG0BEKiUiCKyQHjEMg_1X9zvA53"

    /// Shared Supabase client — one instance for the app's entire lifetime.
    /// Injected into SupabaseService, which is the only caller.
    static let client = SupabaseClient(
        supabaseURL:  projectURL,
        supabaseKey:  publishableKey
    )
}
